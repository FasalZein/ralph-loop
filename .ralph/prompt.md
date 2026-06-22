You are in a Ralph loop improving the ralph-loop Claude Code plugin. Each iteration is a fresh context window — you have no memory of prior iterations.

## Orientation (do this every iteration)

1. Read `.ralph/plan.md` to understand the full scope
2. Read `.ralph/progress.md` to see what's been done
3. Run: `git log --oneline -10` (if git is initialized)
4. Read the current source files you'll be changing

## Key files

- `scripts/ralph.sh` — main loop script (bash)
- `scripts/claude-ralph` — lean claude wrapper
- `skills/ralph-loop/SKILL.md` — main loop skill
- `skills/ralph-plan/SKILL.md` — plan writer skill
- `skills/ralph-stop/SKILL.md` — stop command (create if missing)
- `skills/ralph-status/SKILL.md` — status command (create if missing)
- `skills/ralph-resume/SKILL.md` — resume command (create if missing)
- `skills/ralph-restart/SKILL.md` — restart command (create if missing)

## What to do

1. Choose the HIGHEST PRIORITY incomplete item from the plan
2. Before making changes, read the existing code — don't assume what's implemented
3. Implement it fully — no placeholders, no stubs
4. Test what you can: `bash -n scripts/ralph.sh` for syntax, `scripts/ralph.sh --help` for arg parsing
5. Append a concise entry to `.ralph/progress.md`: what you did, decisions made, files changed
6. `git add` the changed files, `git commit` with a descriptive message

## Rules

- ONE item per iteration. Do not skip ahead.
- jq is available for JSON parsing. Use it for items.json validation.
- Keep ralph.sh backward-compatible: when items.json is absent, skip validation gates.
- Skills are just SKILL.md files with frontmatter. They execute bash commands via ```! blocks.
- Match existing code style — read before writing.
- No placeholders. Full implementations.

## Promise tags

When this iteration's item is done and verified:
  <promise>NEXT</promise>

When ALL items in the plan are complete and verified:
  <promise>COMPLETE</promise>

If stuck and unable to make progress:
  <promise>STOP</promise>

Emit exactly ONE promise tag on the last line. Do NOT emit unless the work is truly done.
