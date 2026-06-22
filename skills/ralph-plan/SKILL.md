---
name: ralph-plan
description: "Create a .ralph/ bundle (plan + prompt + progress) for a Ralph loop. Use before /ralph-loop when the task needs decomposition."
argument-hint: "TASK_DESCRIPTION"
---

# Ralph Plan Writer

Creates a `.ralph/` bundle that decomposes a task into loopable items. This is the planning phase — the loop runs after the user approves.

## Steps

1. Analyze the task description from the user
2. Explore the codebase to understand existing code, patterns, and conventions
3. Break the task into small items — each item = one loop iteration
4. Write the bundle files below
5. Show the plan to the user for approval
6. On approval, tell the user to run: `/ralph-loop @.ralph/prompt.md -c COMPLETE -n N`

## Write these files

### `.ralph/plan.md`

```markdown
# Ralph Plan: [Task Name]

## Items (priority order)
<!-- Risky/architectural items first, polish last -->
1. [ ] Item description (specific, verifiable)
2. [ ] ...

## Verification
- List exact commands: `npm test`, `go build ./...`, etc.
- Each item must pass verification before moving on

## Quality Bar
State what "done" means. No placeholders. Full implementations.
```

### `.ralph/prompt.md`

The prompt fed every iteration. Template:

```markdown
You are in a Ralph loop. Each iteration is a fresh context window.

1. Read .ralph/plan.md to see all items
2. Read .ralph/progress.md to see what's been done
3. Run: git log --oneline -10
4. Choose the HIGHEST PRIORITY incomplete item
5. Implement it fully — no placeholders, no shortcuts, no stubs
6. Before making changes, search the codebase — don't assume not implemented
7. Run verification: [EXACT COMMANDS]
8. If tests fail, fix before moving on
9. Append to .ralph/progress.md: what you did, decisions made, files changed
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

## Rules for good plans

- **One item = one iteration.** If an item needs two iterations, split it.
- **Risky first.** Architecture and integration points before CRUD and polish.
- **Specific items.** "Add user auth" is too vague. "Add JWT validation middleware to /api routes" is specific.
- **Exact verification.** Not "run tests" — the actual command path.
- **10-25 items max.** If more, you're over-specifying. If fewer, items are too big.
- **Search before create.** Always instruct the agent to check existing code.
