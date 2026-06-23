#!/usr/bin/env bash
set -euo pipefail

# Ralph Loop — spawns isolated claude-ralph processes per iteration.
# Bash port of pi-ralph-loop: fresh context per iteration, state on disk,
# promise-gated transitions. Only the harness differs from pi-ralph; the loop
# system and philosophy match. See docs/pi-ralph-parity-plan.md + docs/adr/.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_RALPH="${CLAUDE_RALPH_PATH:-$SCRIPT_DIR/claude-ralph}"

MAX_ITERATIONS=30
COMPLETION_PROMISE=""
MODEL=""
EFFORT=""
IDLE_TIMEOUT=600          # seconds of no output growth before the watchdog kills
MAX_RETRIES=5             # provider-wait/rejection ceiling (matches pi-ralph)
VERBOSE=false
DRY_RUN=false
PROMPT_PARTS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    --max-iterations|-n) MAX_ITERATIONS="$2"; shift 2 ;;
    --completion-promise|-c) COMPLETION_PROMISE="$2"; shift 2 ;;
    --idle-timeout) IDLE_TIMEOUT="$2"; shift 2 ;;
    --max-retries) MAX_RETRIES="$2"; shift 2 ;;
    --model|-m) MODEL="$2"; shift 2 ;;
    --effort) EFFORT="$2"; shift 2 ;;
    --budget) echo "⚠️  --budget is deprecated and ignored (no per-token billing on subscription)." >&2
              shift; [[ $# -gt 0 ]] && shift ;;
    --verbose|-v) VERBOSE=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help)
      cat <<'EOF'
ralph-loop — iterate a task with isolated claude sessions (bash port of pi-ralph-loop)

Usage: /ralph-loop PROMPT [options]
       /ralph-loop @.ralph/prompt.md [options]

Options:
  -n, --max-iterations N       Cap iterations (default: 30)
  -c, --completion-promise T   Custom completion tag for direct (non-bundle) mode
  --idle-timeout SECONDS       Kill an iteration after this much silence (default: 600)
  --max-retries N              Provider-wait/rejection ceiling (default: 5)
  -m, --model MODEL            Override model
  --effort LEVEL               Override effort (low/medium/high)
  --dry-run                    Print iteration 1 prompt and exit (no run)
  -v, --verbose                Full output per iteration
  -h, --help                   This message

Bundle mode (auto): when .ralph/items.json exists ({version,items[]}), promises
are gated — NEXT flips exactly one item, COMPLETE requires all items pass.
EOF
      exit 0 ;;
    *) PROMPT_PARTS+=("$1"); shift ;;
  esac
done

PROMPT="${PROMPT_PARTS[*]:-}"
[[ -z "$PROMPT" ]] && { echo "❌ No prompt. Usage: /ralph-loop \"task\" -c DONE -n 20" >&2; exit 1; }

# @file syntax: read prompt from file
if [[ "$PROMPT" == @* ]]; then
  PROMPT_FILE="${PROMPT#@}"
  [[ -f "$PROMPT_FILE" ]] || { echo "❌ Prompt file not found: $PROMPT_FILE" >&2; exit 1; }
  PROMPT="$(cat "$PROMPT_FILE")"
fi

# Resolve claude-ralph
if [[ ! -x "$CLAUDE_RALPH" ]]; then
  CLAUDE_RALPH="$(command -v claude-ralph 2>/dev/null || true)"
  [[ -z "$CLAUDE_RALPH" ]] && { echo "❌ claude-ralph not found. Check CLAUDE_RALPH_PATH or install." >&2; exit 1; }
fi

# jq is required: we parse stream-json output and gate the rich items.json with it.
command -v jq >/dev/null 2>&1 || { echo "❌ jq is required (install: brew install jq)." >&2; exit 1; }

# ── Paths ────────────────────────────────────────────────────────────────────
STATE_DIR=".ralph"
mkdir -p "$STATE_DIR"
STATE_FILE="$STATE_DIR/loop.md"
PROGRESS_FILE="$STATE_DIR/progress.md"
ITEMS_FILE="$STATE_DIR/items.json"
EVENTS_FILE="$STATE_DIR/events.log"
KILLED_FLAG="$STATE_DIR/.killed"
REJECT_FILE="$STATE_DIR/.rejection"

[[ -f "$PROGRESS_FILE" ]] || cat > "$PROGRESS_FILE" <<'EOF'
# Progress

<!-- Each iteration appends here. Keep entries concise. -->
EOF

# ── Bundle mode detection + schema migration check ───────────────────────────
BUNDLE_MODE=false
if [[ -f "$ITEMS_FILE" ]]; then
  if jq -e 'type=="object" and (.version != null) and (.items|type=="array")' "$ITEMS_FILE" >/dev/null 2>&1; then
    BUNDLE_MODE=true
  elif jq -e 'type=="array"' "$ITEMS_FILE" >/dev/null 2>&1; then
    echo "❌ .ralph/items.json is the legacy [{id,text,done}] format." >&2
    echo "   Regenerate it via the plan writer using the new schema {version,items[]}." >&2
    exit 1
  else
    echo "❌ .ralph/items.json is malformed (expected {version, items:[…]})." >&2
    exit 1
  fi
fi

# ── State (held in vars, whole frontmatter rewritten each transition) ────────
PROMPT_HEAD="$(printf '%s\n' "$PROMPT" | head -3)"
ST_RUNNING=true
ST_ITER=0
ST_MAX=$MAX_ITERATIONS
ST_STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
ST_COMPLETED=null
ST_STOP_REASON=null
ST_ERROR_COUNT=0
ST_BUNDLE_MODE=$BUNDLE_MODE
ST_REJECTION_COUNT=0
ST_OWNER_PID=$$
ST_MODEL="${MODEL:-default}"
ST_EFFORT="${EFFORT:-default}"
ST_LAST_PROMISE=none
ST_LAST_SUBTYPE=none
ST_RETRY_COUNT=0

write_state() {
  cat > "$STATE_FILE" <<EOF
---
running: $ST_RUNNING
iteration: $ST_ITER
max_iterations: $ST_MAX
started_at: $ST_STARTED
completed_at: $ST_COMPLETED
stop_reason: $ST_STOP_REASON
error_count: $ST_ERROR_COUNT
bundle_mode: $ST_BUNDLE_MODE
bundle_rejection_count: $ST_REJECTION_COUNT
owner_pid: $ST_OWNER_PID
model_id: $ST_MODEL
thinking_level: $ST_EFFORT
last_promise: $ST_LAST_PROMISE
last_subtype: $ST_LAST_SUBTYPE
retry_count: $ST_RETRY_COUNT
---

$PROMPT_HEAD
EOF
}

log_event() { printf '%s  %s\n' "$(date -u +%H:%M:%SZ)" "$1" >> "$EVENTS_FILE"; }

# ── Ownership: minimal PID lock ──────────────────────────────────────────────
if [[ -f "$STATE_FILE" ]]; then
  prev_running="$(sed -n 's/^running: //p' "$STATE_FILE" | head -1)"
  prev_pid="$(sed -n 's/^owner_pid: //p' "$STATE_FILE" | head -1)"
  if [[ "$prev_running" == true && -n "$prev_pid" && "$prev_pid" != null ]] && kill -0 "$prev_pid" 2>/dev/null; then
    echo "❌ A ralph loop is already running here (PID $prev_pid). Stop it first or use another workspace." >&2
    exit 1
  fi
fi

finish() {
  local reason="$1" code="${2:-0}"
  ST_RUNNING=false
  ST_STOP_REASON="$reason"
  ST_COMPLETED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  write_state
  exit "$code"
}
trap 'finish interrupted 1' INT TERM

bump_rejection() {
  ST_REJECTION_COUNT=$((ST_REJECTION_COUNT + 1))
  printf '%s\n' "$1" > "$REJECT_FILE"
  write_state
}
clear_rejection() { rm -f "$REJECT_FILE"; }

# ── Bundle snapshot + gates (port of pi-ralph item-gates.ts / file-gates.ts) ─
contract_flag() { jq -r --arg k "$1" '.runtime_contract[$k] // false' "$ITEMS_FILE" 2>/dev/null || echo false; }

source_docs_hash() {
  jq -r '.runtime_contract.source_docs[]? // empty' "$ITEMS_FILE" 2>/dev/null | while read -r d; do
    [[ -f "$d" ]] && shasum "$d" 2>/dev/null
  done | shasum 2>/dev/null | awk '{print $1}'
}

snapshot_bundle() {
  B_ITEMS_SNAP="$(jq -c '[.items[] | {category, description, steps, passes}]' "$ITEMS_FILE")"
  B_HEAD="$(git rev-parse HEAD 2>/dev/null || echo none)"
  B_PROG_SIZE="$(wc -c < "$PROGRESS_FILE")"
  B_PROG_SNAP="$(cat "$PROGRESS_FILE")"
  B_SRC_HASH="$(source_docs_hash)"
}

# Positional immutability + exactly-one-flip (NEXT) / all-pass (COMPLETE).
# Echoes a reason on failure, empty on pass.
immut_and_flip() {
  local kind="$1" after
  after="$(jq -c '[.items[] | {category, description, steps, passes}]' "$ITEMS_FILE")"
  jq -rn --argjson b "$B_ITEMS_SNAP" --argjson a "$after" --arg kind "$kind" '
    if ($b|length) != ($a|length) then "item count changed during the iteration"
    else
      ([ range(0; ($b|length)) as $i
         | select($b[$i].category   != $a[$i].category
               or $b[$i].description != $a[$i].description
               or $b[$i].steps       != $a[$i].steps) | ($i+1) ]) as $changed
      | if ($changed|length) > 0 then "item \($changed[0]) immutable fields changed (category/description/steps)"
        elif $kind == "complete" then
          (if ([ $a[] | select(.passes | not) ] | length) > 0
           then "COMPLETE requires every item to have passes=true" else "" end)
        else
          ([ range(0; ($b|length)) as $i | select(($b[$i].passes | not) and $a[$i].passes) ] | length) as $flips
          | if $flips != 1 then "exactly one item must move passes false→true; observed \($flips)" else "" end
        end
    end'
}

GATE_REASON=""
gate_ok() {
  local kind="$1"
  GATE_REASON="$(immut_and_flip "$kind")"
  [[ -n "$GATE_REASON" ]] && return 1

  local after_head after_prog_size after_prog
  after_head="$(git rev-parse HEAD 2>/dev/null || echo none)"

  if [[ "$(contract_flag require_commit)" == true && "$after_head" == "$B_HEAD" ]]; then
    GATE_REASON="git HEAD did not move (require_commit)"; return 1
  fi
  if [[ "$kind" == next && "$(contract_flag require_progress_append)" == true ]]; then
    after_prog_size="$(wc -c < "$PROGRESS_FILE")"
    after_prog="$(cat "$PROGRESS_FILE")"
    if [[ "$after_prog_size" -le "$B_PROG_SIZE" ]]; then
      GATE_REASON="progress.md did not grow (require_progress_append)"; return 1
    fi
    if [[ "${after_prog:0:${#B_PROG_SNAP}}" != "$B_PROG_SNAP" ]]; then
      GATE_REASON="progress.md prior content was modified, not appended (require_progress_append)"; return 1
    fi
  fi
  if [[ "$(contract_flag require_clean_source_docs)" == true && "$(source_docs_hash)" != "$B_SRC_HASH" ]]; then
    GATE_REASON="source_docs changed during the iteration (require_clean_source_docs)"; return 1
  fi
  return 0
}

# ── Promise extraction: last non-empty line, strip backticks, anchored ───────
extract_promise() {
  local text="$1" last re='^<promise>(NEXT|COMPLETE|STOP)</promise>$'
  last="$(printf '%s\n' "$text" | awk 'NF{l=$0} END{print l}')"
  last="$(printf '%s' "$last" | sed -E 's/^`+//; s/`+$//; s/^[[:space:]]+//; s/[[:space:]]+$//')"
  if [[ "$last" =~ $re ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  elif [[ -n "$COMPLETION_PROMISE" && "$last" == "<promise>$COMPLETION_PROMISE</promise>" ]]; then
    printf 'COMPLETE'
  fi
}

# ── Run one iteration under a process group with an activity watchdog ─────────
# Streams stream-json to $1; kills the whole group after IDLE_TIMEOUT of silence.
# Writes KILLED_FLAG on a watchdog kill so the caller can tell it from a real exit.
run_iteration() {
  local out="$1"; shift
  rm -f "$KILLED_FLAG"
  set -m
  "$CLAUDE_RALPH" "$@" > "$out" 2>&1 &
  local pid=$!
  set +m

  (
    last_size=-1
    stalled=0
    while kill -0 "$pid" 2>/dev/null; do
      sleep 15
      size="$(wc -c < "$out" 2>/dev/null || echo 0)"
      if [[ "$size" -gt "$last_size" ]]; then last_size="$size"; stalled=0
      else stalled=$((stalled + 15)); fi
      if [[ "$stalled" -ge "$IDLE_TIMEOUT" ]]; then
        : > "$KILLED_FLAG"
        kill -TERM -"$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
        sleep 2
        kill -KILL -"$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
        break
      fi
    done
  ) &
  local watcher=$!

  local rc=0
  wait "$pid" 2>/dev/null || rc=$?
  kill "$watcher" 2>/dev/null || true
  wait "$watcher" 2>/dev/null || true
  return "$rc"
}

# ── Parse final stream-json result event ─────────────────────────────────────
# total_cost_usd is intentionally ignored: it's notional on a subscription (see
# build spec §6 — budget dropped). num_turns is a real work signal, so we keep it.
R_TEXT=""; R_IS_ERROR=false; R_SUBTYPE=""; R_TURNS=0
parse_result() {
  local out="$1" rj
  rj="$(jq -c 'select(.type=="result")' "$out" 2>/dev/null | tail -1 || true)"
  if [[ -n "$rj" ]]; then
    R_TEXT="$(jq -r '.result // empty' <<<"$rj" 2>/dev/null || true)"
    R_IS_ERROR="$(jq -r '.is_error // false' <<<"$rj" 2>/dev/null || echo false)"
    R_SUBTYPE="$(jq -r '.subtype // empty' <<<"$rj" 2>/dev/null || true)"
    R_TURNS="$(jq -r '.num_turns // 0' <<<"$rj" 2>/dev/null || echo 0)"
  else
    R_TEXT=""; R_IS_ERROR=true; R_SUBTYPE="no_result_event"; R_TURNS=0
  fi
}

# ── Build the per-iteration prompt ───────────────────────────────────────────
build_prompt() {
  ITER_PROMPT="Ralph loop iteration $ST_ITER/$MAX_ITERATIONS."
  [[ -f "$STATE_DIR/plan.md" ]] && ITER_PROMPT+=$'\n\n## Plan\n'"$(cat "$STATE_DIR/plan.md")"
  ITER_PROMPT+=$'\n\n## Progress so far\n'"$(cat "$PROGRESS_FILE")"
  if [[ "$BUNDLE_MODE" == true ]]; then
    ITER_PROMPT+=$'\n\n## Items\n'"$(jq -r '.items | to_entries[] | "\(.key+1). [\(if .value.passes then "x" else " " end)] (\(.value.category)) \(.value.description)"' "$ITEMS_FILE")"
  fi
  ITER_PROMPT+=$'\n\n## Task\n'"$PROMPT"
  if [[ -f "$REJECT_FILE" ]]; then
    ITER_PROMPT+=$'\n\n## ⚠️ The previous promise was REJECTED by the gate\n'"$(cat "$REJECT_FILE")"$'\nFix this before emitting another promise.'
  fi
  if [[ "$BUNDLE_MODE" == true ]]; then
    ITER_PROMPT+=$'\n\n## Instructions
You are in a fresh session — no memory of prior iterations.
1. Read .ralph/progress.md and run `git log --oneline -10` to orient.
2. Pick the HIGHEST-PRIORITY item whose passes is false.
3. Before changing anything, search the codebase — do not assume it is not implemented.
4. Implement exactly ONE item fully — no placeholders, no shortcuts, no stubs.
5. Run its verification steps; if they fail, fix before continuing.
6. Append a concise entry to .ralph/progress.md (append only — do not edit prior entries).
7. In .ralph/items.json, flip ONLY that item'\''s "passes" to true (use jq). Never change any item'\''s category, description, or steps.
8. git add the changed files and commit with a descriptive message.

Emit EXACTLY ONE control tag as the LAST line of your reply (nothing after it):
  <promise>NEXT</promise>     — you completed one item this iteration
  <promise>COMPLETE</promise> — every item now passes
  <promise>STOP</promise>     — you are blocked and cannot proceed'
  else
    ITER_PROMPT+=$'\n\n## Instructions
You are in a fresh session — no memory of prior iterations.
1. Read .ralph/progress.md and run `git log --oneline -10` to orient.
2. Do the next unit of work toward the task — implement fully, no placeholders.
3. Run verification if applicable; fix failures before continuing.
4. Append a concise entry to .ralph/progress.md.
5. git add the changed files and commit with a descriptive message.'
    [[ -n "$COMPLETION_PROMISE" ]] && ITER_PROMPT+=$'\n\nWhen the task is fully done, emit as the LAST line: <promise>'"$COMPLETION_PROMISE"$'</promise> (do not emit until truly done).'
  fi
}

# ── Banner + initial state ───────────────────────────────────────────────────
write_state
echo "🔄 Ralph loop ($([ "$BUNDLE_MODE" == true ] && echo "bundle mode" || echo "direct mode"))"
echo "   iterations: max $MAX_ITERATIONS | idle-timeout: ${IDLE_TIMEOUT}s | retries: $MAX_RETRIES"
[[ -n "$COMPLETION_PROMISE" ]] && echo "   promise: <promise>$COMPLETION_PROMISE</promise>"
[[ -f "$STATE_DIR/plan.md" ]] && echo "   plan: .ralph/plan.md"
echo ""
log_event "loop start — max $MAX_ITERATIONS, bundle_mode=$BUNDLE_MODE"

# ── Main loop ────────────────────────────────────────────────────────────────
for ((i=1; i<=MAX_ITERATIONS; i++)); do
  if [[ -f "$STATE_DIR/.stop" ]]; then
    echo "🛑 Stop requested (.ralph/.stop)"; rm -f "$STATE_DIR/.stop"; log_event "manual stop"; finish manual_stop 0
  fi

  ST_ITER=$i; ST_RETRY_COUNT=0; write_state
  echo "━━━ iteration $i/$MAX_ITERATIONS ━━━"

  retry=0
  while :; do
    build_prompt
    if [[ "$DRY_RUN" == true ]]; then echo "$ITER_PROMPT"; finish dry_run 0; fi

    [[ "$BUNDLE_MODE" == true ]] && snapshot_bundle

    OUT="$STATE_DIR/.iter.out"
    RALPH_ARGS=(-p "$ITER_PROMPT" --output-format stream-json --verbose)
    [[ -n "$MODEL" ]] && export CLAUDE_RALPH_MODEL="$MODEL"
    [[ -n "$EFFORT" ]] && export CLAUDE_RALPH_EFFORT="$EFFORT"

    rc=0; run_iteration "$OUT" "${RALPH_ARGS[@]}" || rc=$?
    parse_result "$OUT"

    killed=false; [[ -f "$KILLED_FLAG" ]] && killed=true
    if [[ "$killed" == true || "$rc" -ne 0 || "$R_IS_ERROR" == true ]]; then
      retry=$((retry + 1)); ST_RETRY_COUNT=$retry; ST_ERROR_COUNT=$((ST_ERROR_COUNT + 1))
      ST_LAST_SUBTYPE="${R_SUBTYPE:-error}"; write_state
      if [[ "$killed" == true ]]; then why="watchdog idle-kill (${IDLE_TIMEOUT}s silent)"; else why="exit $rc / ${R_SUBTYPE:-error}"; fi
      echo "⚠️  iteration $i failed: $why — retry $retry/$MAX_RETRIES"
      log_event "iter $i FAILED ($why) — retry $retry/$MAX_RETRIES"
      if [[ "$retry" -ge "$MAX_RETRIES" ]]; then
        echo "🛑 iteration $i failed $MAX_RETRIES times — stopping"; log_event "iter $i exhausted retries"; finish error 1
      fi
      backoff=$(( 10 * (2 ** (retry - 1)) )); [[ "$backoff" -gt 180 ]] && backoff=180
      sleep "$backoff"
      continue
    fi
    break
  done

  if [[ "$VERBOSE" == true ]]; then echo "$R_TEXT"; else printf '%s\n' "$R_TEXT" | tail -15; fi
  echo ""

  PROMISE="$(extract_promise "$R_TEXT")"
  ST_LAST_PROMISE="${PROMISE:-none}"; ST_LAST_SUBTYPE="${R_SUBTYPE:-success}"; write_state

  case "$PROMISE" in
    COMPLETE)
      if [[ "$BUNDLE_MODE" == true ]] && ! gate_ok complete; then
        bump_rejection "COMPLETE rejected: $GATE_REASON"
        echo "↩︎ COMPLETE rejected: $GATE_REASON (rejection $ST_REJECTION_COUNT/$MAX_RETRIES)"
        log_event "iter $i COMPLETE rejected: $GATE_REASON"
        [[ "$ST_REJECTION_COUNT" -ge "$MAX_RETRIES" ]] && { echo "🛑 too many rejections"; finish error 1; }
      else
        echo "✅ Complete at iteration $i"; log_event "iter $i COMPLETE — done"; finish complete 0
      fi ;;
    STOP)
      echo "🛑 Agent stuck at iteration $i (<promise>STOP</promise>)"; log_event "iter $i STOP — stuck"; finish stuck 1 ;;
    NEXT|"")
      if [[ "$BUNDLE_MODE" == true ]]; then
        if ! gate_ok next; then
          bump_rejection "NEXT rejected: $GATE_REASON"
          echo "↩︎ NEXT rejected: $GATE_REASON (rejection $ST_REJECTION_COUNT/$MAX_RETRIES)"
          log_event "iter $i NEXT rejected: $GATE_REASON"
          [[ "$ST_REJECTION_COUNT" -ge "$MAX_RETRIES" ]] && { echo "🛑 too many rejections"; finish error 1; }
        else
          clear_rejection
          changed="$(git diff --stat 'HEAD@{1}..HEAD' 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//' || true)"
          echo "→ NEXT (iteration $i) — $R_TURNS turns"
          log_event "iter $i NEXT — $R_TURNS turns — ${changed:-no diff}"
        fi
      else
        echo "→ iteration $i done — $R_TURNS turns"
        log_event "iter $i done — $R_TURNS turns"
      fi ;;
  esac
done

echo "🛑 Max iterations ($MAX_ITERATIONS) reached"
log_event "max iterations reached"
finish max_iterations 0
