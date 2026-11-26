#!/usr/bin/env bash
# open-log-terminal: open a visible macOS Terminal window that follows a build log.
# Usage: open-log-terminal.sh <log-file> [title]
# George's rule: no build runs where he cannot watch it. Set HARNESS_NO_TERMINAL=1 to skip,
# HARNESS_TERMINAL_DRYRUN=1 to print the command instead of opening a window.

set -euo pipefail

log="${1:?log file required}"
title="${2:-harness build}"

[[ "${HARNESS_NO_TERMINAL:-}" == 1 ]] && exit 0
[[ "$(uname)" == Darwin ]] || exit 0

q() { printf '%q' "$1"; }
cmd="printf '\\e]0;%s\\a' $(q "$title"); tail -n +1 -F $(q "$log") | LC_ALL=C tr '\\r' '\\n'"

if [[ "${HARNESS_TERMINAL_DRYRUN:-}" == 1 ]]; then
  echo "$cmd"
  exit 0
fi

osascript - "$cmd" >/dev/null 2>&1 <<'APPLESCRIPT' || echo "harness: could not open a Terminal window for $log" >&2
on run argv
  tell application "Terminal"
    do script (item 1 of argv)
  end tell
end run
APPLESCRIPT
