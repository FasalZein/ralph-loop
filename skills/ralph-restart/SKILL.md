---
name: ralph-restart
description: "Restart a Ralph loop from scratch, discarding prior progress. Use when the user wants to wipe progress and re-run the ralph-loop fresh, or start over."
---

# Ralph Restart

Like `/ralph-resume`, but **discards** prior loop progress first: `progress.md`
is reset to an empty header and any `items.json` `done` flags are cleared. Use
when the previous run went wrong and you want a clean slate against the same
plan. The plan (`plan.md`, `prompt.md`) is left untouched.

This wipes work tracked in `progress.md`. It does NOT revert git commits — if the
prior run committed code, restart that and you may re-do or conflict with it.
Tell the user to reset git separately if they want the code reverted too.

```!
if [[ ! -f .ralph/prompt.md ]]; then
  echo "❌ No .ralph/prompt.md. Use /ralph-plan to create a bundle first." >&2
elif [[ -f .ralph/loop.md ]] && grep -q '^running: true' .ralph/loop.md && [[ ! -f .ralph/.stop ]]; then
  echo "⚠️  loop.md says running: true — stop the active loop (/ralph-stop) before restarting."
else
  rm -f .ralph/.stop
  printf '# Progress\n\n<!-- Each iteration appends here. Keep entries concise. -->\n' > .ralph/progress.md
  if [[ -f .ralph/items.json ]]; then
    jq 'map(.done = false)' .ralph/items.json > .ralph/items.json.tmp && mv .ralph/items.json.tmp .ralph/items.json
  fi
  N="$(sed -n 's/^max_iterations: //p' .ralph/loop.md 2>/dev/null | head -1)"
  echo "🔄 Restarting loop fresh (progress.md cleared)…"
  "${CLAUDE_PLUGIN_ROOT}/scripts/ralph.sh" @.ralph/prompt.md -c COMPLETE -n "${N:-20}" $ARGUMENTS
fi
```
