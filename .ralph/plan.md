# Ralph Plan: Codebase Review & Polish

## Items (priority order)

1. [x] Review scripts/ralph.sh — reviewed, no changes needed
2. [x] Review skills/ — all frontmatter valid
3. [x] Review scripts/claude-ralph — fixed stale "no skills" comment
4. [x] Final polish — bash syntax verified across all scripts

## Verification
- `bash -n scripts/ralph.sh` — no syntax errors
- `bash -n scripts/claude-ralph` — no syntax errors
- All skills have valid SKILL.md frontmatter

## Quality Bar
Production-ready. No dead code, no broken paths, no stale references.
