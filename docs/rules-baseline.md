# Baseline rules for `docs/rules.md`

The harness re-injects `docs/rules.md` into every Ralph iteration via
`CONTEXT_FILES` in `.claude/harness.config.sh`. The rules below are
framework-agnostic patterns that have proved load-bearing across builds.
Copy the relevant ones into a project's `docs/rules.md` during Phase 2,
then add project-specifics (BEM vocabulary, design tokens, framework
gotchas) underneath.

These rules are written for any front-end stack. Substitute the
framework-specific names (React → your component layer; Tailwind → your
styling layer; Radix → your behaviour-primitive library) when you adopt
them.

---

## Composition: primitives + wrappers (BINDING)

Every visual atom is a small primitive component. Composite components
(sections, page templates, layouts) consume those primitives and own
only their layout / behaviour context. Same atom, different wrappers,
zero duplication.

The rule, stated as a slogan:

> **A `NavLink` knows what a nav link looks like. The `Header` knows
> what a bar looks like; the `MobileNav` knows what a drawer looks like.
> Neither wrapper knows or duplicates the link's typography or colour.**

This applies to **every** visual atom, not just the nav.

**The proactive trigger (BINDING):**

> If the same class-string pattern (or markup shape) is about to appear
> for the 3rd time across the codebase OR across a single diff, **stop
> and extract a primitive now**, not "later".

The default failure mode is each slice writing its own inline class
strings; no single slice owns the duplication; the primitive is never
extracted until a desperate cleanup. The 3-callsite trigger short-circuits
this.

**Rules:**

- **Visual atom = primitive component.** Before re-typing a
  colour/weight/size utility chain inline, STOP and use the primitive.
- **Wrappers carry layout-context only.** A wrapper consumes a primitive
  and adds spacing, dropdown behaviour, slide-in animation, dark/light
  treatment — never the atom's intrinsic typography or colour.
- **No duplicated atom markup.** If the same `<a class="…">` /
  `<button class="…">` / `<div class="…">` appears in two places,
  extract a primitive. Repeating a behaviour-library shell, a layout
  wrapper, or a content body is a rule violation, not a style nit.
- **One primitive, not three flag props.** A `<Button variant="primary"
  size="small">` is correct. `<MyThing isButton isLarge isPrimary>` is
  not. Focused props, no boolean proliferation, presentational content
  separated from behaviour/state.
- **Naming follows existing BEM (or equivalent)** where it already
  exists — the BEM classes live in the global stylesheet, the primitive
  emits them. Don't rename them; don't duplicate them in utilities.

**Reviewer MUST flag** any cross-file or in-file duplication of an
atom's markup as a violation, even if all quality gates pass.

---

## Behaviour primitives come from your a11y library (BINDING)

Where a mature a11y primitive library solves an interaction pattern,
use its primitive. Do NOT hand-roll the state machine, focus management,
or ARIA wiring. Restyle with the project's utility classes; behaviour
stays in the library.

For React projects this is **Radix UI**. The specific patterns to look
for, by name:

- **Dialog** (modal + drawer variants)
- **Accordion**
- **Tabs**
- **Navigation Menu** (header nav with submenus + keyboard support)
- **Dropdown Menu**
- **Popover**
- **Tooltip**
- **Toast**
- **Select**
- **Switch / Slider / Radio Group / Checkbox**

For Vue: `headlessui-vue`, `reka-ui`. For Svelte: `bits-ui`, `melt`. For
SolidJS: `kobalte`. The project's Phase 2 tooling decision names which
library; this rule is what makes that decision actionable.

**The signature of a violation:** any `useState` + manual `onClick` /
`onKeyDown` / `useRef`-for-focus combo implementing one of the patterns
above. Stop, use the primitive.

---

## Work WITH the library — no positioning workarounds (BINDING)

When a library component renders or positions unexpectedly, the bug is
the agent's understanding of its mechanism, not the pixels. Read the
library's documentation and use the INTENDED pattern. Never fight a
positioning system with absolute/fixed magic offsets, z-index
inflation, transform nudges, or !important overrides. Positioning that
implements the documented pattern is fine — and must carry a citation
comment in the same edit (`/* cite: <source> */`). If the intended
mechanism cannot produce the design, STOP and escalate; a painted-over
symptom is a violation even when pixels match. Enforce mechanically
with the PreToolUse hook in hooks/no-positioning-hacks.sh (blocks
uncited positioning smells at write time).

Origin incident: a Radix NavigationMenu Viewport — which by design
renders all panels at the menu root — was "fixed" with offset
utilities instead of being removed per the docs (per-trigger anchoring
= Content inside a relative Item, no Viewport).

## Component-specific CSS lives with the component (BINDING)

`global.css` (or its equivalent) carries **foundational concerns only**:

- Design tokens (theme block, custom properties)
- Body / html reset
- BEM rules consumed by primitives (`.btn--*`, `.main-nav__*`, etc. —
  the classes the primitives emit)
- Site-wide containers / utility classes used across many components
- Cross-cutting modifiers (e.g. `.dark` text inversion)

**Component-specific CSS does NOT belong in global.css.** If a keyframe,
animation, state-specific rule, or one-component selector serves only
one component, co-locate it in a sibling CSS file imported from that
component (e.g. `FaqAccordion.tsx` + `FaqAccordion.css`). Vite-style
bundlers handle this automatically; keyframes are intrinsically global
but their *source of truth* lives with the behaviour that owns them.

**Test:** if you remove the component from the project, does the
`global.css` rule make sense on its own? If no, it belongs with the
component.

---

## Build from verified sources, mode-aware (BINDING)

The Producer's Phase 1 mode question (clone vs greenfield) determines
what counts as a verified source for this project.

**Clone / migrate / rebuild mode:**

- The verified source is the **rendered result** of the live thing:
  computed styles via `getComputedStyle` / DevTools probes, captured
  screenshots, the actual DOM. Source CSS files are *evidence* (you can
  inspect them to find token values), not *source-of-truth-to-import*.
- **NEVER import the source project's compiled CSS wholesale.** It will
  carry dev/prod divergence, kill tree-shaking via modern selectors,
  and prevent natural primitive extraction. Re-author natively in the
  new stack's idioms.
- Captures live under a stable path (e.g. `tests/fixtures/captures/`)
  and serve as the fidelity oracle.

**Greenfield mode:**

- The verified source is the **design context** gathered in Phase 1:
  wireframes, mocks, brand guides, competitor patterns, reference
  systems.
- Build natively from those sources; never copy a competitor's
  compiled CSS as a shortcut.
- If a reference system was used to inform the design (e.g. "build
  something like X's checkout flow"), that's research informing the
  design, not source code to import.

In both modes: hand-derived values without a cited source are a rule
violation. The cited source is just what counts as one.

---

## Self-baselines are drift guards, not fidelity gates (BINDING)

A self-baselined screenshot test (e.g. Playwright's `toHaveScreenshot`
without an external reference) compares a rendered page to a screenshot
of itself, captured at some earlier point. It is useful as a **drift
guard** (catch unintentional visual change between approved render and
next render) but it is **NOT a fidelity gate** (it cannot verify the
page is correct, because the baseline is whatever was approved before).

**Rules:**

- Self-baselines pass trivially on the first capture, regardless of
  whether the page is correct.
- For clone projects, the fidelity gate must compare against an
  **external reference** (captured screenshots of the live thing, plus
  structured assertions on computed colours / typography).
- For greenfield projects, the fidelity gate is design-review against
  the captured design context — humans, or designer-agent passes against
  the reference artefacts.
- After an intentional refactor or visual change, **re-baseline the
  self-baseline snapshots** in the same commit, explicitly. Treating a
  self-baseline failure as a fidelity bug is a category error.

---

## Engineering Contract — primitive audit (additive)

The Engineering Contract's self-audit step at end-of-task should
include a positive primitive-extraction check, not only "did I follow
the named rules":

> **Scan the diff for class-string patterns (or markup shapes) that
> appear 3 or more times.** For each: name the pattern, name the
> primitive that should own it, decide whether to extract now (preferred)
> or surface as a follow-up issue. Report the finding before claiming
> the work complete.

This is the active counterpart to the passive "don't duplicate"
rule — it forces the agent to look for duplication rather than just
hoping not to introduce it.
