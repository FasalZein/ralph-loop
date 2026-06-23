# Bash orchestrator spawning fresh `claude -p` per iteration

The loop is driven by an external bash script (`ralph.sh`) that spawns one fresh
`claude -p` OS process per iteration, rather than Claude Code's built-in `/loop`,
a hooks-driven design, or the TypeScript Agent SDK.

We chose this because a genuinely new OS process is the strongest possible form
of "fresh context per iteration" — the core Ralph philosophy. The rejected
alternatives each break it or add no value: `/loop` shares one context window
across iterations (Huntley: it "isn't it"); hooks can't drive a loop (a Stop
hook cannot force a re-run); the SDK would reimplement the same orchestration in
TypeScript without buying any fresh-context guarantee and would drop the lean
bash nature.

Accepted consequence: because iterations are separate processes, all supervision
(error handling, monitoring, budget) happens *between* processes only — there is
no in-process event system or mid-turn steering as pi-ralph has. This coarser
control is acceptable; fresh context is the bigger prize.
