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
