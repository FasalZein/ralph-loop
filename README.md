# Ralph Loop

A Claude Code plugin that runs autonomous, iterative coding loops. Each
iteration spawns a **fresh `claude` process** with a clean context window, so a
long-running task costs **zero tokens** in your parent session. State lives on
disk (`.ralph/`, git commits, modified files) — every iteration reads prior work
from the filesystem, not from context.

Named after [Geoffrey Huntley's "Ralph Wiggum" technique](https://ghuntley.com/ralph/):
run the same prompt in a loop until the work is done.

## How it works

```
This session (main claude) ─── creates plan ──► .ralph/ bundle
         └── kicks off ──► scripts/ralph.sh (bash loop)
                              ├── iter 1: claude-ralph -p "..." reads .ralph/*
                              ├── iter 2: claude-ralph -p "..." reads .ralph/*
                              └── iter N: ... until promise or max iterations
```

- **`ralph.sh`** — the bash loop. Runs iterations, validates promises, tracks
  state in `.ralph/loop.md`, stops on a sentinel or when the promise is met.
- **`claude-ralph`** — a lean per-iteration wrapper: no plugins/MCP, tools
  limited to Bash/Read/Edit/Write/Skill, low reasoning effort.

## Install

**Marketplace (from GitHub):**

```
/plugin install https://github.com/FasalZein/ralph-loop
```

**Local dev (symlink):**

```bash
ln -s /path/to/ralph-loop ~/.claude/plugins/ralph-loop
```

## Usage

The plugin exposes one skill, `/ralph-loop`, with two modes.

### Mode 1 — Plan first, then loop (recommended)

Describe a task. Claude decomposes it into small, independent items (one item =
one iteration), writes a `.ralph/` bundle (`plan.md`, `items.json`, `prompt.md`,
`progress.md`), shows you the plan for approval, then runs the loop:

```
/ralph-loop build a REST API for todos with tests
```

The loop validates each iteration's promise against `items.json`: a `NEXT`
promise must flip ≥1 item to done; `COMPLETE` requires all items done.

### Mode 2 — Direct loop (quick tasks)

For a focused task that doesn't need a plan:

```
/ralph-loop fix the failing auth test -c DONE -n 10
```

**Flags:**

| Flag | Meaning |
|------|---------|
| `-n MAX` | max iterations (default 20) |
| `-c PROMISE` | completion promise the loop watches for (e.g. `DONE`, `COMPLETE`) |
| `--budget USD` | stop when spend exceeds this |
| `--model MODEL` | model for iterations |
| `--effort LEVEL` | reasoning effort |
| `--verbose` | stream iteration output |
| `--herdr` | spawn iterations in multiplexer panes |

### Control operations

Ask Claude to **check / stop / resume / restart** a loop and it runs the right
inline command:

- **Status** — summarizes `.ralph/loop.md` (running, iteration vs max, errors,
  stop reason) plus recent progress.
- **Stop** — drops `.ralph/.stop`; the current iteration finishes, then the loop
  halts gracefully. (Hard kill: `Ctrl-C` the loop's terminal.)
- **Resume** — relaunches against the existing bundle, keeping `progress.md`.
- **Restart** — relaunches but clears `progress.md` and resets `items.json` done
  flags. Does **not** revert git commits — reset those separately.

## Writing good loops

See [docs/writing-perfect-loops.md](docs/writing-perfect-loops.md) for the full
guide. The essentials:

- **One item = one iteration.** If it needs two, split it.
- **Risky first.** Architecture and integration before CRUD and polish.
- **Specific items.** "Add JWT validation to /api routes", not "add auth".
- **Exact verification.** The actual command, not "run tests".
- **10–25 items.** More = over-specifying; fewer = items too big.

## License

MIT
