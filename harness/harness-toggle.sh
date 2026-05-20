#!/usr/bin/env bash
# harness-toggle — flip per-project harness flags ergonomically.
#
# Subcommands (dispatched from harness.sh):
#   mode <poc|full>       Set HARNESS_MODE in .claude/harness.config.sh
#   design <on|off>       Set DESIGN_PHASE (on=enabled, off=disabled)
#   graduate              Shortcut: mode=full + design=on (ready for production)

set -euo pipefail

CONFIG=".claude/harness.config.sh"

if [[ ! -f "$CONFIG" ]]; then
  echo "no harness config at $CONFIG (run 'harness init' first)" >&2
  exit 1
fi

action="${1:-}"
arg="${2:-}"

# macOS sed needs -i ''. Use a portable helper.
sed_inplace() {
  if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

show_state() {
  # shellcheck disable=SC1090
  source "$CONFIG"
  echo
  echo "  HARNESS_MODE  $HARNESS_MODE"
  echo "  DESIGN_PHASE  $DESIGN_PHASE"
  echo "  AGENTS        ${AGENTS_ENABLED[*]}"
  echo
}

case "$action" in
  mode)
    case "$arg" in
      poc|full) ;;
      *) echo "usage: harness mode <poc|full>" >&2; exit 1 ;;
    esac
    sed_inplace -E "s/^HARNESS_MODE=\".*\"/HARNESS_MODE=\"$arg\"/" "$CONFIG"
    echo "✓ HARNESS_MODE set to $arg"
    show_state
    ;;

  design)
    case "$arg" in
      on|enable|enabled)   new="enabled" ;;
      off|disable|disabled) new="disabled" ;;
      *) echo "usage: harness design <on|off>" >&2; exit 1 ;;
    esac
    sed_inplace -E "s/^DESIGN_PHASE=\".*\"/DESIGN_PHASE=\"$new\"/" "$CONFIG"
    echo "✓ DESIGN_PHASE set to $new"
    show_state
    ;;

  graduate)
    sed_inplace -E 's/^HARNESS_MODE=".*"/HARNESS_MODE="full"/' "$CONFIG"
    sed_inplace -E 's/^DESIGN_PHASE=".*"/DESIGN_PHASE="enabled"/' "$CONFIG"
    echo "✓ Project graduated: HARNESS_MODE=full + DESIGN_PHASE=enabled"
    echo "  devops + security are now dispatchable; art-director + designer stay on."
    show_state
    ;;

  *)
    cat >&2 <<EOF
usage:
  harness mode <poc|full>       Set HARNESS_MODE
  harness design <on|off>       Set DESIGN_PHASE
  harness graduate              Shortcut for mode=full + design=on
EOF
    exit 1
    ;;
esac
