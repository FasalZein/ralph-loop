# Ralph Loop

A Claude Code plugin that runs autonomous, iterative coding loops, porting the
philosophy of pi-ralph-loop (a Pi-runtime extension) into a bash orchestrator
that spawns fresh Claude processes.

## Language

**Loop**:
One full autonomous run — a sequence of iterations against a single bundle that
ends on a terminal promise or when max iterations is reached.
_Avoid_: run, session (a session is a Claude-side concept, not the whole loop)

**Iteration**:
One unit of work: a single fresh `claude -p` process with a clean context
window. The orchestrator inspects its result, then decides whether to continue.
_Avoid_: loop (a loop is the whole run, not one step), turn, step

**Bundle**:
The `.ralph/` directory the loop reads and writes — `plan.md`, `items.json`,
`prompt.md`, `progress.md`. The on-disk contract that survives between
iterations, since each iteration's context is fresh.
_Avoid_: spec, config

**Promise**:
A structured control signal the agent emits at the end of an iteration —
`<promise>NEXT|COMPLETE|STOP</promise>` — telling the orchestrator what to do
next. The agent's only channel for driving the loop.
_Avoid_: signal, tag, marker

**Item**:
A single unit of work in the bundle — `{category, description, steps[], passes,
regression_notes}`. One item ≈ one iteration. `passes` is its done-state.
_Avoid_: task, todo, the `done` flag (it is `passes`)

**Runtime contract**:
The `runtime_contract` block in `items.json` declaring `source_docs`,
`verification_gates`, and the `require_*` rules the loop and agent honor.
_Avoid_: config, settings

**Gate**:
A validation check the *orchestrator* runs before accepting a promise — exactly
one item flipped to `passes:true`, immutable fields unchanged, git HEAD moved,
progress grew. Distrusts the agent's claim and verifies the world changed.
_Avoid_: check, validation, guard

**Verification gate**:
A named shell command in the runtime contract that the *agent* runs to prove an
item works. Stored as instruction; the orchestrator never executes it (matches
pi-ralph — re-running heavy gates froze the loop). Distinct from a **Gate**.
_Avoid_: test gate, runtime check
