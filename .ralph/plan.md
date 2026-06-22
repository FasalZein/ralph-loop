# Execution Plan: Ralph Loop Parity with pi-ralph-loop

## Objective

Bring the claude ralph-loop plugin to feature parity with pi-ralph-loop's core utility. The pi version validates promises against file/item invariants, tracks errors, supports NEXT/STOP/COMPLETE promises, and has control commands. Our bash-based version currently relies on the agent's honor system.

## Scope In

- NEXT/STOP promise detection in ralph.sh (currently only COMPLETE)
- Richer loop.md state (error_count, completed_at, loop_token)
- items.json support in ralph.sh — parse and validate when present
- Bundle validation gates (item gate, progress gate, commit gate) in bash
- Control skills: ralph-stop, ralph-status, ralph-resume, ralph-restart
- Update ralph-plan skill to generate items.json

## Scope Out

- Ownership/heartbeat (irrelevant — we spawn fresh processes)
- Limit reminders (irrelevant — fresh context per iteration)
- Provider error retry wait (process crash = next iteration)
- Session blocking (separate processes can't interfere)
- Model state restore via API (env vars cover this)
- Platform reference docs (windows.md, linux.md, etc.)
- TypeScript rewrite — stay in bash

## Constraints

- All loop logic stays in `scripts/ralph.sh` — no external dependencies beyond bash + jq
- Skills are markdown SKILL.md files under `skills/`
- `claude-ralph` wrapper stays minimal
- Must be backward-compatible: loops without items.json still work (plan.md + progress.md only)

## Prioritization Strategy

1. Promise support (NEXT/STOP) — foundational, everything else builds on it
2. Richer state — needed for resume/restart
3. Bundle validation — the biggest quality gap
4. Control commands — user-facing utility
5. Plan writer update — generates the new items.json

## Completion Definition

- ralph.sh supports NEXT/STOP/COMPLETE promises
- ralph.sh validates items.json when present (exactly 1 item flipped for NEXT, all pass for COMPLETE)
- ralph.sh validates progress.md grew and git HEAD changed (when items.json requires it)
- loop.md has error_count, completed_at, loop_token fields
- Skills exist for ralph-stop, ralph-status, ralph-resume, ralph-restart
- ralph-plan skill generates items.json alongside plan.md
- All changes tested by dry-running ralph.sh --help and checking exit codes
