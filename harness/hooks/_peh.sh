#!/usr/bin/env bash
# Shared output library for product-engineering-harness hooks.
#
# Every harness hook should source this and call peh_block() to emit a
# block message. The consistent [[PEH]] banner makes it instantly clear
# that the block came from the harness — not from Claude, the platform,
# or generic system noise.
#
# Usage:
#   # Source it (handles both installed and in-repo paths):
#   _peh_lib="${PEH_LIB:-$HOME/.claude/harness/hooks/_peh.sh}"
#   [[ -r "$_peh_lib" ]] || _peh_lib="$(dirname "$0")/_peh.sh"
#   # shellcheck source=/dev/null
#   source "$_peh_lib"
#
#   peh_block "<hook-name>" "<headline>" "<why>" "<fix>" "<override-hint>"
#   exit 2

peh_block() {
  # $1 hook-name  $2 headline  $3 why  $4 fix  $5 override-hint
  printf '\n══ [[PEH]] %s ═══════════════════════════════════════════════════════\n' "$1" >&2
  printf '   This block is from the product engineering harness.\n' >&2
  printf '   BLOCKED: %s\n' "$2" >&2
  [[ -n "${3:-}" ]] && printf '   Why:      %s\n' "$3" >&2
  [[ -n "${4:-}" ]] && printf '   Fix:      %s\n' "$4" >&2
  [[ -n "${5:-}" ]] && printf '   Override: %s\n' "$5" >&2
  printf '════════════════════════════════════════════════════════════════════════\n\n' >&2
}
