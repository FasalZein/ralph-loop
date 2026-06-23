# pi-ralph parity — build spec

Governing principle: **the loop system and philosophy are identical to
pi-ralph-loop; only the harness changes** (Pi runtime → Claude Code bash). Deviate
only where the harness physically forces it.

Decisions from the grill (ADRs 0001–0003 cover the architectural ones).
Revised after a fresh-context design review — review fixes are marked **[R]**.

## 1. Foundation — bash orchestrator (ADR-0001)
`ralph.sh` spawns one fresh `claude -p` (via `claude-ralph`) per iteration.
Rejected: built-in `/loop`, hooks-driven, Agent SDK.

## 2. Iterations — always fresh, no resume (ADR-0002)
Every iteration is a new process. No `--resume`, no session_id, no nudge.
Recovery = retry the same iteration fresh; durable state lives on disk.

## 3. Provider-wait substitute (was "retry policy") [R]
pi-ralph has **no iteration retry**; it has a 180s provider-error wait
(`PROVIDER_ERROR_MAX_WAIT_MS`) on a live session. Bash has no live session, so the
faithful substitute is: on failure (nonzero exit OR watchdog kill), retry the
**same** iteration with exponential backoff (~10s/30s/60s/120s/180s), ceiling
**5** to match pi-ralph's actual ceiling (not the invented 3). After 5 consecutive
failures → stop with `stop_reason: error`. Counter is per-iteration, resets on
success. Backoff absorbs transient API errors (which the harness can't classify).

## 4. Watchdog — activity-based idle timeout [R]
Run iterations with `--output-format stream-json`, streamed to a file:
`claude … > "$OUT" 2>&1 &` (NOT `OUTPUT=$(…)` — that blocks and yields no PID).
A background watcher kills the process only after ~10 min of no file growth
(configurable `--idle-timeout`), not on total elapsed time.
- **Process-group kill** (macOS has no `timeout`/`setsid`): `set -m` so the bg job
  gets its own pgid, then `kill -TERM -"$pgid"` to reap claude's children. Verify
  with `pgrep -g`. A bare `kill` orphans children and leaks cost.
- **Kill-flag sentinel**: watcher writes `.ralph/.killed` before killing so the
  loop distinguishes a watchdog-kill (→ failure) from a natural nonzero exit.
- **Reap the watcher** in a trap on normal completion, or it leaks per iteration.
- This also catches the known stream-json "missing final result event" hang.

## 5. Observability ("Both" — robustness + live view) [R]
- `loop.md` — full state frontmatter, rewritten each transition via `write_state()`.
- `.ralph/events.log` — append-only, one line per transition. **"What changed" =**
  the flipped item's `description` + `git diff --stat HEAD@{1}..HEAD` (one line) +
  cost/`num_turns` from the result event.
- Watch via `/ralph-loop status` + `tail -f .ralph/events.log` / `git log`.
- Can be launched as a background task in the main Claude session for live relay.
- **jq on stream-json is JSONL**: parse the final event with
  `jq -c 'select(.type=="result")'`, then pull
  `.result/.is_error/.subtype/.total_cost_usd/.num_turns`. Never jq the whole
  stream as one document.

## 6. Budget — dropped [R]
pi-ralph has no budget; on a subscription `total_cost_usd` is notional. Remove the
`--budget`/`--max-budget-usd` mechanism. **But** `--budget` still parses as
accept-and-warn (deprecated, ignored) so saved invocations don't hard-error.
Runaway loops are bounded by `--max-iterations` + §3 + gates.

## 7 & 8. Data model + gates — pi-ralph verbatim (ADR-0003) [R]
`items.json` = `{version, items[], runtime_contract?}`, item =
`{category, description, steps[], passes, regression_notes}`.

Gates port `item-gates.ts` + `file-gates.ts` **exactly** — not the old count-only
check:
- Snapshot the **full items array** (positionally) at iteration start.
- **NEXT gate**: item count unchanged AND per-index `category`/`description`/`steps`
  unchanged (immutable) AND **exactly one** index flips `passes` false→true
  (`completed != 1` rejects 0 *and* 2+).
- **COMPLETE gate**: immutable check + every item `passes:true`.
- **File-gates are flag-gated, NOT hardcoded** — read `runtime_contract`:
  `require_commit` → git HEAD moved; `require_progress_append` → progress grew AND
  retains its exact prior prefix; `require_clean_source_docs` → source_docs
  unchanged. Each check SKIPS unless its flag is `true`. Hardcoding made ralph-loop
  stricter than pi-ralph.
- **COMPLETE omits the progress-append check** (matches `file-gates.ts`).
- `verification_gates` are agent instructions, NOT run by the loop.
- Ported state: `running, iteration, max_iterations, started_at, completed_at,
  stop_reason, error_count, bundle_mode, model_id, thinking_level,
  bundle_rejection_count` + harness adds `owner_pid, last_promise, last_subtype,
  retry_count`. Dropped Pi-only fields per ADR-0003.

## 9. Ownership — minimal PID lock
Write `owner_pid: $$` on start. Refuse to start if `running:true` AND that PID is
alive (`kill -0`); reclaim if the PID is dead (stale crash). PID liveness replaces
pi-ralph's heartbeat.

## 10. Promises — 3-promise per-iteration, keep both modes [R]
- **Bundle mode** = `items.json` present AND parseable as `{version:1, items:[…]}`.
  Old `[{id,text,done}]` shape is NOT bundle mode (see migration).
- **Bundle mode** prompt teaches the rhythm: one item → flip `passes` → emit
  `<promise>NEXT</promise>`; `COMPLETE` only when all pass; `STOP` if blocked. The
  prompt MUST require **exactly one control tag on the last non-empty line**.
- **Direct mode** (no bundle): keep custom `-c` completion promise, ungated.
- **Promise parser [R]**: reconstruct the assistant's final `.result` text, take the
  **last non-empty line**, strip wrapping backticks, match `^<promise>(NEXT|
  COMPLETE|STOP)</promise>$` anchored. NOT `grep | tail -1` over all output (that
  false-fires when a tag is merely mentioned in reasoning).

## 11. Bundle rejection re-prompt [R]
pi-ralph re-prompts the same session on a gate rejection (up to 5) then finalizes
`error`. No-resume kills the live re-prompt, but the spirit is replicable: persist
the rejection reason and **inject it into the next fresh iteration's prompt**
("Previous NEXT was rejected: <reason>. Fix it this iteration."). Wire this in so
`bundle_rejection_count` isn't a dead field.

## 12. Old→new items.json migration [R]
The new gate jq (`.items[].passes`) breaks on the old `[{id,text,done}]` shape and
vice-versa. On load, check shape/version: if old shape detected, **hard-fail with a
clear message** ("items.json is the legacy format; regenerate via the plan
writer") rather than letting a mismatched schema make every gate silently pass.

## Implementation surface
- `scripts/ralph.sh` — stream-json + JSONL jq; idle watchdog (pgid kill + sentinel
  + reap); provider-wait backoff; `write_state()` (structured rewrite, NOT brittle
  per-field sed); PID lock; positional snapshot gates (immutability + exactly-1 +
  flag-gated file checks); events.log; rejection re-prompt; schema migration check;
  drop budget mechanism (accept-and-warn flag).
- `skills/ralph-loop/SKILL.md` — rich `items.json` schema; 3-promise prompt rhythm
  with last-line tag rule; updated control ops.
- `README.md` — drop budget flag (note deprecation); document watchdog/idle-timeout,
  provider-wait, schema.
- `claude-ralph` — unchanged (lean wrapper is correct).

## Build approach — manual first, dogfood is LATER validation [R]
The initial build is done **manually in a normal session** (ADR/plan §"no
self-loop": last time iteration 1 deleted `claude-ralph` and the running `ralph.sh`
died, exit 127). The current engine is the *old, loose* version — using it to
autonomously author the intricate new gate/watchdog logic is high-risk for
correctness. **Dogfooding = validation AFTER the new ralph exists**: run the
finished new ralph (in isolation) on a throwaway task to prove parity, never as the
build mechanism.

Safe dogfood isolation (for the later validation run):
1. Freeze a stable engine outside the work area:
   `cp -R …/ralph-loop ~/.ralph-stable && cp ~/.local/bin/claude-ralph ~/.ralph-stable/`
2. Build target = a **scratch project**, NOT the plugin repo (its `.ralph/` would
   collide; the repo's own `.ralph/` is stale legacy state): `mkdir -p /tmp/ralph-build`
3. Run the FROZEN engine with `CLAUDE_RALPH_PATH=~/.ralph-stable/claude-ralph`.
4. Prompt forbids touching `~/.ralph-stable`, `~/.local/bin/claude-ralph`, the
   running `ralph.sh`. Verify `claude-ralph` keeps `enabledPlugins.ralph-loop:false`.
