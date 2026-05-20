#!/usr/bin/env bash
# harness — entry point for the engineering harness
#
# Subcommands:
#   harness init                Bootstrap current project
#   harness ralph [N]           Run autonomous loop, N iterations (default 10)
#   harness ralph --once        Single interactive iteration
#   harness ralph --target ID   Target a specific issue
#   harness status              Show backlog summary
#   harness help                Show this message
#
# Per-project config lives at .claude/harness.config.sh
# Issues live under .scratch/<feature-slug>/issues/*.md

set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HARNESS_DIR

usage() {
  cat <<EOF
harness — engineering harness for AI-driven development

Usage:
  harness init                  Bootstrap current project (.scratch/, .claude/harness.config.sh)
  harness ralph [N]             Run autonomous loop for N iterations (default 10)
  harness ralph --once          Single interactive iteration
  harness ralph --target ID     Target a specific issue by id (filename stem)
  harness status                Show backlog: ready, blocked, done counts

Mode flags (per-project, edits .claude/harness.config.sh):
  harness mode <poc|full>       Set HARNESS_MODE (full adds devops + security)
  harness design <on|off>       Set DESIGN_PHASE (on adds art-director + designer)
  harness graduate              Shortcut: mode=full + design=on (ready-for-prod)

  harness help                  This message

Files:
  Global scripts:               $HARNESS_DIR
  Per-project config:           .claude/harness.config.sh
  Issues:                       .scratch/<feature>/issues/*.md
EOF
}

cmd="${1:-help}"
[[ $# -gt 0 ]] && shift

case "$cmd" in
  init)            exec "$HARNESS_DIR/harness-init.sh" "$@" ;;
  ralph)           exec "$HARNESS_DIR/ralph.sh" "$@" ;;
  status)          exec "$HARNESS_DIR/harness-status.sh" "$@" ;;
  mode)            exec "$HARNESS_DIR/harness-toggle.sh" mode "$@" ;;
  design)          exec "$HARNESS_DIR/harness-toggle.sh" design "$@" ;;
  graduate)        exec "$HARNESS_DIR/harness-toggle.sh" graduate "$@" ;;
  help|--help|-h)  usage ;;
  *)
    echo "Unknown command: $cmd" >&2
    echo >&2
    usage >&2
    exit 1
    ;;
esac
