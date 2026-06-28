---
name: ralph-loop
description: "Spawn isolated claude sessions to iterate on a task until done. Use when user wants to ralph-loop, run an autonomous loop, iterate until tests pass, build something AFK, or plan/stop/check/resume/restart such a loop."
argument-hint: "PROMPT [-n MAX] [-c PROMISE] [--budget USD] [--model MODEL] [--effort LEVEL] [--verbose] [--dry-run]"
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
4. Execute **in the background** (see Running & watching): `"${CLAUDE_PLUGIN_ROOT}/scripts/ralph.sh" @.ralph/prompt.md -c COMPLETE -n 20`

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

Machine-readable contract (pi-ralph schema). The loop gates promises against it:
a NEXT must flip **exactly one** item `passes` false→true, COMPLETE requires
**all** `passes:true`. An item's `category`, `description`, and `steps` are
**immutable** during the loop — the agent may only flip `passes` (changing them
gets the promise rejected). One item per plan item, same order, all
`passes: false` to start.

```json
{
  "version": 1,
  "items": [
    {
      "category": "feature",
      "description": "Item description (matches plan.md)",
      "steps": ["concrete step", "verification step"],
      "passes": false,
      "regression_notes": ""
    }
  ],
  "runtime_contract": {
    "verification_gates": [{ "name": "tests", "command": "npm test" }],
    "require_commit": true,
    "require_progress_append": true,
    "require_one_item_per_iteration": true
  }
}
```

`verification_gates` are commands the **agent** runs to prove an item works — the
loop never executes them. The `require_*` flags turn on the matching runtime
gate (commit made / progress appended). Legacy `[{id,text,done}]` files are
rejected — regenerate with this schema.

### `.ralph/prompt.md`

The prompt fed EVERY iteration:

> Note: in bundle mode `ralph.sh` generates the per-iteration instructions
> itself (including the promise rules), so a hand-written `prompt.md` is optional.
> When you do write one, match the rhythm below.

```markdown
@.ralph/plan.md @.ralph/progress.md

You are in a Ralph loop. Each iteration is a fresh context window.

1. Read .ralph/plan.md and .ralph/progress.md to see what's done
2. Run: git log --oneline -10
3. Choose the HIGHEST PRIORITY item whose passes is false
4. Implement it fully — no placeholders, no shortcuts, no stubs
5. Before changing anything, search the codebase — don't assume not implemented
6. Run verification: [EXACT COMMANDS]
7. If tests fail, fix before moving on
8. Append to .ralph/progress.md: what you did, decisions, files changed
9. Flip ONLY that item's "passes" to true in .ralph/items.json (jq). Never edit
   any item's category, description, or steps.
10. git add changed files, git commit with descriptive message

ONE item per iteration. Do NOT skip ahead.

Emit EXACTLY ONE control tag as the LAST line of your reply:
  <promise>NEXT</promise>     — one item completed this iteration
  <promise>COMPLETE</promise> — every item now passes
  <promise>STOP</promise>     — blocked, cannot proceed
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

For focused tasks that don't need a plan (fix one bug, run one refactor).
Only use this when the user passes explicit flags like `-c DONE -n 10`:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/ralph.sh" $ARGUMENTS
```

## Routing

- If the user describes a task ("build X", "refactor Y", "add feature Z") → **Mode 1** (plan first)
- If the user passes flags (`-c`, `-n`, `@.ralph/prompt.md`) → **Mode 2** (direct loop)
- If unsure → **Mode 1** (plan is always safer)

## Running & watching

Launch the loop in the **background** (set `run_in_background` on the Bash call).
That keeps this session responsive AND makes the harness notify you the moment
`ralph.sh` exits — that notification is your "loop is done" signal. Do NOT run it
foreground and block the session waiting.

While it runs, watch it live with **`ralph.sh watch`** — a readable feed that
merges the loop's decisions (`events.log`) with the current worker's stream,
pretty-printed (tool calls, text, results, iteration boundaries), and survives
each iteration's stream rollover:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/ralph.sh" watch
```

For a one-shot snapshot instead of a live feed, use the **Status** op below.
Check in periodically; don't poll tightly.

When you get the exit notification, read `.ralph/loop.md` (`stop_reason`:
complete / stuck / error / max_iterations) and `tail -n 25 .ralph/progress.md`,
then report: iterations run, whether the promise was fulfilled, and what changed.

## Control operations

Run these inline when the user asks to check, stop, resume, or restart a loop.

**Status** — the blessed liveness check. Reports runtime state AND whether the
worker is actually alive and streaming. Trust this, never `pgrep` (see Process
model below for why `pgrep claude-ralph` is always empty):

```bash
if [[ ! -f .ralph/loop.md ]]; then
  echo "No .ralph/loop.md — no loop has run here."
else
  sed -n '/^---$/,/^---$/p' .ralph/loop.md | sed '/^---$/d'
  pid="$(sed -n 's/^owner_pid: //p' .ralph/loop.md | head -1)"
  if grep -q '^running: true' .ralph/loop.md; then
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      echo "owner_pid $pid: ALIVE"
      if [[ -f .ralph/.iter.out ]]; then
        age=$(( $(date +%s) - $(stat -f %m .ralph/.iter.out 2>/dev/null || stat -c %Y .ralph/.iter.out) ))
        bytes="$(wc -c < .ralph/.iter.out | tr -d ' ')"
        [[ $age -lt 60 ]] && hint="streaming" || hint="quiet — long tool call or stalled"
        echo "worker stream: ${bytes}B, last write ${age}s ago ($hint)"
      fi
    else
      echo "owner_pid $pid: DEAD — loop crashed without finalizing (stale running:true)"
    fi
  fi
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
and resets every item's `passes` to false). Does NOT revert git commits — reset
git separately.

```bash
rm -f .ralph/.stop .ralph/.rejection .ralph/.killed
printf '# Progress\n\n<!-- Each iteration appends here. Keep entries concise. -->\n' > .ralph/progress.md
[[ -f .ralph/items.json ]] && jq '.items |= map(.passes = false)' .ralph/items.json > .ralph/items.json.tmp && mv .ralph/items.json.tmp .ralph/items.json
N="$(sed -n 's/^max_iterations: //p' .ralph/loop.md 2>/dev/null | head -1)"
"${CLAUDE_PLUGIN_ROOT}/scripts/ralph.sh" @.ralph/prompt.md -c COMPLETE -n "${N:-20}"
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
- `--dry-run` prints the assembled iteration-1 prompt and exits (debug prompts before looping)

### Process model (recognising a healthy loop)

Reason about a running loop from these facts, not from `pgrep`:

- **The wrapper *becomes* the worker.** `claude-ralph` ends in `exec claude`, so
  the iteration runs as a plain `claude` process — `pgrep claude-ralph` is
  **always empty**, and that is not a dead worker.
- **Two `ralph.sh` PIDs is one loop.** The driver spawns its idle-watchdog as a
  subshell that shares the script name. Two PIDs = driver + watchdog, not two loops.
- **`.ralph/.iter.out` is the live worker stream.** `tail -f .ralph/.iter.out`
  watches the current iteration in real time; `Status` reports its activity.

The watchdog measures **output silence**, not wall-clock. A single long, quiet
shell command (a big `build && test`) emits no stream output and counts as
silence; if one tool call runs longer than `--idle-timeout` (default 600s) the
watchdog kills a healthy worker. Raise `--idle-timeout` for build-heavy repos.
