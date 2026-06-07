---
name: producer
description: Use when the user wants to build a new product or feature end-to-end and asks to use the product engineering harness, the producer, or to "produce"/"build x with the harness". The conversational front-door that drives the harness through its four gated phases.
---

# Producer

## Overview

The Producer is the conversational front-door to the product engineering harness. It walks a build from idea to shipped slices through four gated phases, driving the harness's own toolchain (`harness` CLI + the project skills) in order. Each phase blocks on explicit user sign-off before the next begins.

Without the Producer the user has to know to run `harness init`, then `/grill-with-docs`, then `/to-prd`, then `/to-issues`, then `harness ralph` in the right order. The Producer is that sequence made into one guided, gated flow.

**Core principle:** The Producer orchestrates; it does not improvise. Every phase ends with a sign-off gate. Never skip a gate, never collapse two phases into one, never start `harness ralph` before issues exist.

**Violating the letter of the gates is violating the spirit of the gates.** "Compressing" four gates into one mega-decision is collapsing the gates. Presenting spec + tooling + scope + build as a single "say go and I run" choice is NOT four gates, it is zero. Time pressure does not change this. The gates exist precisely so the user can reverse a tooling choice without re-opening the spec, and reshape issues without rebuilding.

## When to Use

Trigger when the user says any of:
- "build X with the product engineering harness"
- "use the producer to build X"
- "produce X"
- "kick off the harness for X"

Do NOT use for: single-file edits, bug fixes, or work on a project that already has issues ready (`harness status` shows ready issues). Those go straight to `harness ralph --once` or the relevant skill.

## Phase marker (statusline indicator)

The Producer announces the current phase to the terminal statusline by writing a marker file at the project root: `.claude/harness-phase`. The statusline renders it as `🎬 PRODUCER · <n>/4 <Phase>`.

- At the **start of each phase**, overwrite the file with the phase label:
  - Phase 1: `printf '1/4 Spec' > .claude/harness-phase`
  - Phase 2: `printf '2/4 Tooling' > .claude/harness-phase`
  - Phase 3: `printf '3/4 PRD & Issues' > .claude/harness-phase`
  - Phase 4: `printf '4/4 Build' > .claude/harness-phase`
- When the build completes, or the user abandons the run, **clear it**: `rm -f .claude/harness-phase`.

Write the marker as the first action of each phase, before doing the phase's work. Keep the label under 40 characters.

## The Four Phases

The Producer runs these strictly in order. Each is a gate.

```
1. SPEC          →  2. ARCHITECTURE   →  3. PRD & ISSUES    →  4. BUILD
   (greenlight)      & TOOLING            (breakdown)           (ralph)
   harness init      tooling gate +       /to-prd +             harness ralph
   /grill-with-docs  docs/rules.md        /to-issues
        ↓ gate            ↓ gate              ↓ gate              ↓
   sign-off          sign-off            sign-off            delivery
```

### Phase 1 — Spec (Greenlight)

1. `harness init` to bootstrap the project (creates `.claude/harness.config.sh`, `.scratch/`, `docs/agents/`, `CONTEXT.md`).
2. Drive `/grill-with-docs` (the product-manager's interview skill) to resolve intent, scope, and domain language into `CONTEXT.md`.

**Gate:** User signs off on the spec / problem definition before moving on.

### Phase 2 — Architecture & Tooling (Pre-production)

Governed by the "New Project Brainstorm Process" in the user's global `CLAUDE.md`. Surface every relevant Stack & Tooling decision: UI primitives, editor/rich-text, styling, fonts, state, persistence, testing, platform-specific patterns. For each: 2-3 options, one-line tradeoffs, a recommendation.

**Layout is not optional here.** The harness builds on the `every-layout` paradigm (Stack, Box, Center, Cluster, Sidebar, Switcher; logical properties; modular scale; intrinsic responsiveness). It is the structural substrate beneath whatever aesthetic the art-director picks. Confirm it applies (it almost always does for any UI) rather than re-deciding it.

**Gate:** User signs off on tooling. Then write the agreed choices into:
- `docs/rules.md` (binding rules, re-injected every Ralph iteration)
- the project `CLAUDE.md`
- `.claude/harness.config.sh` (`CONTEXT_FILES`, `QUALITY_CHECKS`, `HARNESS_MODE`, `DESIGN_PHASE`)

Set `harness design on` if the build has a visual component.

### Phase 3 — PRD & Issues (Breakdown)

1. `/to-prd` — synthesise the spec into `.scratch/<feature>/PRD.md`.
2. `/to-issues` — break the PRD into vertical-slice issues under `.scratch/<feature>/issues/`.

When the PRD and issues describe UI, every component, page, and template is specified in terms of `every-layout` primitives (which primitive composes the page, which the component, where the measure/Stack/Sidebar/Switcher apply). This is integral, not a polish pass.

**Gate:** User reviews the issue set (`harness status`) and confirms scope before any code is written.

### Phase 4 — Build (Ralph / Shoot)

Run `harness ralph N` (or `--once` / `--target ID`). The orchestrator picks ready issues, dispatches specialists (product-manager → art-director → designer → engineer → tester → reviewer per the mode/design flags), runs quality gates, and commits.

Only after Phase 3 sign-off. The Engineering Contract from global `CLAUDE.md` governs every iteration.

## Quick Reference

| Phase | Drives | Output | Gate |
|---|---|---|---|
| 1. Spec | `harness init`, `/grill-with-docs` | CONTEXT.md, problem definition | spec sign-off |
| 2. Arch & Tooling | global CLAUDE.md process | docs/rules.md, project CLAUDE.md, harness.config.sh | tooling sign-off |
| 3. PRD & Issues | `/to-prd`, `/to-issues` | PRD.md + issues/*.md | issue-set sign-off |
| 4. Build | `harness ralph` | committed slices | per-issue reviewer eval |

## Rationalizations — all of these mean STOP

| Excuse | Reality |
|---|---|
| "User's in a hurry, I'll compress the gates into one" | Compressing = collapsing. One combined gate is zero gates. Run all four. |
| "I can't skip gates, so one mega-gate keeps me compliant" | Letter vs spirit. Four distinct sign-offs or you have violated the skill. |
| "User said trust me / use any stack" | That is permission to recommend, not permission to skip the tooling gate. Present options, get the nod. |
| "It's a demo / throwaway, process is overkill" | Demo scope still gets all four phases. Shrink the content, never the gates. |
| "I'll skip test setup to save time" | The testing decision lives in the tooling gate. Surface it; the user may say skip, but you do not decide silently. |
| "I'll run ralph while they read the issues" | No `harness ralph` before issue-set sign-off. Reading is not signing off. |
| "Layout's a styling detail, the designer handles it" | every-layout is the structural substrate. PRDs and issues specify it; it is not deferred. |

## Red Flags — STOP

- About to run `harness ralph` and no issues exist → STOP, go to Phase 3.
- About to pick a library without presenting options → STOP, go to Phase 2 gate.
- About to present spec + tooling + scope as one "say go" decision → STOP, that is gate-collapsing.
- Reaching for words like "compress", "merge", "express version", "one gate" under time pressure → STOP, run all four.
- User hasn't said "go" / "signed off" and you're starting the next phase → STOP, wait for sign-off.
