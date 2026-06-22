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
