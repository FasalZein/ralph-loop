---
name: ralph-loop
description: "Spawn isolated claude sessions to iterate on a task until done. Use when user wants to ralph-loop, run an autonomous loop, iterate until tests pass, or build something AFK."
argument-hint: "PROMPT [-n MAX] [-c PROMISE] [--budget USD] [--model MODEL] [--effort LEVEL] [--verbose] [--herdr]"
---

# Ralph Loop

Spawns fresh `claude-ralph` processes per iteration. Each iteration gets a clean context window — zero token cost to this session.

## Two modes of operation

### Mode 1: Plan first, then loop (recommended)

When the user describes a task but hasn't written a `.ralph/` bundle yet, CREATE THE PLAN FIRST:

1. Discuss the task with the user to understand scope
2. Create the `.ralph/` bundle:

```
.ralph/
├── plan.md          # What to build, broken into items
├── prompt.md        # The actual prompt fed each iteration
├── progress.md      # Starts empty, grows each iteration
└── loop.md          # Runtime state (created by ralph.sh)
```

3. **Show the plan to the user and get approval** before running the loop
4. Then execute: `"${CLAUDE_PLUGIN_ROOT}/scripts/ralph.sh" @.ralph/prompt.md -c COMPLETE -n 20`

#### Writing the plan

**plan.md** — break the task into small, independent items. Each item = one iteration:

```markdown
# Ralph Plan: [Task Name]

## Items (priority order)

1. [ ] Set up project structure and dependencies
2. [ ] Implement core data model
3. [ ] Add API endpoints with validation
4. [ ] Write tests for core logic
5. [ ] Add error handling and edge cases
6. [ ] Integration test and polish

## Verification
- `npm test` must pass
- `npm run typecheck` must pass
- `npm run lint` must pass

## Quality Bar
Production code. Full implementations, no placeholders.
```

**prompt.md** — the actual loop prompt. This is what gets fed EVERY iteration:

```markdown
@.ralph/plan.md @.ralph/progress.md

You are in a Ralph loop. Each iteration is a fresh context window.

1. Read .ralph/plan.md and .ralph/progress.md to understand what's done
2. Read git log --oneline -10 to see recent work
3. Choose the HIGHEST PRIORITY incomplete item (not necessarily first)
4. Implement it fully — no placeholders, no shortcuts
5. Run verification: [list the test/build commands]
6. If tests fail, fix before moving on
7. Update .ralph/progress.md with what you did and key decisions
8. git add the changed files, git commit with descriptive message

ONLY work on ONE item per iteration.
Do NOT assume code is not implemented — search first.

When ALL items are complete and verified:
  <promise>COMPLETE</promise>
```

**progress.md** — starts with a header, grows each iteration:

```markdown
# Progress

<!-- Each iteration appends here. Keep entries concise. -->
```

#### Plan approval

After writing the `.ralph/` bundle, show the user:
- The plan items
- The prompt that will be looped  
- The verification commands
- Estimated iterations

Ask: "Ready to start the loop?" Only proceed on approval.

### Mode 2: Direct loop (quick tasks)

For focused tasks that don't need a plan (fix one bug, run one refactor):

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/ralph.sh" $ARGUMENTS
```

## After completion

Report to the user:
- How many iterations ran
- Whether the promise was fulfilled or max iterations hit
- Check `.ralph/loop.md` and `.ralph/progress.md` for details

## Stopping a running loop

Create `.ralph/.stop` file in the project root — the loop checks it between iterations.

## Architecture

```
This session (main claude) ─── creates plan ──► .ralph/ bundle
         │                                         │
         └── kicks off ──► ralph.sh (bash loop)    │
                              │                     │
                              ├── iter 1: claude-ralph -p "..." reads .ralph/*
                              ├── iter 2: claude-ralph -p "..." reads .ralph/*
                              └── iter N: ...
```

- `claude-ralph`: lean wrapper — no plugins, no MCP, Bash/Read/Edit/Write/Skill, effort:low
- State persists via filesystem (`.ralph/`, git commits, modified files)
- Each iteration reads prior work from disk, not from context
- `--herdr` flag spawns iterations in multiplexer panes
