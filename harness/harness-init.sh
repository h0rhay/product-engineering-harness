#!/usr/bin/env bash
# harness-init — bootstrap the current project for the harness.
#
# Creates everything /setup-matt-pocock-skills would have created, with our
# defaults baked in (local-markdown tracker, default triage labels, single-
# context domain layout). No follow-up steps in Claude required.
#
# Files created:
#   .claude/harness.config.sh           Ralph config (commands, context files)
#   .scratch/example/issues/01-*.md     Starter issue
#   CONTEXT.md                          Empty glossary stub
#   docs/agents/issue-tracker.md        Local-markdown tracker convention
#   docs/agents/triage-labels.md        Triage label mapping (Matt's defaults)
#   docs/agents/domain.md               Domain doc consumer rules
#
# Edits one of (in order of preference):
#   CLAUDE.md      → appends "## Agent skills" block if present
#   AGENTS.md      → same, if CLAUDE.md is absent
#   <creates CLAUDE.md> if neither exists

set -euo pipefail

PROJECT_DIR="$(pwd)"
PROJECT_NAME_DEFAULT="$(basename "$PROJECT_DIR")"

if [[ -f "${PROJECT_DIR}/.claude/harness.config.sh" ]]; then
  echo "harness config already exists at .claude/harness.config.sh"
  echo "Edit it directly or remove it before re-running 'harness init'."
  exit 1
fi

echo "Bootstrapping harness in: $PROJECT_DIR"
echo

# ---------------------------------------------------------------------------
# Detect package manager → default quality checks
# ---------------------------------------------------------------------------
if [[ -f "${PROJECT_DIR}/pnpm-lock.yaml" ]]; then
  TEST_CMDS_DEFAULT='  "pnpm lint"
  "pnpm test"
  "pnpm typecheck"'
elif [[ -f "${PROJECT_DIR}/package-lock.json" ]]; then
  TEST_CMDS_DEFAULT='  "npm run lint"
  "npm test"
  "npm run typecheck"'
elif [[ -f "${PROJECT_DIR}/yarn.lock" ]]; then
  TEST_CMDS_DEFAULT='  "yarn lint"
  "yarn test"
  "yarn typecheck"'
else
  TEST_CMDS_DEFAULT='  # "your-test-command-here"'
fi

mkdir -p "${PROJECT_DIR}/.claude"
mkdir -p "${PROJECT_DIR}/.scratch/example/issues"
mkdir -p "${PROJECT_DIR}/docs/agents"

# ---------------------------------------------------------------------------
# .claude/harness.config.sh
# ---------------------------------------------------------------------------
cat > "${PROJECT_DIR}/.claude/harness.config.sh" <<EOF
# Harness config for ${PROJECT_NAME_DEFAULT}
# Sourced by ~/.claude/harness/ralph.sh — edit values to taste.

PROJECT_NAME="${PROJECT_NAME_DEFAULT}"
COMMIT_PREFIX="feat(ralph)"

# Quality checks run after every Ralph iteration. All must pass for the issue
# to be marked done.
QUALITY_CHECKS=(
${TEST_CMDS_DEFAULT}
)

# Files loaded into every Ralph iteration as binding rules.
# Add design-system, code-patterns, naming docs, etc. as your project grows.
CONTEXT_FILES=(
  "CONTEXT.md"
  "docs/rules.md"
)

# Where to find issues. Matt Pocock's local-markdown convention.
ISSUES_GLOB=".scratch/*/issues/*.md"

# Specialist agents the orchestrator may dispatch. Two flags compose the set:
#
#   HARNESS_MODE
#     poc:  lean team for prototypes
#     full: adds devops + security for production-bound work
#
#   DESIGN_PHASE
#     enabled:  art-director + designer run before engineer for visual slices
#     disabled: skip straight to engineer (current behaviour for code-only slices)
#
# Reviewer always runs as the eval stage; not listed here.
HARNESS_MODE="poc"           # change to "full" when promoting beyond prototype
DESIGN_PHASE="disabled"      # change to "enabled" when slices have a visual component

AGENTS_ENABLED=("product-manager" "engineer" "tester")
case "\$HARNESS_MODE" in
  full) AGENTS_ENABLED+=("devops" "security") ;;
esac
case "\$DESIGN_PHASE" in
  enabled) AGENTS_ENABLED+=("art-director" "designer") ;;
esac
EOF

# ---------------------------------------------------------------------------
# CONTEXT.md (only if absent)
# ---------------------------------------------------------------------------
if [[ ! -f "${PROJECT_DIR}/CONTEXT.md" ]]; then
  cat > "${PROJECT_DIR}/CONTEXT.md" <<'EOF'
# Domain Glossary

This file is a glossary of the shared language used in this project. It is
populated lazily by /grill-with-docs as concepts get resolved. It is **not**
a spec, scratch pad, or implementation log.

## Terms

(none yet — run /grill-with-docs to start building this glossary)
EOF
fi

# ---------------------------------------------------------------------------
# docs/rules.md — binding rules re-injected every Ralph iteration (only if absent)
# ---------------------------------------------------------------------------
if [[ ! -f "${PROJECT_DIR}/docs/rules.md" ]]; then
  cat > "${PROJECT_DIR}/docs/rules.md" <<'EOF'
# Binding Rules

These rules are re-injected into every Ralph iteration. Agents must obey them
over their own defaults. Add project-specific rules (data access, naming,
dependencies) as the project grows.

## Layout — every-layout (binding)

All structure is composed from the `every-layout` primitives. This is the
structural substrate; the design phase's aesthetic (typography, palette, motion)
sits on top of it and does not replace it.

- Compose with Stack, Box, Center, Cluster, Sidebar, Switcher.
- Logical properties only (`margin-inline`, `padding-block`, `inline-size`),
  never physical (`margin-left`, `width`).
- Spacing and sizing from the modular scale (`--s-2` … `--s5`), not ad-hoc values.
- No `@media` for layout reconfiguration; rely on intrinsic responsiveness
  (flex-basis + flex-grow + min-inline-size).
- No `px` except `1px` borders.
- Constrain text to a measure (~60ch).

See the `every-layout` skill for the full pattern set and the per-primitive CSS.
EOF
fi

# ---------------------------------------------------------------------------
# docs/agents/issue-tracker.md (local-markdown convention)
# ---------------------------------------------------------------------------
cat > "${PROJECT_DIR}/docs/agents/issue-tracker.md" <<'EOF'
# Issue tracker: Local Markdown

Issues and PRDs for this repo live as markdown files in `.scratch/`.

## Conventions

- One feature per directory: `.scratch/<feature-slug>/`
- The PRD is `.scratch/<feature-slug>/PRD.md`
- Implementation issues are `.scratch/<feature-slug>/issues/<NN>-<slug>.md`, numbered from `01`
- Triage state is recorded as a `Status:` line near the top of each issue file (see `triage-labels.md`)
- Comments and conversation history append to the bottom of the file under a `## Comments` heading

## When a skill says "publish to the issue tracker"

Create a new file under `.scratch/<feature-slug>/` (creating the directory if needed).

## When a skill says "fetch the relevant ticket"

Read the file at the referenced path. The user will normally pass the path or the issue id directly.

## Ralph integration

The autonomous `harness ralph` loop reads `.scratch/*/issues/*.md`. It picks the next file with `Status: ready-for-agent` whose `Blocked-by:` entries are all `done`. Ralph marks completed issues `Status: done` and commits.

Other valid statuses (do not change without updating ralph.sh): `needs-triage`, `needs-info`, `ready-for-human`, `wontfix`.

Optional per-issue lines (besides `Status:`):

- `Priority: <number>` — lower runs first; default 999
- `Blocked-by: id1, id2` — comma-separated; Ralph waits until each is done
EOF

# ---------------------------------------------------------------------------
# docs/agents/triage-labels.md
# ---------------------------------------------------------------------------
cat > "${PROJECT_DIR}/docs/agents/triage-labels.md" <<'EOF'
# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the actual label strings used in this repo. We use the defaults verbatim.

| Canonical role     | Label in this repo  | Meaning                                  |
| ------------------ | ------------------- | ---------------------------------------- |
| `needs-triage`     | `needs-triage`      | Maintainer needs to evaluate this issue  |
| `needs-info`       | `needs-info`        | Waiting on reporter for more information |
| `ready-for-agent`  | `ready-for-agent`   | Fully specified, ready for an AFK agent  |
| `ready-for-human`  | `ready-for-human`   | Requires human implementation            |
| `wontfix`          | `wontfix`           | Will not be actioned                     |

Ralph adds one more terminal state used after autonomous completion:

| Canonical role     | Label in this repo  | Meaning                                  |
| ------------------ | ------------------- | ---------------------------------------- |
| `done`             | `done`              | Implemented, verified, committed         |

When a skill mentions a role, use the corresponding label string from these tables. Categories are `bug` or `enhancement`; apply one per issue alongside the state role.
EOF

# ---------------------------------------------------------------------------
# docs/agents/domain.md
# ---------------------------------------------------------------------------
cat > "${PROJECT_DIR}/docs/agents/domain.md" <<'EOF'
# Domain Docs

How the engineering skills should consume this repo's domain documentation.

## Before exploring, read these

- `CONTEXT.md` at the repo root
- `docs/adr/` — ADRs that touch the area you're working in

If any are absent, proceed silently. Don't flag their absence or suggest creating them upfront. `/grill-with-docs` creates them lazily as terms and decisions get resolved.

## File structure (single-context)

```
/
├── CONTEXT.md
├── docs/adr/
│   ├── 0001-...
│   └── 0002-...
└── src/
```

If this repo grows into a multi-context layout, create `CONTEXT-MAP.md` at the root and move per-context glossaries under each module.

## Use the glossary's vocabulary

When output names a domain concept (issue title, refactor proposal, hypothesis, test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary avoids.

If a concept isn't in the glossary yet, that's a signal — either you're inventing language the project doesn't use (reconsider), or there's a real gap (note it for `/grill-with-docs`).

## Flag ADR conflicts

If output contradicts an existing ADR, surface it rather than silently overriding:

> _Contradicts ADR-0007 (event-sourced orders) — but worth reopening because..._
EOF

# ---------------------------------------------------------------------------
# Append "## Agent skills" block to CLAUDE.md (or AGENTS.md), create if absent
# ---------------------------------------------------------------------------
AGENT_BLOCK='## Agent skills

### Issue tracker

Issues live as markdown files under `.scratch/<feature>/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Default mapping (canonical names = repo labels). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` at root, `docs/adr/` for ADRs. See `docs/agents/domain.md`.

### Harness

Autonomous loop runs via `harness ralph`. Per-project config at `.claude/harness.config.sh`. Global scripts at `~/.claude/harness/`.
'

TARGET_FILE=""
if [[ -f "${PROJECT_DIR}/CLAUDE.md" ]]; then
  TARGET_FILE="${PROJECT_DIR}/CLAUDE.md"
elif [[ -f "${PROJECT_DIR}/AGENTS.md" ]]; then
  TARGET_FILE="${PROJECT_DIR}/AGENTS.md"
else
  TARGET_FILE="${PROJECT_DIR}/CLAUDE.md"
  cat > "$TARGET_FILE" <<EOF
# ${PROJECT_NAME_DEFAULT}

(Project description goes here.)

EOF
fi

if grep -q "^## Agent skills" "$TARGET_FILE"; then
  echo "  $(basename "$TARGET_FILE") already has an Agent skills block — leaving it alone."
else
  printf '\n%s' "$AGENT_BLOCK" >> "$TARGET_FILE"
  echo "  Appended Agent skills block to $(basename "$TARGET_FILE")."
fi

# ---------------------------------------------------------------------------
# Starter example issue
# ---------------------------------------------------------------------------
cat > "${PROJECT_DIR}/.scratch/example/issues/01-hello-world.md" <<'EOF'
# 01 — Hello world (example)

Status: needs-triage
Priority: 99

## What to build

Starter issue created by `harness init`. Shows the file format. Move it to
`Status: ready-for-agent` to test Ralph, or delete it.

## Acceptance criteria

- [ ] Ralph completes one iteration against this file
- [ ] Issue file ends with `Status: done` and a `## Completion` block
EOF

# ---------------------------------------------------------------------------
# Gitignore hint
# ---------------------------------------------------------------------------
if [[ -f "${PROJECT_DIR}/.gitignore" ]] && ! grep -q "^\.scratch" "${PROJECT_DIR}/.gitignore"; then
  echo
  echo "Hint: consider whether .scratch/ should be in .gitignore."
fi

cat <<EOF

✓ Harness initialised.

Created / edited:
  .claude/harness.config.sh        ← edit CONTEXT_FILES + QUALITY_CHECKS to taste
  CONTEXT.md                       ← glossary (empty)
  docs/agents/issue-tracker.md
  docs/agents/triage-labels.md
  docs/agents/domain.md
  .scratch/example/issues/01-hello-world.md
  $(basename "$TARGET_FILE")        ← Agent skills block

Next steps (no follow-up Claude setup needed):
  1. Start designing:        open Claude Code, run /grill-with-docs
  2. Check backlog:          harness status
  3. Run autonomous loop:    harness ralph 10
EOF
