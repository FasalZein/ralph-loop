You are in a Ralph loop reviewing and polishing the ralph-loop Claude Code plugin.

## Orientation (every iteration)

1. Read .ralph/plan.md and .ralph/progress.md
2. Run: git log --oneline -10
3. Read the files you'll be reviewing

## What to do

1. Pick the highest-priority incomplete item from plan.md
2. Use /improve-codebase-architecture to analyze architecture if reviewing structure
3. Use /ponytail:ponytail-review to check for over-engineering or unnecessary complexity
4. Fix any issues found — dead code, edge cases, broken paths, inconsistencies
5. Run verification: `bash -n scripts/ralph.sh && bash -n scripts/claude-ralph`
6. Append findings and fixes to .ralph/progress.md
7. git add and commit changes

ONE item per iteration.

When ALL items complete: <promise>COMPLETE</promise>
When this item done: <promise>NEXT</promise>
If stuck: <promise>STOP</promise>
