# No session resume — recover by retrying the iteration fresh

`claude -p` supports `--resume <session-id>`, but the loop deliberately never
uses it. Every iteration is a brand-new process with a clean context. When an
iteration crashes, hangs, or errors, recovery is to retry the *same iteration
number* as a fresh process — not to resume the failed session.

This works because all durable state lives on disk: git commits, `progress.md`,
and `items.json`. A fresh retry reads the last committed state and re-derives
from there. Uncommitted work from the failed attempt is discarded on purpose —
a crashed turn's partial output should not be trusted.

Consequence: we drop session_id capture and the "nudge" mechanism (sending
`continue` to a live session) entirely. A missing promise is not nudged; the
next fresh iteration self-corrects by reading `progress.md`. This is simpler
than resume-based recovery and more faithful to fresh-context-per-iteration.
Trade-off accepted: a little rework on retry versus the safety of always
re-deriving from trusted committed state.
