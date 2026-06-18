#!/usr/bin/env bash
# Generic data-write guard for the product engineering harness.
#
# Principle: EMBELLISH, DON'T REPLACE.
# Any upstream system that full-replaces on write (most REST CMSes, many
# admin APIs) will silently wipe fields if an agent sends a partial payload.
# The fix is GET → merge → PUT, enforced via a project-owned helper script.
#
# This guard blocks every direct write to a registered destructive endpoint
# UNLESS the command invokes the matching project helper.
#
# Activation (project side):
#   Add this hook to .claude/settings.json PreToolUse matchers:
#     "matcher": "Bash|mcp__*__execute_mutating|mcp__*__execute_destructive"
#     command: "$HOME/.claude/harness/hooks/data-write-guard.sh"
#   And declare your write surfaces in .claude/harness.config.sh:
#     DATA_WRITE_HELPERS=(
#       "<label>:<helper-path>:<hostname-or-pattern>:<method-pattern>"
#     )
#   E.g.
#     "storyblok-schema:scripts/storyblok/update-component-schema.ts:mapi.storyblok.com/v1/spaces/*/components:PUT|POST|DELETE"
#     "convex-schema:scripts/convex/update-schema.ts:*.convex.cloud/_system|*.convex.site:PUT|POST|DELETE"
#
# Built-in defaults guard the most common foot-guns even if a project
# forgets to declare them (Storyblok component schema, Strapi content-type
# builder, Prismic custom types, Sanity schema, Supabase admin, Convex
# schema/admin). Override per-project via DATA_WRITE_HELPERS or unset with
# DATA_WRITE_DEFAULTS_OFF=1.

set -euo pipefail

# ---------------------------------------------------------------------------
# Branded output. Every harness hook should use this banner so blocks are
# instantly recognisable as "your harness, not Claude/system noise".
# Args: $1 hook-name  $2 headline  $3 why  $4 fix  $5 override-hint
# ---------------------------------------------------------------------------
peh_block() {
  printf '\n══ [[PEH]] %s ═══════════════════════════════════════════════════════\n' "$1" >&2
  printf '   This block is from YOUR product engineering harness, not Claude.\n' >&2
  printf '   BLOCKED: %s\n' "$2" >&2
  [[ -n "${3:-}" ]] && printf '   Why:      %s\n' "$3" >&2
  [[ -n "${4:-}" ]] && printf '   Fix:      %s\n' "$4" >&2
  [[ -n "${5:-}" ]] && printf '   Override: %s\n' "$5" >&2
  printf '════════════════════════════════════════════════════════════════════════\n\n' >&2
}

payload="$(cat)"
tool="$(printf '%s' "$payload" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("tool_name",""))' 2>/dev/null || true)"

# ---------------------------------------------------------------------------
# Load project registry.
# ---------------------------------------------------------------------------
project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
cfg="$project_dir/.claude/harness.config.sh"
DATA_WRITE_HELPERS=()
DATA_WRITE_DEFAULTS_OFF="${DATA_WRITE_DEFAULTS_OFF:-0}"
if [[ -r "$cfg" ]]; then
  # shellcheck disable=SC1090
  source "$cfg" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Built-in defaults — common destructive endpoints across CMSes / data stores.
# Format: label : helper-suggestion : hostpattern : methodpattern
# helper-suggestion is informational only; the project is expected to provide
# its own helper at scripts/<system>/.
# ---------------------------------------------------------------------------
DEFAULTS=(
  # Schema-shape mutations — wipe component fields if PUT partially.
  "storyblok-schema:scripts/storyblok/update-component-schema.ts:mapi.storyblok.com/v[0-9]+/spaces/[0-9]+/components:PUT|POST|DELETE"
  # Story / row content mutations — wipe row fields if PUT partially. Same bug, different surface.
  "storyblok-story:scripts/storyblok/update-story-content.ts:mapi.storyblok.com/v[0-9]+/spaces/[0-9]+/stories:PUT|POST|DELETE"
  "strapi-content-type:scripts/strapi/update-content-type.ts:/admin/content-type-builder|/admin/content-types:PUT|POST|DELETE"
  "prismic-custom-type:scripts/prismic/update-custom-type.ts:customtypes\\.prismic\\.io:PUT|POST|DELETE"
  "sanity-schema:scripts/sanity/update-schema.ts:api\\.sanity\\.io/v[0-9]+/.+/schemas:PUT|POST|DELETE"
  "supabase-admin:scripts/supabase/alter-table.ts:supabase\\.(co|com)/(admin|pg-meta):PUT|POST|DELETE|PATCH"
  "convex-schema:scripts/convex/update-schema.ts:convex\\.(cloud|site)/(_system|admin|schema):PUT|POST|DELETE"
)

# Merge defaults under project entries (project entries win on duplicate label).
# bash 3.2-compatible (no associative arrays).
RULES=()
SEEN_LABELS=""
for entry in "${DATA_WRITE_HELPERS[@]:-}"; do
  [[ -z "$entry" ]] && continue
  label="${entry%%:*}"
  SEEN_LABELS="$SEEN_LABELS|$label|"
  RULES+=("$entry")
done
if [[ "$DATA_WRITE_DEFAULTS_OFF" != "1" ]]; then
  for entry in "${DEFAULTS[@]}"; do
    label="${entry%%:*}"
    case "$SEEN_LABELS" in
      *"|$label|"*) ;;
      *) RULES+=("$entry") ;;
    esac
  done
fi

# ---------------------------------------------------------------------------
# Extract command / MCP details from payload.
# ---------------------------------------------------------------------------
cmd=""
mcp_op=""
case "$tool" in
  Bash)
    cmd="$(printf '%s' "$payload" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null || true)"
    ;;
  mcp__*__execute_destructive)
    # Block destructive ops by default. Per-call override for the deliberate-delete case.
    if [[ "${DATA_WRITE_ALLOW_DESTRUCTIVE:-0}" == "1" ]]; then
      exit 0
    fi
    peh_block "data-write-guard" \
      "$tool is a destructive MCP op" \
      "Destructive ops can wipe state irreversibly." \
      "Confirm the intent with the human, then re-run." \
      "DATA_WRITE_ALLOW_DESTRUCTIVE=1 (per-call) if this is the deliberate delete that was asked for."
    exit 2
    ;;
  mcp__*__execute_mutating)
    mcp_op="$(printf '%s' "$payload" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("tool_input",{}).get("parameters",{}).get("operation",""))' 2>/dev/null || true)"
    case "$mcp_op" in
      # Creates intentionally NOT blocked — nothing to wipe. Updates and deletes only.
      updateComponent|deleteComponent|updateComponentGroup|deleteComponentGroup|\
      updateContentType|deleteContentType|\
      updateCustomType|deleteCustomType|\
      updateSchema|deleteSchema)
        peh_block "data-write-guard" \
          "MCP $mcp_op is a schema-shape mutation" \
          "Partial-payload writes wipe fields that aren't in the payload." \
          "Use the project's schema helper (GET → merge → PUT). Template: ~/.claude/harness/templates/update-component-schema.template.ts" \
          "(none — schema edits must go through a helper)"
        exit 2
        ;;
      updateStory|updateEntry|updateDocument|updateRecord)
        peh_block "data-write-guard" \
          "MCP $mcp_op is a row-content mutation" \
          "Partial-payload PUTs wipe sibling fields. Burned us 3× in 48h on Storyblok." \
          "Use the project's row helper (GET → merge → PUT). Template: ~/.claude/harness/templates/update-row-content.template.ts" \
          "(none — row writes must go through a helper)"
        exit 2
        ;;
    esac
    exit 0
    ;;
  *)
    exit 0
    ;;
esac

# ---------------------------------------------------------------------------
# Bash path: check the command against every rule.
# ---------------------------------------------------------------------------
[[ -z "$cmd" ]] && exit 0

RUNNERS='(tsx|ts-node|node|bun|deno|npx|pnpm|yarn|python3?|sh|bash)'
# -d/--data*/-T/--upload-file imply POST or PUT respectively — body-bearing curl
# without an explicit -X still mutates. Treat presence of any of these as a
# destructive method on a registered host.
BODY_FLAGS="(^|[[:space:]])(-d|--data|--data-raw|--data-binary|--data-urlencode|-T|--upload-file)([[:space:]]|=)"

for rule in "${RULES[@]}"; do
  IFS=':' read -r label helper hostpat methods <<<"$rule"
  # Does the command hit this rule's hostname/pattern?
  if printf '%s' "$cmd" | grep -Eq "$hostpat"; then
    # Does it use a destructive method (explicit) or body-bearing curl (implicit)?
    if printf '%s' "$cmd" | grep -Eq -- "-X[[:space:]]*($methods)|--request[[:space:]]*($methods)|method:[[:space:]]*['\"]($methods)['\"]|$BODY_FLAGS"; then
      # Is the project helper being invoked as an executable (not just mentioned)?
      helper_re="$(printf '%s' "$helper" | sed 's/[.[\*^$()+?{}|]/\\&/g')"
      if printf '%s' "$cmd" | grep -Eq "(^|[[:space:]&|;])$RUNNERS[[:space:]]+([^&|;]*[[:space:]])?${helper_re}([[:space:]&|;]|$)"; then
        continue
      fi
      peh_block "data-write-guard" \
        "direct destructive write to $label endpoint" \
        "Bash hit $hostpat with a mutating method. Partial payloads wipe fields." \
        "Run the helper: $helper (GET → merge → PUT). Templates: ~/.claude/harness/templates/" \
        "(none — invoke the helper, or add a new rule in DATA_WRITE_HELPERS)"
      exit 2
    fi
  fi
done

# Also guard ad-hoc backfill/load scripts that bypass helpers entirely.
if printf '%s' "$cmd" | grep -Eq '(^|/| )(scripts|tools|bin)/(backfill|load|seed|migrate)[^[:space:]]*\.(ts|js|mjs|py|sh)'; then
  if ! printf '%s' "$cmd" | grep -qE 'scripts/(storyblok|strapi|prismic|sanity|supabase|convex)/'; then
    if [[ "${DATA_WRITE_ALLOW_ADHOC:-0}" != "1" ]]; then
      peh_block "data-write-guard" \
        "ad-hoc backfill/load/seed/migrate script" \
        "Ad-hoc scripts bypass the GET → merge → PUT helper pattern." \
        "Move the logic into scripts/<system>/ alongside the system-specific helper." \
        "DATA_WRITE_ALLOW_ADHOC=1 (per-call) if this script is content-only and safe."
      exit 2
    fi
  fi
fi

exit 0
