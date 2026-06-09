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
2. **Ask the mode question — first, explicitly, before anything else:**

   > *"Is this a clone / migrate / rebuild of something that already exists,
   > or a greenfield build?"*

   The answer routes the rest of Phase 1 down one of two paths. Skipping this
   question is how Phase 1 ends with under-specified context, which is how
   slices get written against the wrong source-of-truth.

3. **Branch on the answer:**

   **Clone / migrate / rebuild path**
   - Ask for the source(s) — production URL(s), reference design, asset
     locations, brand/style guides if any.
   - The "verified source" for this project is the **rendered result** of
     the live thing: DOM, computed styles via `getComputedStyle` / DevTools
     probes, captured screenshots. **It is NOT the live project's source
     CSS file.** Capturing styles to re-author natively is the goal;
     importing the source CSS wholesale is the failure mode.
   - Prompt the user to run the relevant skills (do NOT auto-run): the
     firecrawl skills for site scraping and design-system extraction
     (`firecrawl-website-design-clone`, `firecrawl-scrape`,
     `firecrawl-download`), Claude-in-Chrome for live computed-style
     probing, and any tooling for capturing reference screenshots.
   - End Phase 1 with: `CONTEXT.md` describing the target, what was
     captured, where captures live, and the fidelity bar.

   **Greenfield path**
   - Ask for design context: existing wireframes / mocks / Pencil files,
     competitive references, brand voice notes, design system constraints.
     If none exist, route through a design-exploration step before slice
     planning.
   - Prompt the user to run the relevant skills (do NOT auto-run):
     `frontend-design` for UI exploration, `firecrawl-competitive-intel`
     for competitor patterns, `firecrawl-website-design-clone` against
     reference sites whose design is being drawn on, Pencil MCP for
     wireframes.
   - End Phase 1 with: `CONTEXT.md` describing the problem, the design
     constraints, the references, and the visual direction.

4. Drive `/grill-with-docs` (the product-manager's interview skill) to
   resolve intent, scope, and domain language into `CONTEXT.md`.

**Gate:** User signs off on the spec / problem definition AND on the
mode-specific context gathered. The mode itself is recorded in
`CONTEXT.md` because subsequent phases reference it.

### Phase 2 — Architecture & Tooling (Pre-production)

Governed by the "New Project Brainstorm Process" in the user's global `CLAUDE.md`. Surface every relevant Stack & Tooling decision: UI primitives, editor/rich-text, styling, fonts, state, persistence, testing, platform-specific patterns. For each: 2-3 options, one-line tradeoffs, a recommendation.

**Layout is not optional here.** The harness builds on the `every-layout` paradigm (Stack, Box, Center, Cluster, Sidebar, Switcher; logical properties; modular scale; intrinsic responsiveness). It is the structural substrate beneath whatever aesthetic the art-director picks. Confirm it applies (it almost always does for any UI) rather than re-deciding it.

**Behaviour primitives are not optional either.** For any framework with a
mature a11y primitive library (React → Radix UI; Vue → headlessui-vue;
Svelte → bits-ui or melt; etc.), name it explicitly during tooling
sign-off and write down the specific patterns it solves: tabs, accordion,
dialog/drawer, dropdown menu, navigation menu, popover, tooltip, toast,
select, switch, slider, radio group, checkbox. The rule that the build
phase enforces ("before `useState` + custom event handlers for any of
these, reach for the primitive") needs the list of patterns named here
to be actionable.

**Once tooling is chosen, consult framework docs MCPs if available.**
Connect (or instruct the user to connect) the stack's documentation MCP
servers — e.g. an Astro/React/Vue/Tailwind/etc. docs MCP — so the
orchestrator and specialists query authoritative current docs rather
than relying on training-data idioms. Do this NOW, not mid-slice. The
cost of looking up the idiomatic API is paid once; the cost of building
a slice against an outdated pattern and rewriting it later is paid
many times.

**Gate:** User signs off on tooling. Then write the agreed choices into:
- `docs/rules.md` (binding rules, re-injected every Ralph iteration)
- the project `CLAUDE.md`
- `.claude/harness.config.sh` (`CONTEXT_FILES`, `QUALITY_CHECKS`, `HARNESS_MODE`, `DESIGN_PHASE`)

Set `harness design on` if the build has a visual component.

### Phase 3 — PRD & Issues (Breakdown)

1. `/to-prd` — synthesise the spec into `.scratch/<feature>/PRD.md`.
2. **Primitives Plan** — before issues, write a short
   `.scratch/<feature>/PRIMITIVES.md` listing every atomic primitive
   the project will need:
   - **Visual atoms** (the buttons, link variants, headline patterns,
     section wrappers, cards, badges, tags, form controls, prose
     wrappers, etc. the UI repeats) — name them, name the BEM/utility
     class they own, name where they live.
   - **Behaviour primitives** (tabs, accordion, dialog/drawer, menu,
     tooltip, popover, toast, etc.) — name the Radix-or-equivalent
     primitive each one wraps.

   The Primitives Plan is the antidote to the most common slice-debt
   failure mode: each slice writes its own inline class strings, no
   single slice owns the duplication, the primitive is never extracted
   until a desperate cleanup. Naming the primitives BEFORE issue 1
   means the issues can reference them and the build agents reach for
   them.
3. `/to-issues` — break the PRD into vertical-slice issues under `.scratch/<feature>/issues/`. Each issue that touches UI references the relevant primitives from `PRIMITIVES.md`.

When the PRD and issues describe UI, every component, page, and template is specified in terms of `every-layout` primitives (which primitive composes the page, which the component, where the measure/Stack/Sidebar/Switcher apply). This is integral, not a polish pass.

**Gate:** User reviews the issue set (`harness status`) AND the Primitives Plan, and confirms scope before any code is written.

### Phase 4 — Build (Ralph / Shoot)

Run `harness ralph N` (or `--once` / `--target ID`). The orchestrator picks ready issues, dispatches specialists (product-manager → art-director → designer → engineer → tester → reviewer per the mode/design flags), runs quality gates, and commits.

Only after Phase 3 sign-off. The Engineering Contract from global `CLAUDE.md` governs every iteration.

## Quick Reference

| Phase | Drives | Output | Gate |
|---|---|---|---|
| 1. Spec | mode question (clone or greenfield), `harness init`, mode-specific context-gathering skills (opt-in), `/grill-with-docs` | CONTEXT.md including the build mode + sources/refs gathered | spec + context sign-off |
| 2. Arch & Tooling | global CLAUDE.md process; name behaviour-primitive library; connect framework docs MCPs | docs/rules.md, project CLAUDE.md, harness.config.sh | tooling sign-off |
| 3. PRD & Issues | `/to-prd`, **Primitives Plan**, `/to-issues` | PRD.md + PRIMITIVES.md + issues/*.md | issue-set + primitives sign-off |
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
