#!/usr/bin/env bash
# harness watch — terse heartbeat for background ralph runs.
# Scans /tmp/ralph-*.log + project's .claude/worktrees/*/.ralph.log.
# One line per run. Detects silent death: process gone, log not
# ending with "Ralph finished".

set -uo pipefail

shopt -s nullglob
logs=(/tmp/ralph-*.log /tmp/harness-ralph-*.log)
# Also pick up parallel-mode worktree logs in the current project.
if [[ -d .claude/worktrees ]]; then
  logs+=(.claude/worktrees/*/.ralph.log)
fi
if [[ ${#logs[@]} -eq 0 ]]; then
  echo "no ralph logs in /tmp or .claude/worktrees"
  exit 0
fi

now=$(date '+%H:%M:%S')
for log in "${logs[@]}"; do
  # Worktree logs live at <wt>/.ralph.log — use parent dir name.
  if [[ "$(basename "$log")" == ".ralph.log" ]]; then
    name=$(basename "$(dirname "$log")")
  else
    name=$(basename "$log" .log)
  fi
  last=$(tail -1 "$log" 2>/dev/null | tr -d '\r')
  finished=0
  grep -q "^Ralph finished" "$log" 2>/dev/null && finished=1

  pid_count=$(pgrep -f "harness.*ralph" 2>/dev/null | wc -l | tr -d ' ')
  # Look for a recent stage marker
  stage=$(grep -oE "Iteration [0-9]+|engineer|tester|reviewer|product-manager|art-director|designer|Picked" "$log" 2>/dev/null | tail -1)
  stage=${stage:-init}

  if (( finished == 1 )); then
    summary=$(grep -m1 "verdict\|Duration" "$log" | tail -1)
    printf "[%s] %-28s · DONE · %s\n" "$now" "$name" "${summary:-clean}"
  elif (( pid_count == 0 )); then
    err=$(grep -iE "error|fail|fatal|ELIFECYCLE|not found" "$log" | tail -1 | cut -c1-120)
    printf "[%s] %-28s · DIED · %s\n" "$now" "$name" "${err:-unknown}"
  else
    age=$(( $(date +%s) - $(stat -f %m "$log" 2>/dev/null || stat -c %Y "$log") ))
    printf "[%s] %-28s · live %3ds · %s\n" "$now" "$name" "$age" "$stage"
  fi
done
