# Bundle schema and gate logic ported verbatim from pi-ralph-loop

The governing principle for this plugin is: the loop system and philosophy are
identical to pi-ralph-loop; only the harness changes (Pi runtime → Claude Code
bash). Accordingly, the `items.json` bundle schema and the promise-gate logic are
ported from pi-ralph verbatim rather than kept in ralph-loop's earlier simplified
form.

`items.json` is `{version, items[], runtime_contract?}`, where each item is
`{category, description, steps[], passes, regression_notes}` — replacing the old
`[{id, text, done}]`. Gate logic matches `item-gates.ts` exactly: NEXT requires
the item count and immutable fields (`category`, `description`, `steps`)
unchanged plus exactly one item flipping `passes` false→true; COMPLETE requires
the immutable check plus every item `passes:true`.

`runtime_contract.verification_gates` are stored as instructions for the agent
and are deliberately NOT executed by the loop — pi-ralph found that re-running
heavy gates at promise time froze the loop and duplicated work the agent already
did. The orchestrator's runtime gates are item-flip, immutability, git HEAD, and
progress growth only.

Harness-forced state drops: `session_id`, `last_session_file`, `transitioning`,
`loop_token`, `limit_reminders`, and `owner_heartbeat_at` from pi-ralph's
`RalphLoopState` exist only to serve Pi's in-process multi-session runtime and
have no bash equivalent, so they are not carried over. Stop reasons port verbatim
(`complete, max_iterations, user_cancelled, error, manual_stop`).
