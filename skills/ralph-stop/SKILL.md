---
name: ralph-stop
description: "Stop a running Ralph loop. Use when the user wants to stop, halt, or kill a ralph-loop that's in progress."
---

# Ralph Stop

Drops a `.ralph/.stop` sentinel. `ralph.sh` checks for it between iterations and
exits cleanly (removing the file) before the next `claude-ralph` spawn. The
current iteration finishes its work first — this is a graceful stop, not a kill.

```!
if [[ -d .ralph ]]; then
  touch .ralph/.stop
  echo "🛑 Stop requested — loop will halt after the current iteration finishes."
else
  echo "No .ralph/ bundle here. Nothing to stop."
fi
```

For an immediate hard kill, the user must `Ctrl-C` the terminal running the loop
(or kill the `ralph.sh` process) — there's no clean way to interrupt a
mid-flight `claude-ralph` from here.
