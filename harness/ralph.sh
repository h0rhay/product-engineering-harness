#!/usr/bin/env bash
# ralph — autonomous coding loop.
# Reads .scratch/*/issues/*.md, picks next ready-for-agent issue,
# spawns claude with binding context, runs verification, marks done, commits.

set -euo pipefail

# CI=true tells pnpm to skip the interactive "remove modules dir?" prompt
# that aborts in non-TTY contexts (parallel worktrees, CI, background runs).
# Safe in all contexts — ralph never asks the user before this point.
export CI=true

HARNESS_DIR="${HARNESS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
PROJECT_DIR="$(pwd)"
CONFIG_FILE="${PROJECT_DIR}/.claude/harness.config.sh"

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
MAX_ITER=10
TARGET_ID=""
PARALLEL=0
PARALLEL_MAX="${RALPH_PARALLEL_MAX:-4}"
SCOPE_GLOB=""
MERGE_READY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --once)         MAX_ITER=1; shift ;;
    --target)       TARGET_ID="${2:-}"; shift 2 ;;
    --parallel)     PARALLEL=1; shift ;;
    --scope)        SCOPE_GLOB="${2:-}"; shift 2 ;;
    --merge-ready)  MERGE_READY=1; shift ;;
    -h|--help)      echo "Usage: harness ralph [N] [--once] [--target ID] [--parallel] [--scope GLOB] [--merge-ready]"; exit 0 ;;
    [0-9]*)         MAX_ITER="$1"; shift ;;
    *)              echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if (( MERGE_READY )); then
  echo "Sweeping ralph/parallel-* branches with passing issues..."
  CURRENT="$(git rev-parse --abbrev-ref HEAD)"
  MERGED=0
  SKIPPED=0
  for br in $(git for-each-ref --format='%(refname:short)' refs/heads/ralph/parallel-*); do
    # Look up the issue id from branch name: ralph/parallel-<id>-<ts>
    bn="${br#ralph/parallel-}"
    id="${bn%-*}"
    issue_file=""
    for f in issues/*/*.md .scratch/*/issues/*.md; do
      [[ -f "$f" ]] || continue
      if [[ "$(basename "$f" .md | sed -E 's/^[0-9]+-//')" == "$id" ]]; then
        issue_file="$f"
        break
      fi
    done
    status=""
    [[ -n "$issue_file" ]] && status="$(grep -m1 -i '^Status:' "$issue_file" | sed 's/^[^:]*:[[:space:]]*//')"
    if [[ "$status" == "done" ]]; then
      echo "  merging $br..."
      if git merge --no-ff -m "ralph(parallel): merge $id" "$br" >/dev/null 2>&1; then
        ((MERGED++))
      else
        echo "  ✗ merge conflict on $br — left for manual resolution"
      fi
    else
      echo "  skip $br (status: ${status:-unknown})"
      ((SKIPPED++))
    fi
  done
  echo "Merged: $MERGED | Skipped: $SKIPPED"
  exit 0
fi

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
# Pre-flight: in a git worktree, link .env and node_modules from the primary
# repo if missing. Fail-fast on missing target id BEFORE any build runs.
# ---------------------------------------------------------------------------
preflight() {
  local git_dir common_dir primary
  if git_dir=$(git rev-parse --git-dir 2>/dev/null); then
    common_dir=$(git rev-parse --git-common-dir 2>/dev/null)
    if [[ -n "$common_dir" && "$git_dir" != "$common_dir" ]]; then
      primary=$(cd "$common_dir/.." && pwd)
      if [[ -f "$primary/.env" && ! -e "$PROJECT_DIR/.env" ]]; then
        ln -s "$primary/.env" "$PROJECT_DIR/.env"
        echo "preflight: linked .env from $primary"
      fi
      # node_modules: real install per worktree, serialized via flock so
      # parallel worktrees don't race on pnpm's global content store.
      # The lock file lives at the primary repo so all worktrees share it.
      if [[ ! -d "$PROJECT_DIR/node_modules/.bin" ]] && [[ -f "$PROJECT_DIR/package.json" ]]; then
        echo "preflight: pnpm install (waiting for install lock)"
        (
          cd "$PROJECT_DIR"
          exec 9>"$primary/.pnpm-install.lock"
          flock 9
          pnpm install --prefer-offline >/dev/null 2>&1 \
            || echo "preflight: pnpm install failed (will surface in quality gates)"
        )
      fi
    fi
  fi
  if [[ -n "$TARGET_ID" ]]; then
    if ! pick_next_issue "$TARGET_ID" >/dev/null; then
      echo "preflight FAIL: target '$TARGET_ID' not found or not ready-for-agent." >&2
      exit 2
    fi
  fi
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

preflight

# ---------------------------------------------------------------------------
# Parallel mode: fan out all unblocked ready issues into worktrees, run one
# `harness ralph --target X --once` per worktree, then merge done branches.
# ponytail: shells out to this same script; no model picker / no inner loops.
# ---------------------------------------------------------------------------
if (( PARALLEL )); then
  echo "Parallel mode: cap $PARALLEL_MAX concurrent"
  [[ -n "$SCOPE_GLOB" ]] && echo "Scope: $SCOPE_GLOB"
  SCAN_GLOB="${SCOPE_GLOB:-$ISSUES_GLOB}"
  TARGETS=()
  for f in $SCAN_GLOB; do
    [[ -f "$f" ]] || continue
    [[ "$(issue_status "$f")" == "ready-for-agent" ]] || continue
    is_blocked "$f" && continue
    TARGETS+=("$(issue_id "$f")")
  done
  if (( ${#TARGETS[@]} == 0 )); then
    echo "No ready unblocked issues in scope. Nothing to do."
    exit 0
  fi
  echo "Targets (${#TARGETS[@]}): ${TARGETS[*]}"
  ORIG_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
  WT_ROOT="$PROJECT_DIR/.claude/worktrees"
  mkdir -p "$WT_ROOT"
  TS="$(date +%s)"
  # macOS bash 3.2: parallel indexed arrays instead of associative.
  P_PIDS=()
  P_TARGETS=()
  P_BRANCHES=()
  P_WTS=()

  spawn_one() {
    local id="$1"
    local wt="$WT_ROOT/ralph-$id-$TS"
    local branch="ralph/parallel-$id-$TS"
    git worktree add -b "$branch" "$wt" "$ORIG_BRANCH" >/dev/null 2>&1 || {
      echo "  ✗ $id: worktree add failed" >&2
      return 1
    }
    (
      cd "$wt"
      "$HARNESS_DIR/harness.sh" ralph --target "$id" --once > "$wt/.ralph.log" 2>&1
    ) &
    local pid=$!
    P_PIDS+=("$pid")
    P_TARGETS+=("$id")
    P_BRANCHES+=("$branch")
    P_WTS+=("$wt")
    echo "  → $id [pid $pid]"
  }

  RUNNING=0
  i=0
  while (( i < ${#TARGETS[@]} )); do
    if (( RUNNING < PARALLEL_MAX )); then
      spawn_one "${TARGETS[$i]}" && ((RUNNING++))
      ((i++))
    else
      wait -n 2>/dev/null || wait
      ((RUNNING--))
    fi
  done
  wait

  echo
  echo "── Parallel results ──"
  echo
  MERGED=()
  FAILED=()
  for idx in "${!P_PIDS[@]}"; do
    target="${P_TARGETS[$idx]}"
    branch="${P_BRANCHES[$idx]}"
    wt="${P_WTS[$idx]}"
    if grep -q "Success: " "$wt/.ralph.log" 2>/dev/null; then
      if git merge --no-ff -m "ralph(parallel): merge $target" "$branch" >/dev/null 2>&1; then
        echo "  ✓ $target  → merged $branch"
        MERGED+=("$target")
        git branch -D "$branch" >/dev/null 2>&1 || true
      else
        echo "  ⚠ $target  → merge conflict on $branch (left for manual resolution)"
        FAILED+=("$target (merge conflict)")
      fi
    else
      echo "  ✗ $target  → log: $wt/.ralph.log"
      FAILED+=("$target")
    fi
  done

  echo
  echo "Merged: ${#MERGED[@]} | Failed: ${#FAILED[@]}"
  (( ${#FAILED[@]} == 0 ))
  exit $?
fi

# ---------------------------------------------------------------------------
# Resolve orchestrator model
# Prefer Fable 5; fall back to Opus 4.7 if Fable access is unavailable.
# Set ORCHESTRATOR_MODEL to override entirely.
# ---------------------------------------------------------------------------
if [[ -z "${ORCHESTRATOR_MODEL:-}" ]]; then
  PREFERRED_MODEL="claude-fable-5"
  FALLBACK_MODEL="claude-opus-4-7"
  echo -n "Probing $PREFERRED_MODEL access... "
  if claude --model "$PREFERRED_MODEL" -p "ok" >/dev/null 2>&1; then
    ORCHESTRATOR_MODEL="$PREFERRED_MODEL"
    echo "ok"
  else
    ORCHESTRATOR_MODEL="$FALLBACK_MODEL"
    echo "unavailable, using $FALLBACK_MODEL"
  fi
fi
echo "Orchestrator model: $ORCHESTRATOR_MODEL"
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

  # Parity-match protocol (only injected when mode=parity-match).
  PARITY_BLOCK=""
  if [[ "${HARNESS_MODE:-}" == "parity-match" ]]; then
    if [[ -z "${PARITY_TARGET_URL:-}" ]]; then
      echo "✗ HARNESS_MODE=parity-match but PARITY_TARGET_URL is unset." >&2
      echo "  Run: harness match target <url>" >&2
      exit 1
    fi
    ISSUE_DIR="$(dirname "$NEXT_ISSUE")"
    AUDIT_FILE="${ISSUE_DIR}/../live-audits/${ISSUE_ID}.md"
    mkdir -p "$(dirname "$AUDIT_FILE")"
    PARITY_BLOCK="

PARITY-MATCH PROTOCOL (BINDING — this is a clone/migration build):

  Target site (the canonical reference we are matching):  ${PARITY_TARGET_URL}
  Our build (for visual comparison only):                 ${PARITY_SOURCE_URL:-unset}
  Live-audit file (write here BEFORE dispatching engineer): ${AUDIT_FILE}

  Before ANY agent dispatch on this slice, you MUST run the live-audit step
  yourself:

  1. Identify the route for this issue (from the issue body or PRD). Open
     \${PARITY_TARGET_URL}\${route} via the Chrome MCP (mcp__claude-in-chrome__*).
  2. For every element named in the issue's acceptance criteria, extract the
     actual CSS rule text from live — selector + declarations including the
     var(--token) references. Use this probe pattern in javascript_tool:
       const el = document.querySelector('<selector>');
       const out = [];
       for (const s of document.styleSheets) {
         let rules; try { rules = s.cssRules } catch { continue }
         for (const r of rules || []) {
           if (r.selectorText && el.matches(r.selectorText)) out.push(r.cssText);
         }
       }
       out.join('\\n\\n');
     Do NOT rely on getComputedStyle — its resolved RGB values hide the
     intended design token after cascade inheritance.
  3. Write the extracted rules to ${AUDIT_FILE}, one section per element.
  4. Only after the audit file exists with real content do you dispatch the
     engineer. The engineer's prompt MUST include the path to this file as
     binding context, and the engineer MUST cite a rule from it for each
     code change.

  Skip this protocol → the iteration fails the eval stage. No exceptions.
"
  fi

  PROMPT="You are the ORCHESTRATOR for ${PROJECT_NAME}. You are not a worker; you delegate.${PARITY_BLOCK}

OUTPUT DISCIPLINE: Be terse. No preamble, no recap, no narration. Output only what's load-bearing: tool calls and a final summary. Treat every token as scarce.

YOUR TEAM (dispatch via the Agent tool, using subagent_type). Only the agents listed below as ENABLED may be dispatched on this project; agents not listed must NOT be invoked. Each agent's full capability is in its .md frontmatter description, surfaced by the Agent tool — do not re-describe them here.

ENABLED on this project: ${AGENTS_ENABLED[*]}

Two non-obvious constraints:
  - reviewer — DO NOT call. The harness runs reviewer after you finish.
  - security — never run a deepsec scan without explicit user confirmation; it costs real money.

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
    --model "$ORCHESTRATOR_MODEL" \
    --output-format stream-json 2>>"${OUTPUT_FILE}.err" \
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
