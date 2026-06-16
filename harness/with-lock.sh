#!/usr/bin/env bash
# Portable mutex: acquire a directory-lock, run a command, release on exit.
# Usage: with-lock.sh <lock-dir> <cmd> [args...]
# Works on macOS (no flock) via atomic mkdir.
set -euo pipefail
LOCK="$1"; shift
while ! mkdir "$LOCK" 2>/dev/null; do sleep 1; done
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT
set +e
"$@"
status=$?
set -e
exit "$status"
