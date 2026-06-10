# Token usage review

A first-pass audit of where the harness spends tokens and where it
could spend fewer without losing quality. Findings are sorted by
estimated impact × implementation risk.

## Why this matters

The harness's design *already* leans into the right pattern — the
orchestrator delegates everything, sub-agents do the work in their own
isolated contexts, and the main thread only sees their summaries.
Anecdotally that pattern can keep a main-thread context under 20% drop
through an 8-hour autonomous run. But several specifics inside the
harness make per-iteration cost higher than necessary, and a few
architectural choices leave bigger wins on the table.

## Per-iteration cost — measured surface area

| Surface | Size | Where injected | Frequency |
|---|---|---|---|
| Orchestrator prompt (in `ralph.sh`) | ~4.7 KB / ~1200 tokens | Every iteration's `claude --print` | Per issue |
| Each agent's `.md` body | 4.4–11.9 KB / ~1100–3000 tokens | Loaded when Task tool dispatches that agent | Per dispatch |
| `every-layout` SKILL.md | 5.9 KB / ~1500 tokens | Engineer + designer + AD + PM all load it via `Skill` | Per dispatch that calls the skill |
| `react-best-practices` SKILL.md | 7.3 KB / ~1800 tokens | Engineer loads it before every code-touching dispatch | Per engineer dispatch |
| `composition-patterns` SKILL.md | 2.9 KB / ~720 tokens | Engineer loads it before every code-touching dispatch | Per engineer dispatch |
| `CONTEXT_FILES` content | Project-dependent (vcc-static `docs/rules.md` ≈ 12 KB / ~3000 tokens) | Each sub-agent reads them itself | Per dispatch × per file |

A typical "code + test" slice (orchestrator + PM + engineer + tester)
re-reads `docs/rules.md` three times. A "visual" slice with the design
phase (orchestrator + PM + AD + designer + AD-audit + engineer + tester)
re-reads it seven times.

---

## Findings, sorted by impact × low risk

### HIGH impact

#### 1. Reviewer and DevOps should run on Haiku, not Sonnet

Both are pattern-matching jobs with bounded output shape:

- **Reviewer** reads a diff, emits structured JSON (verdict + scores +
  violations). No creative synthesis, no novel design.
- **DevOps** runs git operations and writes commit / PR messages from
  formulaic templates.

Haiku 4.5 handles structured-output classification well at roughly 1/15
the Sonnet token cost. Move both to `model: haiku-4-5`. Engineer / AD
/ designer / tester stay on Sonnet because they generate novel output;
PM stays on Sonnet because it's a real interview.

**Estimated saving: ~25–30% of per-slice output token spend** (reviewer
+ devops are typically the largest output-token consumers per slice
after engineer).

#### 2. Orchestrator prompt has redundant capability descriptions

Every ENABLED agent gets a paragraph in `ralph.sh`'s orchestrator
prompt describing what it does. That paragraph duplicates what's in
the agent's own `.md` frontmatter (which the Task tool surfaces when
the orchestrator selects an agent).

Replace the inline capability paragraphs with a single-line list of
enabled agent names. The orchestrator already has access to the
agent's `description` field; the description is enough.

**Estimated saving: ~50% of the orchestrator prompt's per-iteration
cost** (~600 tokens per issue, paid once per ralph iteration).

#### 3. ~~Conditional skill loading in engineer~~ — REJECTED

*Originally proposed: load `react-best-practices` + `composition-patterns`
+ `every-layout` only when the slice touches new components / layout /
interactive React.*

Rejected after review: those three skills are how the engineer
*thinks*, not optional knowledge. Making them conditional saves
tokens by making the engineer dumber on small slices, which is
exactly the wrong direction. The skills stay unconditional. Recorded
here as a non-trade-off for future reference.

### MEDIUM impact

#### 4. CONTEXT_FILES read by every sub-agent independently

Orchestrator passes paths only — good — but each sub-agent then reads
the files itself. For a 3-agent slice the same `docs/rules.md` is
loaded 3 times. For a 7-agent design-phase slice, 7 times.

Two options:
- **Pass-through approach:** orchestrator loads the binding rules
  once, passes a *trimmed* version to each agent. Risks rule drift.
- **Cache approach:** keep current pattern but add a hash-check
  ("rules.md unchanged since previous dispatch — skip reload").
  Requires harness instrumentation.

This is medium-impact because the binding rules ARE what the agents
need to follow. Honest cost of the discipline. Worth measuring before
optimising.

#### 5. The harness doesn't use the parallel-dispatch pattern

The orchestrator's `dispatching-parallel-agents` super-power exists for
sending 2+ independent sub-tasks in one round-trip. The harness
prompt mentions sequential flow only. For a slice with PM clarification
+ designer reference-fetching that are mutually independent, those
*could* run in parallel — same wall-clock latency, same token cost,
but main-thread waits for the LATER of the two only once.

Doesn't reduce total tokens; reduces wall-clock per iteration. Probably
worth wiring once the rest of the rules-based wins are taken.

#### 6. The Workflow tool vs per-issue `claude --print` spawn

`ralph.sh` spawns a fresh `claude --print` per issue. Pros: clean
context every iteration, no inter-issue drift. Cons: every iteration
pays the orchestrator-prompt + binding-context tax fresh.

Alternative: ONE long-running orchestrator session that processes the
issue queue using the `Workflow` tool. Each "iteration" becomes a
`Workflow` call; the workflow itself dispatches the specialist agents.
Main thread retains ONE context across N issues, paying the
orchestrator-prompt tax once.

Trade-off: drift risk if the orchestrator's context gets confused
across issues. Mitigation: workflow returns crisp summaries; main
thread compresses its own context between workflows.

Architectural change. Worth prototyping on a small project first.
**Estimated saving: ~30% of total tokens across a multi-iteration
ralph run, if drift is controlled.**

### LOW impact (worth noting, low priority)

#### 7. SKILL.md duplication across agents

`every-layout` is loaded by 4 of 8 agents (PM, AD, designer, engineer).
Same content, four loads in a design-phase slice. If a "skill once
per orchestrator session" cache existed, we'd save ~18 KB / 4500 tokens
per design-phase slice. Requires harness or Claude Code support for
skill-load deduplication.

#### 8. Output discipline isn't enforced

Orchestrator prompt says "be terse, no preamble, no recap." Reviewer
agent doesn't currently check the orchestrator's or sub-agents'
verbosity. Cheap addition to the reviewer eval JSON: a `verbosity`
score with a budget. Doesn't save tokens directly but creates a
feedback signal.

---

## The architectural question worth surfacing

The CTO's "8-hour main thread under 20% context drop" anecdote
suggests they're using **one persistent main thread that dispatches
heavily via Workflow / Agent tools** rather than spawning fresh
processes per issue. Our harness does the opposite: fresh process per
issue, no inter-issue continuity.

Both patterns are defensible:

| | Fresh process per issue (current) | Persistent main + dispatch |
|---|---|---|
| Drift risk | None — each issue starts clean | Possible — main thread can accumulate noise |
| Per-issue tax | Pays orchestrator + binding context every time | Pays once at start; near-zero per dispatch |
| Resumability | Each issue independent | One main session = single point of failure |
| Observability | Output per process is bounded | Main thread context is one growing artefact |

Switching to the persistent pattern is the biggest possible token
win, but it's a different architecture. Worth pitching as the
**phase-2 token review** after the rule-level wins above are taken.

---

## Recommended order

1. **Quick wins** — DONE in this PR:
   - Reviewer + DevOps to Haiku 4.5 (~30% saving on those agents)
   - Trim orchestrator prompt's capability paragraphs (~50% saving on
     orchestrator-prompt cost per iteration)
   - ~~Conditional skill loading in engineer.md~~ — rejected; the
     skills are how engineer thinks, not optional knowledge.

2. **Medium wins** (1 day, medium risk):
   - Parallel-dispatch wiring for genuinely independent sub-tasks
   - CONTEXT_FILES caching / change-detection

3. **Architectural** (week+, prototype first):
   - Persistent-main-thread mode for ralph (Workflow-driven)
   - Skill-load deduplication across a session

---

## Out of scope for this review

- Whether the agents are doing the right work (separate quality
  question, addressed by reviewer eval).
- Specific MCP-tool token cost (depends on MCP design; each MCP added
  ships its tool schema in the agent's tool list).
- Cross-project caching of skill content (would need Claude Code
  platform feature, not a harness change).
