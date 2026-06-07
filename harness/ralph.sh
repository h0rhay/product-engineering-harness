#!/usr/bin/env bash
# ralph — autonomous coding loop.
# Reads .scratch/*/issues/*.md, picks next ready-for-agent issue,
# spawns claude with binding context, runs verification, marks done, commits.

set -euo pipefail

HARNESS_DIR="${HARNESS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
PROJECT_DIR="$(pwd)"
CONFIG_FILE="${PROJECT_DIR}/.claude/harness.config.sh"

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
MAX_ITER=10
TARGET_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --once)         MAX_ITER=1; shift ;;
    --target)       TARGET_ID="${2:-}"; shift 2 ;;
    -h|--help)      echo "Usage: harness ralph [N] [--once] [--target ID]"; exit 0 ;;
    [0-9]*)         MAX_ITER="$1"; shift ;;
    *)              echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Load project config
# ---------------------------------------------------------------------------
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "No harness config at $CONFIG_FILE" >&2
  echo "Run 'harness init' in the project root first." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$CONFIG_FILE"

PROJECT_NAME="${PROJECT_NAME:-$(basename "$PROJECT_DIR")}"
COMMIT_PREFIX="${COMMIT_PREFIX:-feat(ralph)}"
ISSUES_GLOB="${ISSUES_GLOB:-.scratch/*/issues/*.md}"
QUALITY_CHECKS=("${QUALITY_CHECKS[@]:-}")
CONTEXT_FILES=("${CONTEXT_FILES[@]:-}")
AGENTS_ENABLED=("${AGENTS_ENABLED[@]:-product-manager engineer tester}")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
get_field() {
  local file="$1" field="$2"
  grep -m1 -i "^${field}:" "$file" 2>/dev/null | sed -E "s/^[^:]+:[[:space:]]*//" || true
}

issue_status()      { get_field "$1" "Status"; }
issue_priority()    { get_field "$1" "Priority"; }
issue_blocked_by()  { get_field "$1" "Blocked-by"; }

issue_id() {
  local f="$1"
  basename "$f" .md | sed -E 's/^[0-9]+-//'
}

find_issue_by_id() {
  local id="$1"
  local f
  for f in $ISSUES_GLOB; do
    [[ -f "$f" ]] || continue
    if [[ "$(issue_id "$f")" == "$id" ]] || [[ "$(basename "$f" .md)" == "$id" ]]; then
      echo "$f"
      return 0
    fi
  done
  return 1
}

is_blocked() {
  local file="$1"
  local blockers
  blockers="$(issue_blocked_by "$file")"
  [[ -z "$blockers" ]] && return 1
  # Treat sentinel "no dependency" values as unblocked.
  case "$(echo "$blockers" | tr '[:upper:]' '[:lower:]' | xargs)" in
    none|-|n/a|na) return 1 ;;
  esac

  local b bfile
  IFS=',' read -ra BLOCKERS <<< "$blockers"
  for b in "${BLOCKERS[@]}"; do
    b="$(echo "$b" | xargs)"
    [[ -z "$b" ]] && continue
    case "$(echo "$b" | tr '[:upper:]' '[:lower:]')" in none|-|n/a|na) continue ;; esac
    bfile="$(find_issue_by_id "$b" || true)"
    if [[ -z "$bfile" ]] || [[ "$(issue_status "$bfile")" != "done" ]]; then
      return 0
    fi
  done
  return 1
}

pick_next_issue() {
  local target="$1"
  local f best_pri=999999 best_file=""
  local pri

  for f in $ISSUES_GLOB; do
    [[ -f "$f" ]] || continue
    [[ "$(issue_status "$f")" == "ready-for-agent" ]] || continue

    if [[ -n "$target" ]]; then
      if [[ "$(issue_id "$f")" == "$target" ]] || [[ "$(basename "$f" .md)" == "$target" ]]; then
        echo "$f"
        return 0
      fi
      continue
    fi

    is_blocked "$f" && continue

    pri="$(issue_priority "$f")"
    [[ -z "$pri" ]] && pri=999
    if (( pri < best_pri )); then
      best_pri=$pri
      best_file="$f"
    fi
  done

  [[ -n "$best_file" ]] && echo "$best_file"
}

mark_issue_done() {
  local file="$1"
  local summary="$2"
  if grep -qi "^Status:" "$file"; then
    sed -i.bak -E "s/^[Ss]tatus:.*$/Status: done/" "$file" && rm -f "${file}.bak"
  else
    # Insert Status line after the first heading
    sed -i.bak '1,/^#/{/^#/a\
Status: done
}' "$file" && rm -f "${file}.bak"
  fi
  cat >> "$file" <<EOF

## Completion
$(date '+%Y-%m-%d %H:%M:%S') — ${summary}
EOF
}

build_context_block() {
  local f
  for f in "${CONTEXT_FILES[@]}"; do
    [[ -z "$f" ]] && continue
    if [[ -f "$f" ]]; then
      echo
      echo "<<< $f >>>"
      cat "$f"
      echo "<<< end $f >>>"
    fi
  done
}

build_quality_block() {
  local c
  for c in "${QUALITY_CHECKS[@]}"; do
    [[ -n "$c" ]] && echo "   - $c"
  done
}

notify() {
  local title="$1" msg="$2" sound="${3:-Glass}"
  osascript -e "display notification \"$msg\" with title \"$title\" sound name \"$sound\"" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
echo "========================================"
echo "Harness Ralph"
echo "Project: $PROJECT_NAME"
echo "Iterations: $MAX_ITER"
[[ -n "$TARGET_ID" ]] && echo "Target: $TARGET_ID"
echo "Started: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================"

for ((i=1; i<=MAX_ITER; i++)); do
  echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Iteration $i of $MAX_ITER — $(date '+%H:%M:%S')"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  NEXT_ISSUE="$(pick_next_issue "$TARGET_ID" || true)"
  if [[ -z "$NEXT_ISSUE" ]]; then
    if [[ -n "$TARGET_ID" ]]; then
      echo "Target issue '$TARGET_ID' not found or not ready-for-agent."
    else
      echo "No ready-for-agent issues with all blockers resolved."
    fi
    notify "Ralph idle" "No work to pick up." "Tink"
    exit 0
  fi

  ISSUE_ID="$(issue_id "$NEXT_ISSUE")"
  echo "Picked: $NEXT_ISSUE"
  echo "ID: $ISSUE_ID"
  echo

  iteration_start=$(date +%s)
  OUTPUT_FILE="/tmp/ralph-output-$$.txt"
  : > "$OUTPUT_FILE"

  PROMPT="You are the ORCHESTRATOR for ${PROJECT_NAME}. You are not a worker; you delegate.

OUTPUT DISCIPLINE: Be terse. No preamble, no recap, no narration. Output only what's load-bearing: tool calls and a final summary. Treat every token as scarce.

YOUR TEAM (dispatch via the Agent tool, using subagent_type). Only the agents listed below as ENABLED may be dispatched on this project; agents not listed must NOT be invoked:

ENABLED on this project: ${AGENTS_ENABLED[*]}

Capabilities (only dispatch ones in the ENABLED list):
  • product-manager — clarifies scope and acceptance criteria when the issue is ambiguous.
  • art-director — owns visual taste decisions: aesthetic lineage, typography, palette, motion, anti-slop refusal list. Writes a direction brief to .scratch/<feature>/direction/<NN-slice>.md AND audits designer output afterward.
  • designer — executes the direction brief: runs skillui to distil reference sites, drives Pencil MCP to produce mockups, fetches 21st.dev examples via Firecrawl. Does NOT make taste decisions; if direction is missing or ambiguous it escalates back to you.
  • engineer — writes / edits React + TypeScript code. For visual slices, reads the approved mockup and the direction brief; implements faithfully.
  • tester — writes Vitest tests when the slice requires them.
  • devops — git hygiene, remote setup, branch/commit/PR conventions, deployment plumbing. Invoke when the slice is ready to be pushed or a release is imminent.
  • security — vulnerability scan (deepsec) + manual checklist. Invoke before any production deploy or when explicitly requested. Costs real money; never run deepsec scan without user confirmation.
  • reviewer — DO NOT call. The harness runs reviewer after you finish.

DELEGATION RULES:
  - You do NOT write code, tests, or design specs yourself. Delegate to the appropriate specialist.
  - You CAN read files, run shell, check status. You orchestrate; you don't implement.
  - DESIGN PHASE (only when BOTH art-director AND designer are ENABLED, AND the slice has a visual component):
      1. Dispatch art-director with issue + context. It writes a direction brief.
      2. Dispatch designer with issue + context + direction brief path. It produces mockup artefacts.
      3. Dispatch art-director AGAIN with the mockup paths. It runs the impeccable 'audit' sub-command and returns approve/revise/reject.
      4. If 'revise', re-dispatch designer with the revision note appended to the direction brief. Re-audit.
      5. If 'reject', stop and write RALPH_RESULT: blocked — <reason>.
      6. Only after 'approve' does the slice proceed to engineer.
    If art-director or designer is NOT enabled, skip the design phase entirely and dispatch engineer directly.
  - For a code-only slice: engineer → tester (if tests in scope).
  - Pass the issue file path and BINDING CONTEXT file paths to every delegated agent. They read; you don't have to copy.

BINDING CONTEXT (file paths; every delegated agent must read and comply):
$(for f in "${CONTEXT_FILES[@]}"; do [[ -n "$f" && -f "$f" ]] && echo "  - $f"; done)

ISSUE TO IMPLEMENT (file: ${NEXT_ISSUE}):
$(cat "$NEXT_ISSUE")

WORKFLOW:
1. Read the issue and BINDING CONTEXT files to understand scope.
2. Determine whether this slice has a visual component (new screen, layout, typography, palette, or motion change).
3. Delegate as needed:
   a. If the slice is ambiguous, dispatch product-manager.
   b. If the slice has a visual component AND both art-director and designer are ENABLED: run the DESIGN PHASE in DELEGATION RULES above. The approved mockup path and direction brief path then go to engineer.
   c. Dispatch engineer with issue + context (+ approved direction + mockup paths if a design phase ran).
   d. Dispatch tester if the slice adds tests (check docs/rules.md for test scope).
4. After each delegation, verify the agent's output: read the changed files, sanity-check against the brief.
5. SIMPLIFY PASS (you do this, not a specialist): review the final diff. If you see dead code, redundant abstractions, or comments restating code, dispatch engineer to clean up. Do NOT over-engineer.
6. Do NOT run quality checks yourself — the harness runs them authoritatively after you finish.
7. Emit a final summary: RALPH_RESULT: success — <one-line summary> (or failed/blocked with reason).
8. Do NOT modify the issue file. Do NOT commit. The harness handles both.

CRITICAL: every agent must respect the BINDING CONTEXT. If a delegated agent's output violates a rule, dispatch reviewer-style audit yourself (read + grep) or dispatch engineer to fix. If the rule fundamentally can't be satisfied, write: RALPH_RESULT: blocked — <reason>."

  set +e
  claude --dangerously-skip-permissions --verbose -p "$PROMPT" \
    --model "${ORCHESTRATOR_MODEL:-opus}" \
    --output-format stream-json 2>/dev/null \
    | bash "$HARNESS_DIR/ralph-progress.sh" "$OUTPUT_FILE"
  claude_exit=${PIPESTATUS[0]}
  set -e

  elapsed=$(( $(date +%s) - iteration_start ))

  if [[ $claude_exit -ne 0 ]]; then
    notify "Ralph CRASHED" "claude exited $claude_exit on iteration $i" "Basso"
    echo "claude exited $claude_exit"
    tail -50 "$OUTPUT_FILE" 2>/dev/null || true
    exit 1
  fi

  # ----- Authoritative verification: harness runs checks itself -----
  echo
  echo "── Verifying quality gates ──"
  all_pass=1
  failure_log=""
  for cmd in "${QUALITY_CHECKS[@]}"; do
    [[ -z "$cmd" ]] && continue
    printf "  %-40s " "$cmd"
    if eval "$cmd" >/tmp/ralph-qc-$$.log 2>&1; then
      echo "✓"
    else
      echo "✗"
      failure_log="$failure_log\n--- $cmd ---\n$(tail -30 /tmp/ralph-qc-$$.log)\n"
      all_pass=0
      break
    fi
  done
  rm -f /tmp/ralph-qc-$$.log

  if [[ $all_pass -eq 1 ]]; then
    summary="${ISSUE_ID} verified clean"
    # Try to pull a nicer summary line from the agent's output if present
    if [[ -f "$OUTPUT_FILE" ]]; then
      hint="$(grep -m1 -E "^RALPH_RESULT: success" "$OUTPUT_FILE" 2>/dev/null | sed -E 's/^RALPH_RESULT:[[:space:]]*success[[:space:]]*—?[[:space:]]*//' || true)"
      [[ -n "$hint" ]] && summary="$hint"
    fi
    echo
    echo "✓ Success: $summary"
    mark_issue_done "$NEXT_ISSUE" "$summary"
    if command -v git >/dev/null 2>&1 && git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
      git -C "$PROJECT_DIR" add -A
      git -C "$PROJECT_DIR" commit -m "$COMMIT_PREFIX: $ISSUE_ID — $summary" >/dev/null 2>&1 || echo "  (nothing to commit)"
    fi
    # Eval stage: run reviewer agent against the just-committed diff
    if [[ -x "$HARNESS_DIR/eval-stage.sh" ]]; then
      echo
      echo "── Eval (reviewer agent) ──"
      "$HARNESS_DIR/eval-stage.sh" "$NEXT_ISSUE" HEAD || echo "  (eval failed; iteration still counts as success)"
    fi
    notify "Ralph ✓" "$ISSUE_ID — $summary" "Glass"
  else
    echo
    echo "✗ Quality gate failed."
    echo -e "$failure_log"
    notify "Ralph failed" "$ISSUE_ID — quality gate failed" "Basso"
    exit 1
  fi

  echo
  echo "  Duration: ${elapsed}s"
  [[ $i -lt $MAX_ITER ]] && sleep 3
done

echo
echo "========================================"
echo "Ralph finished $MAX_ITER iterations."
echo "$(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================"
