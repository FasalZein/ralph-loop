# Progress

<!-- Each iteration appends here. Keep entries concise. -->

## Item 1: Merge 6 skills into 1 (done)
- Rewrote skills/ralph-loop/SKILL.md to cover plan mode (bundle creation incl. items.json), direct mode (ralph.sh), and control ops (status/stop/resume/restart) as inline documented bash blocks. 170 lines (<180 target).
- Deleted ralph-plan, ralph-stop, ralph-status, ralph-resume, ralph-restart via git rm. Only skills/ralph-loop/ remains.
- Verified: bash -n on both scripts passes.
