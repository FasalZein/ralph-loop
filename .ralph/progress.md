# Progress

<!-- Each iteration appends here. Keep entries concise. -->

## Iteration 1 — Promise support (NEXT/STOP/COMPLETE)
Added standard promise-tag parsing to scripts/ralph.sh. After each iteration the
loop greps the last `<promise>NEXT|STOP|COMPLETE</promise>` tag:
- COMPLETE → exit 0, stop_reason: complete
- STOP → exit 1, stop_reason: stuck
- NEXT → continue to next iteration
Custom `--completion-promise` string still works (backward compat).
Files: scripts/ralph.sh. Verified: bash -n + --help.

## Iteration 2 — Richer loop.md state
Added completed_at, error_count, loop_token fields to .ralph/loop.md frontmatter.
- loop_token: unique `<epoch>-<pid>` set at start.
- error_count: incremented + persisted when a claude-ralph iteration exits non-zero.
- completed_at: stamped on every terminal path via new finish() helper.
Refactored all 5 terminal sed blocks (stop/complete-promise/COMPLETE/STOP/max)
into a single finish(reason, code) helper. Captured run exit code (RUN_RC).
Files: scripts/ralph.sh. Verified: bash -n + --help.

## Iteration 3 — items.json validation gates
Added optional `.ralph/items.json` support to scripts/ralph.sh. Shape:
`[{"id":N,"text":"...","done":bool}, ...]`. When the file is present, terminal
promises are validated against deltas captured before each run:
- B_* snapshot (done count, total, git HEAD, progress.md line count) taken pre-run.
- `gate_ok complete`: all items done + HEAD changed + progress grew.
- `gate_ok next`: ≥1 item flipped done + HEAD changed + progress grew (used >=1
  not exactly-1 — prep/multi-subtask iterations are legitimate).
- Failed COMPLETE downgrades to "continue" (never exit 0 on false done); failed
  NEXT just warns. Both bump error_count via new bump_errors() helper.
Backward-compatible: no items.json → gates skipped entirely.
Files: scripts/ralph.sh. Verified: bash -n, --help, jq fixture delta test.

## Iteration 4 — Control skills (stop/status/resume/restart)
Added four user-facing SKILL.md control commands under skills/:
- ralph-stop: touches .ralph/.stop sentinel (graceful, loop checks between iters).
- ralph-status: prints loop.md frontmatter + .stop flag + tail of progress.md.
- ralph-resume: relaunches ralph.sh @.ralph/prompt.md, progress.md PRESERVED;
  guards against an already-running loop; reuses prior max_iterations.
- ralph-restart: same launch but first resets progress.md to empty header and
  clears items.json done flags via jq. Notes it does NOT revert git commits.
Decision: resume/restart relaunch ralph.sh (which resets iteration:0); real
progress lives in progress.md + git, so the counter reset is cosmetic. Kept lazy
— no new ralph.sh flags needed. Verified jq/sed snippets on a fixture.
Files: skills/ralph-stop/, ralph-status/, ralph-resume/, ralph-restart/.

## Iteration 5 — ralph-plan generates items.json
Added `.ralph/items.json` to the bundle the ralph-plan skill writes. Shape
matches what ralph.sh validates: `[{"id":N,"text":"...","done":bool}]`, one per
plan.md item, same order, all done:false at start. Updated the prompt.md
template (new step 10: flip done via jq) and added a sync rule. Closes the last
scope item — ralph.sh's gates now have a generator. Files: skills/ralph-plan/SKILL.md.
