---
name: ralph-loop
description: "Spawn isolated claude sessions to iterate on a task until done. Use when user wants to ralph-loop, run an autonomous loop, iterate until tests pass, build something AFK, or plan/stop/check/resume/restart such a loop."
argument-hint: "PROMPT [-n MAX] [-c PROMISE] [--budget USD] [--model MODEL] [--effort LEVEL] [--verbose] [--herdr]"
---

# Ralph Loop

Spawns fresh `claude-ralph` processes per iteration. Each iteration gets a clean
context window — zero token cost to this session. State persists on disk
(`.ralph/`, git commits, modified files), so each iteration reads prior work
from the filesystem, not from context.

## Mode 1: Plan first, then loop (recommended)

When the user describes a task but hasn't written a `.ralph/` bundle, CREATE THE
PLAN FIRST. Decompose into small, independent items — each item = one iteration.

1. Discuss scope, then explore the codebase for existing patterns/conventions.
2. Write the bundle files below.
3. **Show the plan and get approval** before running the loop.
4. Execute: `"${CLAUDE_PLUGIN_ROOT}/scripts/ralph.sh" @.ralph/prompt.md -c COMPLETE -n 20`

### `.ralph/plan.md`

```markdown
# Ralph Plan: [Task Name]

## Items (priority order)
<!-- Risky/architectural items first, polish last -->
1. [ ] Item description (specific, verifiable)
2. [ ] ...

## Verification
- Exact commands: `npm test`, `go build ./...`, etc.

## Quality Bar
What "done" means. No placeholders. Full implementations.
```

### `.ralph/items.json`

Machine-readable mirror of the plan. The loop validates promises against it: a
NEXT promise must flip ≥1 item to `done`, COMPLETE requires all done. One object
per plan item, same order, all `done: false` to start.

```json
[
  { "id": 1, "text": "Item description (matches plan.md)", "done": false },
  { "id": 2, "text": "...", "done": false }
]
```

### `.ralph/prompt.md`

The prompt fed EVERY iteration:

```markdown
@.ralph/plan.md @.ralph/progress.md

You are in a Ralph loop. Each iteration is a fresh context window.

1. Read .ralph/plan.md and .ralph/progress.md to see what's done
2. Run: git log --oneline -10
3. Choose the HIGHEST PRIORITY incomplete item
4. Implement it fully — no placeholders, no shortcuts, no stubs
5. Before changing anything, search the codebase — don't assume not implemented
6. Run verification: [EXACT COMMANDS]
7. If tests fail, fix before moving on
8. Append to .ralph/progress.md: what you did, decisions, files changed
9. Flip your item's "done" to true in .ralph/items.json (jq)
10. git add changed files, git commit with descriptive message

ONE item per iteration. Do NOT skip ahead.

When ALL items are complete and verified:
  <promise>COMPLETE</promise>
```

### `.ralph/progress.md`

```markdown
# Progress

<!-- Each iteration appends here. Keep entries concise. -->
```

### Rules for good plans

- **One item = one iteration.** If it needs two, split it.
- **Risky first.** Architecture and integration before CRUD and polish.
- **Specific items.** "Add JWT validation to /api routes", not "add auth".
- **Exact verification.** The actual command, not "run tests".
- **10–25 items.** More = over-specifying; fewer = items too big.
- **Keep items.json in sync with plan.md.** Same items, same order.

## Mode 2: Direct loop (quick tasks)

For focused tasks that don't need a plan (fix one bug, run one refactor):

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/ralph.sh" $ARGUMENTS
```

## After completion

Report: how many iterations ran, whether the promise was fulfilled or max hit.
Details live in `.ralph/loop.md` and `.ralph/progress.md`.

## Control operations

Run these inline when the user asks to check, stop, resume, or restart a loop.

**Status** — read runtime state, then summarize `running`, `iteration` vs
`max_iterations`, `error_count`, and `stop_reason`:

```bash
if [[ ! -f .ralph/loop.md ]]; then
  echo "No .ralph/loop.md — no loop has run here."
else
  sed -n '/^---$/,/^---$/p' .ralph/loop.md | sed '/^---$/d'
  [[ -f .ralph/.stop ]] && echo "stop_requested: true"
  echo "── progress (last 25) ──"; tail -n 25 .ralph/progress.md 2>/dev/null
fi
```

**Stop** — graceful: drops a sentinel `ralph.sh` checks between iterations. The
current iteration finishes first. For a hard kill, `Ctrl-C` the loop's terminal.

```bash
[[ -d .ralph ]] && touch .ralph/.stop && echo "🛑 Halts after current iteration." || echo "No .ralph/ here."
```

**Resume** — relaunch against the existing bundle; `progress.md` is **kept**, so
iterations continue from prior work. Pass through any flags the user gave:

```bash
if [[ ! -f .ralph/prompt.md ]]; then
  echo "❌ No .ralph/prompt.md — use Mode 1 to create a bundle first."
elif [[ -f .ralph/loop.md ]] && grep -q '^running: true' .ralph/loop.md && [[ ! -f .ralph/.stop ]]; then
  echo "⚠️  loop.md says running — stop it before resuming."
else
  rm -f .ralph/.stop
  N="$(sed -n 's/^max_iterations: //p' .ralph/loop.md 2>/dev/null | head -1)"
  "${CLAUDE_PLUGIN_ROOT}/scripts/ralph.sh" @.ralph/prompt.md -c COMPLETE -n "${N:-20}"
fi
```

**Restart** — like resume but **discards** progress first (clears `progress.md`
and `items.json` done flags). Does NOT revert git commits — reset git separately.

```bash
rm -f .ralph/.stop
printf '# Progress\n\n<!-- Each iteration appends here. Keep entries concise. -->\n' > .ralph/progress.md
[[ -f .ralph/items.json ]] && jq 'map(.done = false)' .ralph/items.json > .ralph/items.json.tmp && mv .ralph/items.json.tmp .ralph/items.json
"${CLAUDE_PLUGIN_ROOT}/scripts/ralph.sh" @.ralph/prompt.md -c COMPLETE -n 20
```

## Architecture

```
This session (main claude) ─── creates plan ──► .ralph/ bundle
         └── kicks off ──► ralph.sh (bash loop)
                              ├── iter 1: claude-ralph -p "..." reads .ralph/*
                              ├── iter 2: claude-ralph -p "..." reads .ralph/*
                              └── iter N: ...
```

- `claude-ralph`: lean wrapper — no plugins/MCP, Bash/Read/Edit/Write/Skill, effort:low
- `--herdr` flag spawns iterations in multiplexer panes
