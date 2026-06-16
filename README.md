# Product Engineering Harness

A project-agnostic build harness for AI-driven software work. Turns a fuzzy idea into shipped slices via an orchestrator-and-specialists model, with verification on every step. Installs into `~/.claude/` and drives Claude Code.

Two things make it work:

1. An **autonomous loop** (`harness ralph`) that picks the next ready issue, dispatches specialist sub-agents, runs quality gates, and commits.
2. A **mode dial** so the team you dispatch grows with the project: lean during proof-of-concept, full when you're heading toward production.

## The front door: `/producer`

The fastest way in is the **`producer`** skill. Say *"build X with the product engineering harness"* and it walks you through four gated phases as one guided flow, driving the commands and skills below in order:

```
1. SPEC          →  2. ARCHITECTURE   →  3. PRD & ISSUES   →  4. BUILD
   harness init      & TOOLING            /to-prd              harness ralph
   /grill-with-docs  (tooling gate +      /to-issues
                      docs/rules.md)
```

Each phase ends in an explicit sign-off gate; the Producer never collapses them or starts `ralph` before issues exist. You can still run the steps by hand (see the walkthrough below) if you prefer.

## Install

Two paths. Pick by intent.

### User install (read-only consumer)

```bash
git clone https://github.com/h0rhay/product-engineering-harness.git
cd product-engineering-harness
./install.sh            # copies agents + harness scripts into ~/.claude/
source ~/.zshrc         # pick up the `harness` alias
```

`install.sh` copies files into `~/.claude/`, adds the `harness` alias, and appends the Engineering Contract to `~/.claude/CLAUDE.md`. To pick up upstream changes: `git pull && ./install.sh` again.

### Maintainer install (live-edit + contribute upstream)

If you want every edit you make under `~/.claude/harness/` to land back here as a PR (recommended for anyone who works on the harness):

```bash
git clone https://github.com/h0rhay/product-engineering-harness.git ~/Sites/product-engineering-harness
rm -rf ~/.claude/harness                                                 # remove any prior vendor drop
ln -s ~/Sites/product-engineering-harness/harness ~/.claude/harness      # symlink the install
source ~/.zshrc
```

Now editing any file in `~/.claude/harness/` is editing the git checkout. The standard branch-first flow applies:

```bash
cd ~/Sites/product-engineering-harness
git checkout main && git pull origin main
git checkout -b feat/<change>
# edit files; every edit is reflected in ~/.claude/harness/ instantly via the symlink
git add -A && git commit -m "feat(...): ..."
git push -u origin feat/<change>
gh pr create --base main
```

When the PR merges, `git checkout main && git pull` brings the symlinked install back to mainline. No re-install needed.

`install.sh --link` does the symlink wiring for you if you'd rather not do it by hand.

### Optional: statusline phase indicator

The `producer` skill writes the active phase to `<project>/.claude/harness-phase` (e.g. `2/4 Tooling`) at the start of each phase, and clears it on completion. `install.sh` does **not** touch your statusline — wiring it in is a manual, one-time edit to your own `~/.claude/statusline-command.sh` so it can render the marker, e.g. `🎬 PRODUCER · 2/4 Tooling`.

Add this near the top of the script (after it has the session's `cwd`):

```bash
# Product engineering harness phase (written by the producer skill)
PROJECT_ROOT="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || echo "$CWD")"
HARNESS_PHASE=""
[ -f "$PROJECT_ROOT/.claude/harness-phase" ] && \
  HARNESS_PHASE=$(head -n1 "$PROJECT_ROOT/.claude/harness-phase" | tr -d '\n' | cut -c1-40)
```

Then render it wherever you build the line, only when set:

```bash
[ -n "$HARNESS_PHASE" ] && printf '🎬 PRODUCER · %s ' "$HARNESS_PHASE"
```

No marker means no segment, so your statusline is unchanged outside an active `producer` run. Add `.claude/harness-phase` to the project's `.gitignore` if you don't want the transient marker committed.

---

## Architecture in one screen

```
                       ┌─────────────────────────────────────────┐
                       │     ~/.claude/harness/  (entry point)    │
                       │     `harness <subcommand>`               │
                       └───────────────────┬─────────────────────┘
                                           │
        ┌────────────────────┬─────────────┼─────────────┬──────────────────┐
        │                    │             │             │                  │
   harness init        harness ralph   harness status  harness mode/design/graduate
   bootstrap project   autonomous loop  show backlog    flip per-project flags
        │                    │
        │                    ▼
        │         ┌──────────────────────────────────────────────────┐
        │         │  Orchestrator (Claude Opus, --dangerously-skip)   │
        │         │  picks next ready issue, dispatches specialists   │
        │         └────────────────────┬──────────────────────────────┘
        │                              │
        │     ┌────────────────┬───────┴───────┬──────────────┬──────────────┐
        │     ▼                ▼               ▼              ▼              ▼
        │  product-manager  art-director   designer        engineer       tester
        │  (poc + full)     (design phase) (design phase)  (poc + full)   (poc + full)
        │                                                  │              │
        │                                                  └──┬───┬───────┘
        │                                                     │   │
        │     ┌───────────────────────┬────────────────┐      │   │
        │     ▼                       ▼                ▼      │   │
        │   devops                  security        reviewer ◄┘   │ (LLM-judge eval
        │   (full only)             (full only)    (always)       │  after gates)
        │
        └──> writes per-project config: .claude/harness.config.sh
             writes issue layout:        issues/<feature>/, docs/prds/<feature>.md, docs/agents/
             scratch (gitignored):       .scratch/ for genuine cruft only (captures, dumps)
```

The orchestrator does not implement; it delegates. Each specialist owns a narrow job. Reviewer is read-only and emits a structured JSON eval. Specialists never call each other directly: routing always goes through the orchestrator.

---

## Commands (every one)

```
harness init                  Bootstrap current project (.claude/, issues/, docs/, CLAUDE.md block)
harness ralph [N]             Run autonomous loop, N iterations (default 10)
harness ralph --once          Single iteration with verbose output
harness ralph --target ID     Run against one specific issue (filename stem)
harness ralph --parallel      Fan out unblocked ready issues into git worktrees, run concurrently
harness ralph --scope GLOB    Restrict --parallel to one PRD, e.g. "issues/parity-cta-restore/*.md"
harness ralph --merge-ready   Sweep ralph/parallel-* branches whose issue is Status: done; merge locally
harness status                Show backlog: ready, blocked, done counts + current mode
harness watch                 Terse heartbeat: one line per in-flight or completed ralph run
harness match <sub>           Parity-match mode (clone / migration / rebrand)
harness mode <poc|full>       Set HARNESS_MODE
harness design <on|off>       Set DESIGN_PHASE
harness graduate              Shortcut: mode=full + design=on (ready-for-prod)
harness help                  Show all of the above
```

### Heartbeat protocol (visibility during long parallel runs)

Background ralph runs are silent by default. `harness watch` solves that.

```bash
harness watch
# [18:09:01] ralph-extract-modern-slavery-1781629668 · live   5s · Picked
# [18:09:01] ralph-close-wontfix-404s-1781629668     · live   5s · Picked
# [18:09:01] ralph-carousels                         · DONE · verdict: pass
# [18:08:27] ralph-doc-fallback                      · DIED · ELIFECYCLE Test failed
```

One line per run. Three states: `DONE` (verdict + duration), `DIED` (process gone, log doesn't end with "Ralph finished"; surfaces the last error), `live Ns` (still going, seconds-since-last-activity + current stage). Scans both `/tmp/ralph-*.log` and `<project>/.claude/worktrees/*/.ralph.log`.

When driving the harness from Claude Code, follow the four-point protocol from [`harness/LESSONS.md`](harness/LESSONS.md):

1. **Pre-flight validation.** `harness ralph --target ID` exits non-zero fast if the issue is missing or worktree misconfigured. Catch failures in seconds, not hours.
2. **`ScheduleWakeup` every 270s while any run is live.** Each tick runs `harness watch` and surfaces status to the user.
3. **Detect silent death immediately.** `harness watch` reports `DIED` when the process is gone but the log doesn't end with the success marker.
4. **Stop the chain when all `DONE`/`DIED`.** No idle ticks.

### Parallel mode notes

- Spawns at most `RALPH_PARALLEL_MAX` worktrees (default 4) under `<project>/.claude/worktrees/`.
- Each worktree gets its own `pnpm install`, serialized via a mkdir-based lock so parallel installs don't corrupt pnpm's content store.
- Singleton-resource quality checks (e.g. a Playwright dev server on a fixed port) should be wrapped with `~/.claude/harness/with-lock.sh <lock-dir> <cmd>` inside `QUALITY_CHECKS` so only one worktree runs them at a time. `with-lock.sh` is a portable mkdir mutex (macOS has no `flock`).
- `export CI=true` is set at the top of `ralph.sh` so pnpm never blocks on TTY confirmation in any subprocess.
- On success a worktree's branch (`ralph/parallel-<id>-<ts>`) is left in place. `--merge-ready` folds passing branches back into the branch you invoked from. No auto-push; raise the resulting branch as a PR yourself, or run the per-slice PR sweep (TODO flag).

All commands operate on the current working directory's `.claude/harness.config.sh`. The global scripts live at `~/.claude/harness/` and are invoked via the `harness` shell alias (sourced from `~/.zshrc`).

---

## Modes and AGENTS_ENABLED

Two orthogonal flags compose the team the orchestrator can dispatch:

| Flag | Values | Adds |
|------|--------|------|
| `HARNESS_MODE` | `poc` (default) | product-manager, engineer, tester |
| | `full` | + devops, security |
| `DESIGN_PHASE` | `disabled` (default) | nothing |
| | `enabled` | + art-director, designer |

Reviewer is always on. It runs as the post-quality-gates eval stage.

Typical lifecycle:

```
new project        →  harness init  (poc, design disabled)
visual work starts →  harness design on
ready for prod     →  harness graduate     (full + design on)
need to bypass     →  harness mode poc     (drops devops/security)
```

Slop-free shorthand for the orchestrator: any agent not in `AGENTS_ENABLED` must NOT be dispatched. The orchestrator prompt enforces this.

---

## The specialists, one line each

| Agent | Role |
|-------|------|
| product-manager | Turns fuzzy ideas into PRDs with acceptance criteria; defers visual + implementation to the right specialists |
| art-director | Owns visual direction: taxonomy, typography, palette, motion, anti-slop refusal list; audits designer output via Impeccable |
| designer | Executes the direction brief via Pencil CLI Agent Mode (primary), `skillui` for reference extraction, 21st.dev for taste exposure |
| engineer | Implements React + TypeScript per `react-best-practices` and `composition-patterns`; loads project binding rules every iteration |
| tester | Writes Vitest / jsdom tests using red-green-refactor; external-behaviour assertions only |
| devops | Git hygiene, remote setup, branch / commit / PR conventions, deployment plumbing |
| security | Vercel deepsec scan + manual checklist; writes findings as new ready-for-agent issues for engineer to fix |
| reviewer | Read-only LLM-judge eval. Emits JSON with verdict + per-category scores + violations after quality gates pass |

---

## The supporting skills, one line each

| Skill | Use |
|-------|-----|
| `/producer` | Front-door orchestrator. Drives the four gated phases (spec → tooling → PRD/issues → ralph). Harness-native, vendored in this repo |
| `every-layout` | **Binding** layout substrate. Stack / Box / Center / Cluster / Sidebar / Switcher, logical properties, modular scale, intrinsic responsiveness. Loaded by product-manager, art-director, designer, engineer. Harness-native, vendored in this repo |
| `/grill-with-docs` | Interview-driven design that updates CONTEXT.md and ADRs inline |
| `/to-prd` | Synthesise the current conversation into a PRD file |
| `/to-issues` | Break a PRD into vertical-slice issues with Status / Priority / Blocked-by |
| `/triage` | State machine for inbound bugs and feature requests |
| `/diagnose` | Disciplined repro → minimise → hypothesise → fix loop |
| `/tdd` | Red-green-refactor for any slice with tests in scope |
| `/react-best-practices` | Vercel performance rules (engineer loads by default) |
| `/composition-patterns` | React composition rules (engineer loads by default) |
| `/impeccable` | Primary design system. Sub-commands: `craft`, `shape`, `audit`, `polish`. Used by art-director and designer |
| `/frontend-design` | Anthropic's frontend-design skill. Secondary reference behind Impeccable |
| `/tokenwise` | Terse-response mode, baked into orchestrator prompts |
| `stripe-design` (auto-generated) | A SkillUI distillation of stripe.com; example of how SkillUI output becomes a reusable Claude skill |

---

## The external tools wired in

| Tool | What it does | How designer uses it |
|------|-------------|----------------------|
| **Pencil CLI** (`@pencil.dev/cli`) | Headless `.pen` composition via natural-language prompt | `pencil --in <prev> --out <new> --prompt "<brief>"` produces a `.pen` on disk; `--export` produces a screenshot. Primary path. |
| **Pencil MCP** | Live in-app editing of the running Pencil.app working copy | 13 `mcp__pencil__*` tools. Fallback for live iteration; no save tool (user must Cmd+S). |
| **SkillUI** (`skillui` CLI) | Reverse-engineers any website into a Claude-readable design skill | `skillui --url https://example.com --mode ultra` writes a DESIGN.md + SKILL.md folder that auto-registers as a skill. |
| **Impeccable** | Hardened evolution of frontend-design; register-aware references and sub-commands | Invoked first by art-director and designer; `audit` sub-command drives the post-mockup approve/revise/reject. |
| **21st.dev** | Component reference library | Fetched via Firecrawl when the direction brief names specific component categories to study. |
| **Vercel deepsec** | Agent-powered vulnerability scanner | Security agent runs `npx deepsec init/scan/process/revalidate/export` on production-bound codebases. Cost-gated. |

---

## Architecture reference docs

- [`docs/rules-baseline.md`](docs/rules-baseline.md) — framework-agnostic
  rules to copy into a project's `docs/rules.md` during Phase 2:
  primitives + wrappers (with the proactive 3+-callsites trigger),
  behaviour primitives from your a11y library (Radix/headlessui/bits-ui),
  component-CSS-co-location, verified-sources mode-aware (clone vs
  greenfield), self-baselines as drift guards.
- [`docs/anti-pattern-hook.md`](docs/anti-pattern-hook.md) — the PreToolUse
  hook pattern for flagging anti-patterns about to be reintroduced after
  a primitive is extracted. Includes the project-agnostic `FLAG_ISLAND`
  / `FLAG_SWIPER` flags and shows how to add project-specific ones.

---

## Per-project configuration

Lives at `.claude/harness.config.sh` after `harness init`. Example:

```bash
PROJECT_NAME="TodoTest"
COMMIT_PREFIX="feat(ralph)"

QUALITY_CHECKS=(
  "pnpm lint"
  "pnpm test -- --run"
  "pnpm typecheck"
  "pnpm build"
  # Singleton-port E2E wrapped in with-lock so parallel worktrees don't fight for port 4321.
  "~/.claude/harness/with-lock.sh /tmp/<project>-e2e.lock pnpm test:e2e"
)

CONTEXT_FILES=(
  "docs/rules.md"
  "docs/prds/todo-app.md"
)

ISSUES_GLOB="issues/*/*.md"

HARNESS_MODE="poc"
DESIGN_PHASE="disabled"

AGENTS_ENABLED=("product-manager" "engineer" "tester")
case "$HARNESS_MODE" in
  full) AGENTS_ENABLED+=("devops" "security") ;;
esac
case "$DESIGN_PHASE" in
  enabled) AGENTS_ENABLED+=("art-director" "designer") ;;
esac
```

`CONTEXT_FILES` are **binding rules**. Ralph re-injects them on every iteration. If you want Tailwind-only styling, Convex-only data access, no barrel imports, etc., put them in `docs/rules.md` and list that file here. This is the forcing function that prevents the agent from "forgetting" the rules between iterations.

---

## Issue file format

Plain markdown under `issues/<feature>/<NN>-<slug>.md` (tracked in git, so worktrees and parallel runs see them natively). PRDs live alongside under `docs/prds/<feature>.md`:

```markdown
# 03 — delete a todo

Status: ready-for-agent
Priority: 1
Blocked-by: 02-toggle-done

## What to build
One-click delete on each todo row, no confirm, no undo. Persists to localStorage.

## Acceptance criteria
- [ ] × button appears on row hover
- [ ] Click removes the row immediately
- [ ] localStorage no longer contains the deleted todo on reload
- [ ] All quality gates pass
```

Status values: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `done`, `wontfix`.

Ralph picks the lowest-Priority `ready-for-agent` issue with no unresolved `Blocked-by`. On success it sets `Status: done` and commits with `<COMMIT_PREFIX>: <id>, <summary>`.

---

## End-to-end workflow walkthrough

### Phase 1: design and slice

```
cd ~/Sites/MyApp
harness init                         # bootstrap; ends in poc mode, design off
/grill-with-docs                     # 20 minutes of focused interview
/to-prd                              # synthesises docs/prds/<feature>.md
/to-issues                           # vertical slices into issues/<feature>/*.md
harness status                       # confirm what's ready
```

### Phase 2: visual work begins

```
harness design on                    # enables art-director + designer
                                     # next ralph run will route visual issues through them
pencil login                         # one-time auth for Pencil CLI Agent Mode
harness ralph 10                     # ralph dispatches the full design phase + engineering for each visual slice
```

### Phase 3: heading to production

```
harness graduate                     # flips to full mode + design on
                                     # devops + security now dispatchable
harness ralph --target deploy-prep   # devops sets up remote, branches, PR conventions
                                     # security runs deepsec + manual checklist on the codebase
```

### Phase 4: ongoing

```
inbound bug:    /triage <ref>  →  /diagnose if needed  →  harness ralph --once
new feature:    /grill-with-docs  →  /to-prd  →  /to-issues  →  harness ralph N
status check:   harness status
```

---

## The design phase, in detail

When `DESIGN_PHASE=enabled` and a slice has a visual component, the orchestrator runs this sub-loop before dispatching engineer:

```
art-director  →  writes .scratch/<feature>/direction/<NN-slice>.md
                  (taxonomy, typography, palette, motion, anti-slop list, tool commands)
       ↓
designer      →  runs skillui on reference sites named in the brief
                  shells out to `pencil --in --out --prompt` (Agent Mode, persists .pen)
                  shells out to `pencil --in --export` for per-frame screenshots
                  shells out to `open <.pen>` to surface the result in Pencil.app
                  writes .scratch/<feature>/design/<NN-slice>-handoff.md (tokens + Tailwind classes)
       ↓
art-director  →  audits the screenshots + handoff via Impeccable's `audit` sub-command
                  verdict: approve / revise / reject
       ↓ (approve only)
engineer      →  reads the approved direction + handoff + screenshots
                  implements against the project's binding rules
       ↓
quality gates →  lint, test, typecheck, build (must all pass)
       ↓
reviewer      →  4-category scored eval, JSON to .scratch/<feature>/issues/<id>.eval.json
                  verdict: pass / concerns / fail
```

A `concerns` verdict triggers a small follow-up loop; `fail` blocks the slice. The whole thing runs unattended per `harness ralph`.

---

## File layout

This repo (the source of truth):

```
product-engineering-harness/
├── README.md                                      # ← you are here
├── LICENSE                                        # MIT
├── install.sh                                     # copy/symlink into ~/.claude/, wire alias + contract
├── agents/                                        # the 8 specialist sub-agents
├── harness/                                       # the bash scripts (harness.sh, ralph.sh, ...)
├── contract/engineering-contract.md               # the Engineering Contract block + rationale
├── skills/_install-skill.sh                       # helper to install skills from any GitHub tree URL
└── examples/README.md                             # the TodoTest validation walkthrough
```

After `./install.sh`, the layout under `~/.claude/`:

```
~/.claude/                                         # global config
├── CLAUDE.md                                      # Engineering Contract (skill announce + self-audit)
├── agents/                                        # specialist sub-agents (from this repo)
│   ├── art-director.md  designer.md  devops.md  engineer.md
│   └── product-manager.md  reviewer.md  security.md  tester.md
├── harness/                                       # the build harness scripts (from this repo)
│   ├── harness.sh                                 # entry point dispatcher
│   ├── harness-init.sh                            # project bootstrap
│   ├── harness-status.sh                          # backlog summary
│   ├── harness-toggle.sh                          # mode / design / graduate
│   ├── harness-match.sh                           # parity-match mode (clone / migration / rebrand)
│   ├── harness-watch.sh                           # heartbeat for background ralph runs
│   ├── ralph.sh                                   # autonomous loop (incl. --parallel)
│   ├── ralph-progress.sh                          # stream-json progress renderer
│   ├── eval-stage.sh                              # reviewer dispatch + JSON emit
│   └── with-lock.sh                               # portable mkdir mutex (macOS has no flock)
├── skills/                                        # installed skills (Anthropic + Vercel + community)
│   ├── _install-skill.sh                          # `~/.claude/skills/_install-skill.sh <github-tree-url>`
│   ├── impeccable/                                # primary design system
│   ├── frontend-design/                           # secondary
│   ├── react-best-practices/, composition-patterns/, ...
│   └── stripe-design/                             # example: auto-generated by SkillUI
└── projects/<workspace>/memory/                   # auto-memory (per-machine, not shipped)

<project-root>/                                    # in each project after `harness init`
├── .claude/harness.config.sh                      # per-project flags + binding rules
├── .claude/worktrees/                             # parallel ralph worktrees (gitignored)
├── issues/<feature>/                              # TRACKED in git
│   ├── <NN>-<slug>.md                             # output of /to-issues (Status / Priority / Blocked-by)
│   └── <NN>-<slug>.eval.json                      # reviewer eval (per slice)
├── docs/prds/<feature>.md                         # TRACKED — output of /to-prd
├── docs/agents/{issue-tracker,triage-labels,domain}.md   # Matt Pocock conventions, with our defaults
├── docs/rules.md                                  # binding rules (Tailwind-only, no inline style, etc.)
├── CONTEXT.md                                     # populated lazily by /grill-with-docs
└── .scratch/<feature>/                            # GITIGNORED — genuine cruft only
    ├── direction/<NN>-<slug>.md                   # art-director output (regenerable)
    └── design/                                    # designer output (regenerable)
        ├── <NN>-<slug>.pen                        # Pencil source
        ├── <NN>-<slug>-handoff.md                 # engineer-facing
        ├── <NN>-<slug>.prompt.md                  # what Pencil's agent received
        ├── <NN>-pencil-agent.log                  # CLI run log
        ├── screenshots/<NN>-pencil-<frame>.png
        └── skills/<ref-name>/                     # SkillUI output (regenerable)
```

---

## Design principles

- **Bash, not Python.** Portable, no install step, runs anywhere.
- **Markdown files, not JSON.** Human-readable, grep-able, edit by hand if needed.
- **Per-project config.** No path is hardcoded in the global scripts.
- **Orchestrator delegates, never implements.** Specialists own narrow jobs. Reviewer is read-only.
- **Binding rules are re-injected every iteration.** Forcing function against "I forgot to use Tailwind."
- **Composition over modes.** `HARNESS_MODE` and `DESIGN_PHASE` compose into `AGENTS_ENABLED`; the orchestrator prompt enforces dispatch only of enabled agents.
- **Anti-slop refusal lives in art-director only.** Single source of truth for taste. Designer executes; engineer implements; neither overrides.

---

## Validated in real projects

### vcc-migration (Webflow → Astro + Storyblok migration, 2026-06)

The harness drove a parity-restoration PRD (homepage + marketing-page CTA buttons) using the new parallel mode. What this session proved:

1. **`harness ralph --parallel --scope "issues/<feature>/*.md"`** fans out unblocked ready issues into git worktrees and runs them concurrently. Wall-clock drops with parallelism; each slice still gets a full quality-gate pass (lint / typecheck / test / build / parity-gate) inside its worktree.
2. **Tracked issues at `issues/<feature>/*.md` survive worktrees natively.** Removing the gitignore on the task tracker eliminated a whole class of "issue file missing in worktree" bugs that earlier band-aids tried to paper over with rsync.
3. **`with-lock.sh` serializes singleton resources.** Wrapping the parity-gate Playwright run (binds port 4321) in `with-lock.sh /tmp/<project>-parity.lock` lets the rest of the gate (lint / typecheck / test / build) run truly in parallel across worktrees, while only the port-bound step queues.
4. **Symlinked install picks up upstream changes by `git pull`.** With `~/.claude/harness → ~/Sites/product-engineering-harness/harness`, the same `git checkout main && git pull` flow that updates any repo updates the global install. No re-install step.
5. **`export CI=true` at the top of `ralph.sh`** propagates to every subprocess so `pnpm install` never blocks on TTY confirmation in worktrees, CI, or background runs.

### TodoTest (smoke-test app, earlier session)

The harness ran 8 slices end-to-end on a smoke-test app (`h0rhay/TodoTest`, private). Specifically validated:

1. **SkillUI round-trips into a global skill.** `skillui --url stripe.com` produced a skill folder that auto-registered in the available-skills list, then was invoked by art-director during the audit pass.
2. **Pencil MCP reaches sub-agents** when each `mcp__pencil__*` tool is enumerated in the agent frontmatter (no wildcard supported), and after a Claude Code restart.
3. **Pencil CLI Agent Mode persists `.pen` to disk** via `--out`, which the MCP path cannot. Single shell call also exports screenshots via `--export`. This is the documented canonical path per Pencil docs and is what designer.md uses by default.
4. **Reviewer catches lint-spirit violations.** Slice 06's `style={{ transitionTimingFunction: ... }}` was flagged as a Tailwind-only-rule breach despite the engineer's self-justification; the Tailwind v4 native `ease-out-quart` utility fixed it cleanly.
5. **The design phase routes correctly** through art-director → designer → audit → engineer when `DESIGN_PHASE=enabled`, and skips to engineer directly when disabled.
6. **`harness graduate` flips poc → full** in one command, surfacing devops + security to the orchestrator. Devops then created the private GitHub repo and opened PR #1 against `main` without manual intervention.

---

## Known gaps and nice-to-haves

### Caveats to remember

- **Agent definitions are cached at session start.** Editing `~/.claude/agents/<name>.md` requires a Claude Code restart for the cached agent to refresh. Workaround in the meantime: pass explicit overrides in the dispatch prompt.
- **Pencil MCP has no save tool.** `open_document` + `batch_design` modify the desktop app's in-memory copy only. The CLI Agent Mode path (which this harness uses by default) sidesteps this.
- **The `harness mode` / `design` / `graduate` commands run via `sed -i`.** Edits to `.claude/harness.config.sh` are minimal and idempotent. They don't run `harness ralph` or anything that consumes credits.

### Nice-to-haves not yet built

- **Per-slice PR raising in `--parallel`.** Today a successful parallel run merges into the invoking branch locally. A `--raise-prs` flag would push each `ralph/parallel-*` branch and `gh pr create` against the base instead. Useful when slices should reviewed/merged independently rather than piled into one feature PR.
- **`harness sync`** — diff `~/.claude/harness/` against PEH `origin/main`, offer to branch + commit + PR uncommitted local edits. The maintainer install pattern makes this trivial once you remember to do it; a subcommand would prevent drift like this README's.
- **`harness mockup <slice-id>`** — one-shot dispatch of just the design phase against a specific issue (skip the rest). Useful for iterating on a mockup without re-running engineering.
- **`harness graduate` should commit the config edit.** Currently it leaves the change uncommitted. Could optionally take a `--commit` flag.
- **Pencil `.pen` files don't open in app automatically when composed via CLI Agent Mode.** Designer.md was updated this session to run `open <path>.pen` as a step, but that's a manual hook; would be cleaner if Pencil CLI had a `--open` flag.
- **Reviewer's eval JSON is per-issue, not aggregated.** A `harness eval-report` command would summarise pass/concerns/fail rates across an issue set.
- **Security agent's deepsec cost gate is prompt-level, not config-level.** A `DEEPSEC_MAX_LOC` env var would let the user set an explicit budget.
- **No `harness deinit`.** Removing the harness from a project means hand-deleting files; a clean uninstall would be neat.
- **Multi-context monorepos.** `harness init` writes a single-context layout (CONTEXT.md at root). Multi-context support exists in the docs/agents/domain.md template but isn't bootstrapped by init.

### Docs still to write

Now that this is its own repo, the natural next docs are:

- `docs/creating-a-skill.md` — how to add a new skill via `_install-skill.sh`
- `docs/creating-an-agent.md` — how to add a new specialist (frontmatter, tool surface, dispatch rules)
- `docs/extending-the-loop.md` — how to add new phases to the orchestrator routing

These are deferred until another two or three projects have run through the harness and the shape has stabilised further.

## Install prerequisites

The harness dispatches skills and tools it does not vendor (they have their own upstreams). After `./install.sh`, install:

**Skills** (via `~/.claude/skills/_install-skill.sh <github-tree-url>` or `npx skills add`):

- Vercel: `react-best-practices`, `composition-patterns`
- Matt Pocock: `grill-with-docs`, `to-prd`, `to-issues`, `triage`, `tdd`, `diagnose`
- Impeccable: `npx skills add pbakaus/impeccable`
- Anthropic `frontend-design` (bundled with Claude Code in most installs)

**Design tooling** (only needed if you use the design phase):

```bash
npm install -g @pencil.dev/cli   &&   pencil login
npm install -g skillui
```

**Security tooling** (only needed in `full` mode for the security agent):

```bash
# deepsec is invoked on-demand via npx by the security agent; no global install needed
```
