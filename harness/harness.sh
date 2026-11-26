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
# Issues live under issues/<feature-slug>/*.md

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
  harness watch                 Terse heartbeat: one line per in-flight or completed ralph run
  harness match <sub>           Parity-match mode (clone / migration / rebrand)

  harness help                  This message

Files:
  Global scripts:               $HARNESS_DIR
  Per-project config:           .claude/harness.config.sh
  Issues:                       issues/<feature>/*.md
EOF
}

cmd="${1:-help}"
[[ $# -gt 0 ]] && shift

case "$cmd" in
  init)            exec "$HARNESS_DIR/harness-init.sh" "$@" ;;
  ralph)
    # Every ralph run gets a visible Terminal window following its output (George, 26 Nov 2026).
    # Interactive runs already show output. Otherwise follow the file stdout points at, or
    # tee into .scratch/ralph-run.log when stdout is a pipe.
    if [[ ! -t 1 ]]; then
      log="$(lsof -a -p $$ -d 1 -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)"
      if [[ ! -f "$log" ]]; then
        mkdir -p "$PWD/.scratch"
        log="$PWD/.scratch/ralph-run.log"
        : > "$log"
        exec > >(tee -a "$log") 2>&1
      fi
      "$HARNESS_DIR/open-log-terminal.sh" "$log" "$(basename "$PWD") build (harness)" || true
    fi
    exec "$HARNESS_DIR/ralph.sh" "$@" ;;
  status)          exec "$HARNESS_DIR/harness-status.sh" "$@" ;;
  mode)            exec "$HARNESS_DIR/harness-toggle.sh" mode "$@" ;;
  design)          exec "$HARNESS_DIR/harness-toggle.sh" design "$@" ;;
  graduate)        exec "$HARNESS_DIR/harness-toggle.sh" graduate "$@" ;;
  watch)           exec "$HARNESS_DIR/harness-watch.sh" "$@" ;;
  match)           exec "$HARNESS_DIR/harness-match.sh" "$@" ;;
  help|--help|-h)  usage ;;
  *)
    echo "Unknown command: $cmd" >&2
    echo >&2
    usage >&2
    exit 1
    ;;
esac
