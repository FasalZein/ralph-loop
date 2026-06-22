# Writing Perfect AI Agent Loops

Synthesized from Geoffrey Huntley (creator), Matt Pocock (practitioner), and Anthropic's long-running agent research.

## TL;DR

Fresh context per iteration is the single most important thing. Everything else — plans, progress files, feedback loops, small steps — exists to make that fresh context useful. The agent is sharp at the start of every context window and dumb by the end. Never let it reach the end.

---

## The Core Loop

```bash
while :; do cat PROMPT.md | claude -p ; done
```

That's it. Everything below is about making this one line work well.

---

## 1. Fresh Context Is Everything

**Why loops work**: LLMs have a "smart zone" (first ~40% of context) and a "dumb zone" (last ~60%). Quality degrades as context fills. A loop exits before decay dominates, and the next iteration starts fresh. [1][5]

**Why the Anthropic Stop hook plugin fails**: It keeps everything in ONE session. By iteration 3, context is 50%+ full. The agent is in the dumb zone, making bad decisions with compounding cruft. [5]

**The correct architecture**: Each iteration = fresh process, fresh context window. State persists via files on disk and git history, not via context. The agent reads its own prior work from the filesystem, not from memory. [1][2]

> "Throw away live context, keep durable evidence." — pi-ralph-loop README

---

## 2. One Item Per Loop

The #1 rule from Huntley, repeatedly stressed:

> "One item per loop. I need to repeat myself here — one item per loop." [1]

You only have ~170k tokens to work with. The more you use, the worse the outcomes. One focused task per iteration keeps the agent sharp and the feedback tight.

You may relax this as the project matures, but if things go off the rails, narrow back to one. [1]

---

## 3. Deterministic Stack Allocation

Load the SAME files every loop in the SAME order:

1. **Plan file** (`fix_plan.md`, `prd.json`, `.ralph/plan.md`)
2. **Specs** (`specs/*`)
3. **Progress file** (`progress.txt`, `.ralph/progress.md`)
4. **Task instruction** (what to do this iteration)

> "Deterministically allocate the stack the same way every loop." — Huntley [1]

This means the agent always orients itself the same way. No guessing, no exploration waste.

---

## 4. The Progress File

Each iteration appends to a progress file. This is the bridge between fresh context windows. [2][3]

**What goes in:**
- Task completed this iteration
- Decisions made and why
- Files changed
- Blockers encountered
- Notes for next iteration

**Keep it concise.** Sacrifice grammar for brevity. This file exists to skip exploration, not to be documentation. Delete it when the sprint is done. [3]

---

## 5. Define Scope Explicitly

Without explicit scope, the agent will:
- Declare victory too early [2]
- Skip things it decides "don't count" [3]
- Loop forever finding endless improvements

**Use structured PRD items** (Anthropic's approach):
```json
{
  "category": "functional",
  "description": "New chat button creates a fresh conversation",
  "steps": ["Click New Chat", "Verify conversation created"],
  "passes": false
}
```

The agent flips `passes` to `true` when done. JSON is better than Markdown — the model is less likely to inappropriately edit JSON. [2]

**Scope + stop condition must be explicit**, or the agent won't know when to emit `<promise>COMPLETE</promise>`. [3]

---

## 6. Feedback Loops Are Guardrails

The more automated checks you wire in, the higher quality the output:

| Feedback Loop | What It Catches |
|---|---|
| Type checker (tsc, pyrefly, dialyzer) | Type mismatches, missing props |
| Tests (unit, integration) | Broken logic, regressions |
| Linter (eslint, ruff) | Code style, potential bugs |
| Pre-commit hooks | Blocks bad commits entirely |
| Browser automation (Playwright MCP) | UI bugs, broken interactions |

> "After implementing functionality, run the tests for that unit of code that was improved." — Huntley [1]

**Block commits unless everything passes.** The agent can't declare victory if tests are red. [3]

For dynamically typed languages, a static analyzer is CRITICAL — without one, "you will run into a bonfire of outcomes." [1]

---

## 7. Backpressure = The Wheel Speed

Huntley's metaphor: the loop is a wheel. Feedback loops are backpressure that reject bad code generation.

> "It's the speed of the wheel turning that matters, balanced against the axis of correctness." [1]

- **Rust**: Extreme correctness, slow compilation = slow wheel, fewer iterations
- **Python + type checker**: Fast wheel, decent correctness
- **JS/TS with strict tsconfig**: Good balance

Anything can be wired as backpressure: security scanners, static analyzers, integration tests. The key: the wheel has to turn FAST. [1]

---

## 8. Don't Assume Not Implemented

A common failure: the LLM runs `ripgrep`, doesn't find what it's looking for, and re-implements something that already exists.

> "Before making changes, search codebase (don't assume not implemented) using subagents. Think hard." — Huntley [1]

Always instruct the agent to search before creating. This is the Achilles' heel of the loop. [1]

---

## 9. No Cheating — Full Implementations

Claude has an inherent bias toward minimal/placeholder implementations:

> "DO NOT IMPLEMENT PLACEHOLDER OR SIMPLE IMPLEMENTATIONS. WE WANT FULL IMPLEMENTATIONS. DO IT OR I WILL YELL AT YOU" — Huntley [1]

The model chases its reward function (compiling code). Placeholders compile. You need to explicitly override this bias. [1]

---

## 10. Leave Notes for Future Iterations

When writing tests, capture WHY the test exists:

> "When authoring documentation, capture the why tests and the backing implementation is important." — Huntley [1]

Future iterations won't have the reasoning context. The test file itself becomes the documentation. This helps the agent decide whether to delete, modify, or fix a failing test. [1]

---

## 11. Loop Back Is Everything

Program in ways where the agent can evaluate its own output:

- **Compile and inspect output** (e.g., look at LLVM IR)
- **Add logging** to debug issues
- **Run the app** and check behavior
- **Self-verify** features end-to-end, not just unit tests

> "Always look for opportunities to loop Ralph back on itself." — Huntley [1]

---

## 12. Let the Agent Self-Improve

Allow the agent to update its own instructions:

> "When you learn something new about how to run the compiler, make sure you update AGENT.md." — Huntley [1]

The `AGENT.md` / `CLAUDE.md` is the heart of the loop. If the agent discovers a better way to build/test/run, let it write that down for future iterations. [1]

---

## 13. Git Commit Every Iteration

Each iteration should commit its work. This gives future iterations:
- Clean `git log` showing what changed
- Ability to `git diff` against previous work  
- Rollback point if something breaks

> "When the tests pass, git add -A, git commit with a message that describes the changes." — Huntley [1]

Progress file + git history = full context without burning tokens on exploration. [3]

---

## 14. HITL First, AFK Second

| Mode | Best For |
|---|---|
| **HITL** (human-in-the-loop) | Learning, prompt refinement, risky architecture |
| **AFK** (away from keyboard) | Bulk work, low-risk tasks, overnight runs |

1. Start with HITL to learn and refine your prompt
2. Go AFK once you trust the prompt
3. Review commits when you return

> "HITL Ralph resembles pair programming." — Pocock [3]

Use HITL for architectural decisions (the code stays forever). Save AFK for when the foundation is solid. [3]

---

## 15. Prioritize Risky Tasks

Without guidance, the agent picks easy wins. Override this:

1. **Architectural decisions** — cascade through entire codebase
2. **Integration points** — reveals incompatibilities early
3. **Unknown unknowns** — better to fail fast
4. **Standard features** — straightforward implementation
5. **Polish and cleanup** — can be parallelized later

> "Focus on spikes — things you don't know how they'll turn out." — Pocock [3]

---

## 16. The TODO List Is Disposable

The plan/TODO file is a living document. Delete it when it gets stale and regenerate:

> "I have deleted the TODO list multiple times." — Huntley [1]

Run a planning loop to generate a fresh TODO, then switch back to building mode. The plan is not sacred — it's a working document that the agent maintains. [1]

---

## 17. You Will Wake Up to Broken Code

It happens. Engineering judgment call:
- **Easy fix?** Let the next iteration handle it
- **Deep break?** `git reset --hard` to last good commit, re-run
- **Stuck?** Take the error output to a different model, ask it to make a plan

> "Any problem created by AI can be resolved through a different series of prompts." — Huntley [1]

---

## Anthropic's Two-Agent Pattern

For large projects, Anthropic recommends splitting the loop into two prompts [2]:

### 1. Initializer Agent (first iteration only)
- Writes comprehensive feature list (200+ items, JSON, `passes: false`)
- Creates `init.sh` to run dev server
- Sets up progress tracking file
- Makes initial git commit

### 2. Coding Agent (every subsequent iteration)
- Reads progress file + git log
- Runs `init.sh` to start dev server
- Tests basic functionality first (catch regressions)
- Picks ONE feature to implement
- Tests end-to-end (browser automation)
- Commits + updates progress

> "The key insight was finding a way for agents to quickly understand the state of work when starting with a fresh context window." — Anthropic [2]

---

## Common Failure Modes

| Failure | Cause | Fix |
|---|---|---|
| Declares victory early | No explicit scope/PRD | Structured PRD with `passes` field |
| Leaves broken state | No commit discipline | Commit after every green test run |
| One-shots everything | No "one item per loop" instruction | Explicitly say ONE feature only |
| Re-implements existing code | Bad ripgrep search | "Don't assume not implemented, search first" |
| Placeholder implementations | Reward function bias | "NO PLACEHOLDERS. Full implementations." |
| Context rot (quality degrades) | Same session, growing context | Fresh process per iteration |
| Infinite loop, no progress | No step budget | `--max-iterations` always |
| Marks features done without testing | No testing instruction | "Self-verify end-to-end before marking passes:true" |

---

## Sources

- [1] [Geoffrey Huntley — Ralph Wiggum as a "software engineer"](https://ghuntley.com/ralph/) — Creator of the technique
- [2] [Anthropic — Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) — Official research
- [3] [Matt Pocock — 11 Tips For AI Coding With Ralph Wiggum](https://github.com/edxeth/pi-ralph-loop/skills/ralph-plan-writer/philosophy/004) — Practitioner guide
- [4] [neurals.ca — Tool use loops](https://neurals.ca/agents/concepts/loops/) — Loop architecture theory
- [5] [Matt Pocock — Why the Anthropic Ralph plugin sucks](https://github.com/edxeth/pi-ralph-loop/skills/ralph-plan-writer/philosophy/005) — Why fresh context matters
- [6] [Geoffrey Huntley — Everything is a ralph loop](https://ghuntley.com/loop/) — The loop mindset
