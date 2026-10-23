#!/usr/bin/env bash
# harness-match — arm and configure parity-match mode for the current project.
#
# Subcommands:
#   harness match init                   Set HARNESS_MODE=parity-match in the project's config.
#   harness match target <url>           Set PARITY_TARGET_URL (the canonical reference site to match).
#   harness match source <url>           Set PARITY_SOURCE_URL (our build — preview/staging/localhost).
#   harness match status                 Show current parity-match config.
#
# parity-match mode adds a mandatory live-audit step at the start of every
# ralph iteration: the orchestrator opens PARITY_TARGET_URL{issue route} in
# Chrome MCP, extracts the actual CSS rules (selector + declarations with
# their var(--token) references) for each element in the issue's acceptance
# criteria, and writes them to .scratch/<issue>/live-audit.md. The engineer
# may not change a styled element without an entry in that file.
#
# Codifies the 2026-06-13 lesson: parity work that infers from class-maps,
# screenshots, or getComputedStyle drifts. The reliable signal is the live
# CSS rule itself. See ~/.claude/harness/LESSONS.md.

set -euo pipefail

CONFIG=".claude/harness.config.sh"

if [[ ! -f "$CONFIG" ]]; then
  echo "no harness config at $CONFIG (run 'harness init' first)" >&2
  exit 1
fi

sed_inplace() {
  if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# Set or append a `KEY="VALUE"` line in the config (idempotent).
set_kv() {
  local key="$1" value="$2"
  if grep -qE "^${key}=" "$CONFIG"; then
    sed_inplace -E "s|^${key}=\".*\"|${key}=\"${value}\"|" "$CONFIG"
  else
    printf '\n%s="%s"\n' "$key" "$value" >> "$CONFIG"
  fi
}

show_state() {
  # shellcheck disable=SC1090
  source "$CONFIG"
  echo
  echo "  HARNESS_MODE         ${HARNESS_MODE:-unset}"
  echo "  PARITY_TARGET_URL    ${PARITY_TARGET_URL:-unset}"
  echo "  PARITY_SOURCE_URL    ${PARITY_SOURCE_URL:-unset}"
  echo
  if [[ "${HARNESS_MODE:-}" == "parity-match" && -z "${PARITY_TARGET_URL:-}" ]]; then
    echo "  ⚠ parity-match armed but no target URL set."
    echo "    Run: harness match target <url>"
    echo
  fi
}

action="${1:-status}"
arg="${2:-}"

case "$action" in
  init)
    set_kv "HARNESS_MODE" "parity-match"
    # Seed empty URL vars so users see them in the config.
    grep -qE '^PARITY_TARGET_URL=' "$CONFIG" || set_kv "PARITY_TARGET_URL" ""
    grep -qE '^PARITY_SOURCE_URL=' "$CONFIG" || set_kv "PARITY_SOURCE_URL" ""
    # Verify Chrome MCP is configured; warn (don't fail) if absent.
    if command -v claude >/dev/null 2>&1; then
      if ! claude mcp list 2>/dev/null | grep -qi "claude-in-chrome\|chrome"; then
        echo "  ⚠ Chrome MCP not detected in 'claude mcp list'."
        echo "    Install: see https://code.claude.com/docs/en/chrome"
        echo
      fi
    fi
    # Append a "Live parity protocol" stub to docs/rules.md if missing.
    if [[ -f docs/rules.md ]] && ! grep -q "Live parity protocol" docs/rules.md; then
      cat >> docs/rules.md <<'EOF'

## Live parity protocol (BINDING)

This project is in parity-match mode. For every visual change:

1. Open PARITY_TARGET_URL{route} in Chrome MCP.
2. Inspect each element in the issue's acceptance criteria. Read the actual
   CSS rule text — selector + declarations including the `var(--token)`
   references. Don't rely on `getComputedStyle` resolved values; they
   reflect cascade after inheritance and hide which token was intended.
3. Write the extracted rules to `.scratch/<issue>/live-audit.md`.
4. Every code change must cite a rule from that file. No backing rule, no
   change. The reviewer rejects diff hunks that don't map to the audit.

Rationale: parity work that infers from class-maps, screenshots, or
resolved pixel values drifts. The live CSS rule text is the only signal
that survives the cascade and the design-token indirection. See
`~/.claude/harness/LESSONS.md` (2026-06-13).
EOF
      echo "  ✓ Appended 'Live parity protocol' to docs/rules.md"
    fi
    echo "  ✓ parity-match mode armed."
    show_state
    ;;

  target)
    [[ -n "$arg" ]] || { echo "usage: harness match target <url>" >&2; exit 1; }
    set_kv "PARITY_TARGET_URL" "$arg"
    echo "  ✓ PARITY_TARGET_URL set"
    show_state
    ;;

  source)
    [[ -n "$arg" ]] || { echo "usage: harness match source <url>" >&2; exit 1; }
    set_kv "PARITY_SOURCE_URL" "$arg"
    echo "  ✓ PARITY_SOURCE_URL set"
    show_state
    ;;

  status)
    show_state
    ;;

  *)
    cat >&2 <<EOF
usage:
  harness match init                    Arm parity-match mode
  harness match target <url>            Set canonical reference URL
  harness match source <url>            Set our build URL (preview/staging)
  harness match status                  Show current config
EOF
    exit 1
    ;;
esac
