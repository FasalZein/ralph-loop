---
name: ralph-resume
description: "Resume a stopped or finished Ralph loop where it left off. Use when the user wants to continue, resume, or restart-from-progress a ralph-loop without losing prior work."
---

# Ralph Resume

Relaunches the loop against the existing `.ralph/` bundle. `progress.md` is
**kept**, so the fresh iterations read prior work from disk and continue from
where the last run stopped. `ralph.sh` resets the `iteration` counter to 0 —
that's just the per-run counter; actual progress lives in `progress.md` and git
commits, not the counter.

Requires a `.ralph/prompt.md` (written by `/ralph-plan`). Pass through any loop
flags the user gave (`-n`, `-c`, `--budget`, etc.).

```!
if [[ ! -f .ralph/prompt.md ]]; then
  echo "❌ No .ralph/prompt.md to resume. Use /ralph-plan to create a bundle first." >&2
elif [[ -f .ralph/loop.md ]] && grep -q '^running: true' .ralph/loop.md && [[ ! -f .ralph/.stop ]]; then
  echo "⚠️  loop.md says running: true — a loop may already be active. Stop it (/ralph-stop) before resuming."
else
  rm -f .ralph/.stop
  N="$(sed -n 's/^max_iterations: //p' .ralph/loop.md 2>/dev/null | head -1)"
  echo "▶️  Resuming loop (progress.md preserved)…"
  "${CLAUDE_PLUGIN_ROOT}/scripts/ralph.sh" @.ralph/prompt.md -c COMPLETE -n "${N:-20}" $ARGUMENTS
fi
```
