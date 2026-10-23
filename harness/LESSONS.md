# Harness lessons

Notes that drove harness changes. Each entry: what went wrong, what we
changed in the harness so it can't happen the same way again.

---

## 2026-08-13 — Empty-implementation guard (no "verified clean" on no code)

**Context.** CUST-1094: three slices were marked `done` / "verified clean" by
ralph having written no source code — commits `83021e32` (i18n sweep) and
`3ba9b2e6` (atoms) touched only their own issue `.md`. The i18n slice (~52
strings, the biggest piece of the ticket) was entirely absent, yet the PR read
as complete. Caught only by manually diffing `git show --stat` per slice.

**Root cause.** The authoritative verification runs `QUALITY_CHECKS` (lint,
type, test, build, …) and marks the issue done if they pass. But those gates
pass trivially when nothing changed — an agent that does nothing leaves a clean
tree that still lints, types, tests and builds. Passing unchanged gates proves
nothing about whether the work was done.

**The fix in the harness.** After the gates pass, before `mark_issue_done`,
ralph now checks `git status --porcelain` for at least one changed file outside
`issues/`. If there is none, it refuses to mark done: sets the issue to
`needs-info`, commits that status flip, notifies, and continues to the next
slice. An agent must produce a real code (or docs) change to be credited.

**Operator note.** A slice that legitimately requires no code change (e.g. an
audit line that turns out to conflict with a binding rule) should be closed by a
human as `wontfix` with rationale, not left for ralph to "pass" — the guard will
otherwise park it as `needs-info` every run.

---

## 2026-08-12 — Scoped runs auto-branch (no more direct-to-main)

**Context.** CUST-1094 (vcc-migration): a scoped sequential run
(`harness ralph 8 --scope issues/cust-1094-tech-debt/*.md`) was started while
sitting on `main`. All 8 slice commits plus a pre-req fix landed directly on
local `main` with no branch and no PR. Recovered by hand afterwards (moved the
9 commits to a feature branch, reset main, opened the PR), but the work should
never have been on main in the first place.

**Root cause.** The stale-checkout guard allows `main` *or* `ralph/*`, and its
default when already on `main` is to commit to `main`. That is correct for a
whole-backlog trunk run, but a `--scope`d run is feature work and wants
isolation. Nothing branched automatically, and the operator (mistakenly
believing a feature branch would make ralph refuse) ran on main.

**The fix in the harness.**

1. **Auto-branch on scoped sequential runs.** When `harness ralph` is invoked
   with `--scope` while on the default branch and not `--parallel`, it now
   derives `ralph/<feature>` from the scope glob and switches to it before the
   first iteration. Every commit lands on that branch; `main` is never touched.
   `--parallel` is unchanged (it already isolates via worktree branches).
2. `ralph/*` was already an allowed branch, so the derived branch passes the
   refuse check. The operator still opens the PR from `ralph/<feature>`.

**Operator note.** A `--scope`d run no longer needs a manual
`git switch -c ralph/<ticket>` first — the harness does it. Whole-backlog runs
(no `--scope`) still run on `main` by design.

---

## 2026-06-13 — Live parity protocol (parity-match mode)

**Context.** vcc-migration: 48 hours of "fix one element, find another broken
one, fix that, original one drifts again" loops on a Webflow → Astro
migration. Repeatedly told to "match live" and repeatedly failed.

**Root cause.** Every parity decision was made from secondhand signals:
- the extracted Webflow class map (a static JSON snapshot — drifted)
- compiled CSS minified blobs (wrong specificity guesses)
- self-captured screenshots (eyeballing pixel differences)
- parity-gate ratios (a number, not a cause)
- `getComputedStyle()` resolved RGB (hides which `var(--token)` was meant)

None of these tell you "live h2 references `var(--text--primary)` directly
via `.title.w-variant-…`." Only reading the live CSS rule text does.

**The fix in the harness.**

1. **New `HARNESS_MODE=parity-match`** (alongside `poc` / `full`). Activated
   per-project via `harness match init`. Two URL vars: `PARITY_TARGET_URL`
   (reference) and `PARITY_SOURCE_URL` (our build).
2. **Mandatory live-audit step** prepended to every ralph iteration in this
   mode. The orchestrator must open `PARITY_TARGET_URL{route}` via Chrome
   MCP, walk `document.styleSheets`, and extract the matching CSS rule text
   for every element in the issue. Output written to
   `.scratch/<feature>/live-audits/<issue-id>.md` before the engineer is
   dispatched. ralph fails fast if `PARITY_TARGET_URL` is unset.
3. **Engineer contract** in parity-match mode: every code change cites a rule
   from the audit file. No rule, no change.
4. **Reviewer contract** in parity-match mode: diff hunks unbacked by the
   audit auto-fail review.
5. **`docs/rules.md`** "Live parity protocol (BINDING)" section auto-appended
   on `harness match init`.
6. **Producer Phase 2** (Architecture & Tooling) gains a match-mode question.
   On "yes", Producer calls `harness match init` as part of writing
   `.claude/harness.config.sh`.

**Why this works.** The discipline is structural, not advisory. The harness
refuses to dispatch the engineer without a populated audit file. The
reviewer refuses to pass diffs not backed by it. You can't accidentally
fall back to inference because there's nothing to fall back to.

**What this is NOT.** It's not "read the class map first" or "run more
screenshot diffs". Those are still secondhand. The only first-class signal
is the live CSS rule itself, surfaced via Chrome MCP. Everything else is
optional supplementary context.

---

## 2026-06-14 — Composition over per-element styling

**Context.** vcc-migration: a sweep refactor moved inline every-layout
idioms into primitives (Stack, Switcher, Box, Center). The structural shape
was right, but the implementation kept stamping `text-center` onto every
heading and paragraph individually inside the new wrappers — turning the
refactor into wallpaper. Three siblings sharing one alignment ended up
with three identical classes instead of one parent.

**Root cause.** Treating layout, alignment, rhythm, and breathing as
properties of the CHILD instead of the CONTAINER. The mental model was
"this `<h2>` should be centred." The correct model is "this section's
content area is centre-aligned, and the `<h2>` is one of its children."

**The fix in the harness.**

1. **`every-layout` skill** gains a binding "Composition over per-element
   styling" section. Five concrete rules: no per-element `text-*`, no
   per-item `items-*`, no ad-hoc `gap-…` between siblings, no ad-hoc
   `padding-block:…` on `<section>`, primitives (Stack/Box/Center) don't
   layer alignment on top of their structural intent.
2. **Engineer agent** loads the same rule procedurally. Includes a
   self-test: for every child touched, would removing all alignment /
   rhythm / breathing classes leave it correctly laid out given the right
   parent? If no, the intent escaped to the wrong scope. Push it up.
3. **Box primitive** in projects gains an `align` prop (`start | center |
   end`). One container, one prop, every descendant flows. Switching
   alignment becomes a one-line change.
4. **Section breathing** consolidates onto a single `--section-gap` token
   plus a base `section { padding-block: var(--section-gap) }` rule. No
   per-section ad-hoc padding-block.

**Why this works.** Children become portable — they carry typography and
appearance, nothing else. Containers carry layout intent. Adding a sibling
inherits the parent's alignment automatically. Switching the whole
section's alignment is one prop, not a file-wide sweep. Less repetition,
proper separation of concerns, the page just flows.

**What this is NOT.** It's not "use every-layout primitives" — that was
already the rule. It's the layer above: even WITH primitives, you can
still write the same intent on every child. The discipline is one intent,
one scope.

## 2026-06-14 — Background-ralph heartbeat protocol

When dispatching ≥1 `harness ralph` run in the background:

1. **Pre-flight first.** ralph.sh now symlinks `.env` and `node_modules` from the primary worktree if missing, and validates `--target` BEFORE the build runs. Worktrees without these died silently for ~50 minutes on 2026-06-14; never again.
2. **Heartbeat every ~5 min.** Use `ScheduleWakeup` at 270s. On each tick run `harness watch` and emit ONE line per run. Format: `[hh:mm] <name> · <state> · <stage|err>`. Tokenwise-compatible.
3. **Death detection is immediate.** `harness watch` flags a run as DIED if pgrep returns 0 AND the log lacks `Ralph finished`. Surface immediately, do not wait for next tick.
4. **Stop the wakeup chain when every run has finished or died.** No idle ticks.

## 2026-06-14 — No-hacks rule

Trigger: any time a fix is scoped to "the current blocker" (vendor down, quota out, env missing, content not yet imported) rather than to the actual problem shape.

Rule:
1. If the proposed fix would be deleted the moment the blocker clears, it is a hack — say so explicitly to the user.
2. Before proposing, probe the problem shape (`/grill-with-docs` or a focused round of questions) until the durable form is visible. The durable form is content-shape-driven, schema-driven, or capability-driven — never keyed on the blocker's identity (no per-slug maps, no "until Monday" branches, no temporary feature flags that have no removal trigger).
3. If only a hack fits the timebox, name it as a hack, name the durable replacement, and create the follow-up issue for the durable replacement BEFORE shipping the hack.

Self-test before proposing a fix: "Once the blocker clears, do we delete this code? If yes — it's a hack."

## 2026-07-06 — Empty-completion pattern (ralph orchestrator)

Three times in one build (hubspot-forms slices 02 and 03), the orchestrator
read context for 10-30 minutes, dispatched NO engineer, wrote NO code, then
flipped the issue to done and let the quality gates pass trivially (nothing
changed = nothing fails). The reviewer eval caught every instance; without
the eval stage these would have shipped as "verified clean".

Detection: `git show --stat` on the ralph commit. If it touches only the log
file, the issue file, and maybe an audit doc, it is an empty completion.
Zero `Write`/`Edit` lines in the run output confirms it.

Rules:
1. NEVER trust "verified clean" without checking the commit diff has real
   implementation touching src/ or tests/.
2. First occurrence: revert the status flip, append explicit "this is NOT an
   audit task, write the code" remediation notes under ## Comments, rerun.
   This worked once (slice 02 round 3 passed).
3. Second occurrence on the SAME issue: stop ralph, implement in-session with
   TDD + full gates, then dispatch the reviewer agent manually for the eval.
   Do not burn a third iteration.
4. Contributing cause in one case: parity-match mode demanded a live audit of
   a page with no live equivalent (new-feature form) and the iteration
   concluded after auditing. Green-field features on a parity-configured repo
   need HARNESS_MODE flipped on the feature branch.

## 2026-07-06 — ralph --scope is parallel-only

`harness ralph N --scope <glob>` SILENTLY ignores --scope in sequential mode
(SCAN_GLOB is only consulted inside the `if (( PARALLEL ))` branch of
ralph.sh). A sequential run picks from the full ISSUES_GLOB backlog by
priority: on 2026-07-06 it burned 4 iterations on about-us-parity issues
while tasked with hubspot-forms. Until ralph.sh is fixed, sequential
scoping is `--target <id> --once` per issue, chained by the caller. Also:
PRD.md files carrying `Status: ready-for-agent` are pickable issues to
ralph's scanner; strip the status line from PRDs.

## 2026-07-06 — Preflight lint can disagree with an interactive lint run

A file that passed `pnpm lint` in an interactive session failed ralph's
preflight on the identical command (unused catch binding), most plausibly a
stale eslint cache in one of the two contexts. Before dispatching ralph on
a branch with fresh manual commits, run the lint gate cold (or clear
.eslintcache) so the iteration does not die at preflight.
