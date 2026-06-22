#!/usr/bin/env bash
set -euo pipefail

# Ralph Loop — spawns isolated claude-ralph processes per iteration.
# Each iteration = fresh context. Zero token bleed to parent.
# ponytail: bash loop, state on disk, promise grep. That's it.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_RALPH="${CLAUDE_RALPH_PATH:-$SCRIPT_DIR/claude-ralph}"

MAX_ITERATIONS=30
COMPLETION_PROMISE=""
BUDGET="2"
MODEL=""
EFFORT=""
VERBOSE=false
HERDR=false
PROMPT_PARTS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    --max-iterations|-n) MAX_ITERATIONS="$2"; shift 2 ;;
    --completion-promise|-c) COMPLETION_PROMISE="$2"; shift 2 ;;
    --budget) BUDGET="$2"; shift 2 ;;
    --model|-m) MODEL="$2"; shift 2 ;;
    --effort) EFFORT="$2"; shift 2 ;;
    --verbose|-v) VERBOSE=true; shift ;;
    --herdr) HERDR=true; shift ;;
    -h|--help)
      cat <<'EOF'
ralph-loop — iterate a task with isolated claude sessions

Usage: /ralph-loop PROMPT [options]
       /ralph-loop @.ralph/prompt.md [options]

Options:
  -n, --max-iterations N       Cap iterations (default: 30)
  -c, --completion-promise T   String that signals done
  --budget N                   USD cap per iteration (default: 2)
  -m, --model MODEL            Override model
  --effort LEVEL               Override effort (low/medium/high)
  --herdr                      Spawn in herdr pane (multiplexed)
  -v, --verbose                Full output per iteration
  -h, --help                   This message

Examples:
  /ralph-loop "Add auth with tests" -c DONE -n 20
  /ralph-loop @.ralph/prompt.md -c COMPLETE -n 20
  /ralph-loop "Fix flaky test in api.test.ts" -c FIXED --effort medium
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

# State
STATE_DIR=".ralph"
mkdir -p "$STATE_DIR"
STATE_FILE="$STATE_DIR/loop.md"
PROGRESS_FILE="$STATE_DIR/progress.md"

# Initialize progress file if missing
[[ -f "$PROGRESS_FILE" ]] || cat > "$PROGRESS_FILE" <<'EOF'
# Progress

<!-- Each iteration appends here. Keep entries concise. -->
EOF

LOOP_TOKEN="$(date +%s)-$$"

cat > "$STATE_FILE" <<EOF
---
running: true
iteration: 0
max_iterations: $MAX_ITERATIONS
started_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
completed_at: null
stop_reason: null
error_count: 0
loop_token: $LOOP_TOKEN
---

$(echo "$PROMPT" | head -3)
EOF

# finish RUNNING REASON — set running:false, stop_reason, completed_at, then exit.
finish() {
  local reason="$1" code="$2"
  sed -i.bak "s/^running: .*/running: false/" "$STATE_FILE"
  sed -i.bak "s/^stop_reason: .*/stop_reason: $reason/" "$STATE_FILE"
  sed -i.bak "s|^completed_at: .*|completed_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)|" "$STATE_FILE"
  rm -f "$STATE_FILE.bak"
  exit "$code"
}

ERROR_COUNT=0

# Optional items.json — shape: [{"id":N,"text":"...","done":bool}, ...]
# When present, terminal promises are validated against item/progress/git deltas.
ITEMS_FILE="$STATE_DIR/items.json"

bump_errors() {
  ERROR_COUNT=$((ERROR_COUNT + 1))
  sed -i.bak "s/^error_count: .*/error_count: $ERROR_COUNT/" "$STATE_FILE" && rm -f "$STATE_FILE.bak"
}

# gate_ok KIND — KIND=next|complete. Compares post-run state to B_* snapshot.
# Echoes reasons + returns 1 on failure. Requires ITEMS_FILE to exist.
gate_ok() {
  local kind="$1" reason="" a_done a_head a_prog
  a_done=$(jq '[.[]|select(.done)]|length' "$ITEMS_FILE")
  a_head=$(git rev-parse HEAD 2>/dev/null || echo none)
  a_prog=$(wc -l < "$PROGRESS_FILE")
  [[ "$a_head" == "$B_HEAD" ]] && reason+="HEAD unchanged; "
  [[ "$a_prog" -le "$B_PROG" ]] && reason+="progress.md did not grow; "
  if [[ "$kind" == complete ]]; then
    [[ "$a_done" -lt "$B_TOTAL" ]] && reason+="only $a_done/$B_TOTAL items done; "
  else
    [[ "$a_done" -le "$B_DONE" ]] && reason+="no item flipped done; "
  fi
  [[ -n "$reason" ]] && { echo "⚠️  gate failed: $reason"; return 1; }
  return 0
}

echo "🔄 Ralph loop"
echo "   iterations: max $MAX_ITERATIONS | budget: \$$BUDGET/iter"
[[ -n "$COMPLETION_PROMISE" ]] && echo "   promise: <promise>$COMPLETION_PROMISE</promise>"
[[ -f "$STATE_DIR/plan.md" ]] && echo "   plan: .ralph/plan.md"
echo ""

for ((i=1; i<=MAX_ITERATIONS; i++)); do
  # Check for external stop request
  if [[ -f "$STATE_DIR/.stop" ]]; then
    echo "🛑 Stop requested (found .ralph/.stop)"
    rm -f "$STATE_DIR/.stop"
    finish manual_stop 0
  fi

  # Update state
  sed -i.bak "s/^iteration: .*/iteration: $i/" "$STATE_FILE" && rm -f "$STATE_FILE.bak"

  echo "━━━ iteration $i/$MAX_ITERATIONS ━━━"

  # Build iteration prompt — deterministic stack allocation:
  # 1. Plan (if exists)  2. Progress  3. Task  4. Instructions
  ITER_PROMPT="Ralph loop iteration $i/$MAX_ITERATIONS."

  if [[ -f "$STATE_DIR/plan.md" ]]; then
    ITER_PROMPT+="

## Plan
$(cat "$STATE_DIR/plan.md")"
  fi

  ITER_PROMPT+="

## Progress so far
$(cat "$PROGRESS_FILE")

## Task
$PROMPT

## Instructions
You are in a fresh session — no memory of prior iterations.
1. Read .ralph/progress.md and git log --oneline -10 to orient
2. Pick the highest-priority incomplete item
3. Implement it fully — no placeholders, no shortcuts
4. Run verification (tests, typecheck, lint) if applicable
5. If tests fail, fix before moving on
6. Append a concise entry to .ralph/progress.md: what you did, key decisions, files changed
7. git add changed files, git commit with descriptive message
8. Work on ONE item only"

  if [[ -n "$COMPLETION_PROMISE" ]]; then
    ITER_PROMPT+="

When ALL items complete and verified: <promise>$COMPLETION_PROMISE</promise>
Do NOT emit unless truly done."
  fi

  # Snapshot state before the run — gates compare deltas afterward.
  if [[ -f "$ITEMS_FILE" ]]; then
    B_DONE=$(jq '[.[]|select(.done)]|length' "$ITEMS_FILE")
    B_TOTAL=$(jq 'length' "$ITEMS_FILE")
    B_HEAD=$(git rev-parse HEAD 2>/dev/null || echo none)
    B_PROG=$(wc -l < "$PROGRESS_FILE")
  fi

  # Build args
  RALPH_ARGS=(-p "$ITER_PROMPT" --max-budget-usd "$BUDGET")
  [[ -n "$MODEL" ]] && export CLAUDE_RALPH_MODEL="$MODEL"
  [[ -n "$EFFORT" ]] && export CLAUDE_RALPH_EFFORT="$EFFORT"

  # Run — fresh process, fresh context, zero parent bleed
  RUN_RC=0
  if [[ "$HERDR" == "true" ]] && command -v herdr &>/dev/null; then
    # Spawn a visible pane — user watches the agent work live
    AGENT_NAME="ralph-$i"
    PANE_ID=$(herdr agent start "$AGENT_NAME" --split down --no-focus -- "$CLAUDE_RALPH" "${RALPH_ARGS[@]}" 2>/dev/null | grep -o 'pane_[^ ]*' || true)
    if [[ -n "$PANE_ID" ]]; then
      herdr agent wait "$AGENT_NAME" --status idle --timeout 300000 2>/dev/null || true
      OUTPUT=$(herdr agent read "$AGENT_NAME" --source recent-unwrapped --lines 200 2>/dev/null) || true
      herdr pane close "$PANE_ID" 2>/dev/null || true
    else
      # Fallback if herdr agent start didn't return a pane id
      OUTPUT=$("$CLAUDE_RALPH" "${RALPH_ARGS[@]}" 2>&1) || RUN_RC=$?
    fi
  else
    OUTPUT=$("$CLAUDE_RALPH" "${RALPH_ARGS[@]}" 2>&1) || RUN_RC=$?
  fi

  # Track iteration errors (non-zero claude-ralph exit).
  if [[ "$RUN_RC" -ne 0 ]]; then
    bump_errors
    echo "⚠️  iteration $i exited $RUN_RC (error_count: $ERROR_COUNT)"
  fi

  # Display
  if [[ "$VERBOSE" == "true" ]]; then
    echo "$OUTPUT"
  else
    echo "$OUTPUT" | tail -15
  fi
  echo ""

  # Check promise — custom COMPLETION_PROMISE still means "done".
  if [[ -n "$COMPLETION_PROMISE" ]] && echo "$OUTPUT" | grep -qF "<promise>$COMPLETION_PROMISE</promise>"; then
    echo "✅ Complete at iteration $i"
    finish complete 0
  fi

  # Standard promise tags: last one wins. COMPLETE=done, STOP=stuck, NEXT=continue.
  PROMISE=$(echo "$OUTPUT" | grep -oE '<promise>(NEXT|STOP|COMPLETE)</promise>' | tail -1 | grep -oE 'NEXT|STOP|COMPLETE' || true)
  case "$PROMISE" in
    COMPLETE)
      if [[ -f "$ITEMS_FILE" ]] && ! gate_ok complete; then
        bump_errors
        echo "↩︎ COMPLETE rejected at iteration $i — continuing (error_count: $ERROR_COUNT)"
      else
        echo "✅ Complete at iteration $i (<promise>COMPLETE</promise>)"
        finish complete 0
      fi ;;
    STOP)
      echo "🛑 Stuck at iteration $i (<promise>STOP</promise>)"
      finish stuck 1 ;;
    NEXT)
      if [[ -f "$ITEMS_FILE" ]] && ! gate_ok next; then
        bump_errors
        echo "→ NEXT at iteration $i — gate warning (error_count: $ERROR_COUNT)"
      else
        echo "→ NEXT (iteration $i done)"
      fi ;;
  esac
done

echo "🛑 Max iterations ($MAX_ITERATIONS) reached"
finish max_iterations 0
