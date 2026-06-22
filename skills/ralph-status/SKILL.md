---
name: ralph-status
description: "Show the status of a Ralph loop. Use when the user asks how the ralph-loop is going, what iteration it's on, or whether it finished."
---

# Ralph Status

Reads runtime state from `.ralph/loop.md` and the tail of `.ralph/progress.md`.

```!
if [[ ! -f .ralph/loop.md ]]; then
  echo "No .ralph/loop.md here — no loop has run in this directory."
else
  echo "── loop.md state ──"
  sed -n '/^---$/,/^---$/p' .ralph/loop.md | sed '/^---$/d'
  [[ -f .ralph/.stop ]] && echo "stop_requested: true"
  echo
  echo "── progress.md (last 25 lines) ──"
  tail -n 25 .ralph/progress.md 2>/dev/null || echo "(no progress.md)"
fi
```

After running, summarize for the user: whether it's `running`, the current
`iteration` vs `max_iterations`, `error_count`, and `stop_reason` if finished.
