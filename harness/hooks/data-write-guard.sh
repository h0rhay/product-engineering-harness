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
  "storyblok-schema:scripts/storyblok/update-component-schema.ts:mapi.storyblok.com/v[0-9]+/spaces/[0-9]+/components:PUT|POST|DELETE"
  "strapi-content-type:scripts/strapi/update-content-type.ts:/admin/content-type-builder|/admin/content-types:PUT|POST|DELETE"
  "prismic-custom-type:scripts/prismic/update-custom-type.ts:customtypes\\.prismic\\.io:PUT|POST|DELETE"
  "sanity-schema:scripts/sanity/update-schema.ts:api\\.sanity\\.io/v[0-9]+/.+/schemas:PUT|POST|DELETE"
  "supabase-admin:scripts/supabase/alter-table.ts:supabase\\.co/(rest|pg|admin):PUT|POST|DELETE|PATCH"
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
    # Block all destructive ops outright. Helpers should use idempotent updates.
    printf '\n[data-write-guard] BLOCKED: %s is destructive. Use the project helper or surface intent to the human.\n' "$tool" >&2
    exit 2
    ;;
  mcp__*__execute_mutating)
    mcp_op="$(printf '%s' "$payload" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("tool_input",{}).get("parameters",{}).get("operation",""))' 2>/dev/null || true)"
    # Block known schema-shape mutations across CMSes.
    case "$mcp_op" in
      updateComponent|deleteComponent|createComponent|updateComponentGroup|deleteComponentGroup|\
      updateContentType|deleteContentType|createContentType|\
      updateCustomType|deleteCustomType|\
      updateSchema|deleteSchema)
        printf '\n[data-write-guard] BLOCKED: MCP %s is a schema-shape mutation.\n' "$mcp_op" >&2
        printf '[data-write-guard] Route schema edits through a project helper that does GET → merge → PUT.\n' >&2
        printf '[data-write-guard] If no helper exists yet, copy the appropriate template from:\n' >&2
        printf '  %s\n' "$HOME/.claude/harness/templates/" >&2
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

for rule in "${RULES[@]}"; do
  IFS=':' read -r label helper hostpat methods <<<"$rule"
  # Does the command hit this rule's hostname/pattern?
  if printf '%s' "$cmd" | grep -Eq "$hostpat"; then
    # Does it use a destructive method?
    if printf '%s' "$cmd" | grep -Eq -- "-X\\s*($methods)|--request\\s*($methods)|method:\\s*['\"]($methods)['\"]"; then
      # Is the project helper being invoked?
      if printf '%s' "$cmd" | grep -qF "$helper"; then
        continue
      fi
      printf '\n[data-write-guard] BLOCKED [%s]: direct destructive write to %s.\n' "$label" "$hostpat" >&2
      printf '[data-write-guard] Use the project helper (GET → embellish → PUT):\n' >&2
      printf '  %s\n' "$helper" >&2
      printf '[data-write-guard] If the helper does not exist yet, scaffold it from:\n' >&2
      printf '  %s\n' "$HOME/.claude/harness/templates/" >&2
      exit 2
    fi
  fi
done

# Also guard ad-hoc backfill/load scripts that bypass helpers entirely.
if printf '%s' "$cmd" | grep -Eq '(^|/| )(scripts|tools|bin)/(backfill|load|seed|migrate)[^[:space:]]*\.(ts|js|mjs|py|sh)'; then
  if ! printf '%s' "$cmd" | grep -qE 'scripts/(storyblok|strapi|prismic|sanity|supabase|convex)/'; then
    if [[ "${DATA_WRITE_ALLOW_ADHOC:-0}" != "1" ]]; then
      printf '\n[data-write-guard] BLOCKED: ad-hoc backfill/load script.\n' >&2
      printf '[data-write-guard] Route writes through a system-specific helper under scripts/<system>/.\n' >&2
      printf '[data-write-guard] If this script is content-only and safe, set DATA_WRITE_ALLOW_ADHOC=1 in the call.\n' >&2
      exit 2
    fi
  fi
fi

exit 0
