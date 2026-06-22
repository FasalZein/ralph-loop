# Ralph Plan: Codebase Review & Polish

## Items (priority order)

1. [ ] Review scripts/ralph.sh — code quality, edge cases, robustness
2. [ ] Review skills/ — all SKILL.md files for correctness, consistency, and completeness
3. [ ] Review scripts/claude-ralph — wrapper flags, token optimization
4. [ ] Final polish — fix anything found in reviews, verify bash syntax across all scripts

## Verification
- `bash -n scripts/ralph.sh` — no syntax errors
- `bash -n scripts/claude-ralph` — no syntax errors
- All skills have valid SKILL.md frontmatter

## Quality Bar
Production-ready. No dead code, no broken paths, no stale references.
