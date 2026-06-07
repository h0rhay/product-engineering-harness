#!/usr/bin/env bash
# harness-status — print backlog summary for the current project.
# Plain bash 3.2 compatible (no associative arrays).

set -euo pipefail

PROJECT_DIR="$(pwd)"
CONFIG_FILE="${PROJECT_DIR}/.claude/harness.config.sh"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "No harness config at $CONFIG_FILE" >&2
  echo "Run 'harness init' first." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$CONFIG_FILE"

ISSUES_GLOB="${ISSUES_GLOB:-.scratch/*/issues/*.md}"

c_ready=0
c_human=0
c_triage=0
c_info=0
c_done=0
c_wontfix=0
c_unset=0

ready_list=()
blocked_list=()

get_field() {
  grep -m1 -i "^${2}:" "$1" 2>/dev/null | sed -E "s/^[^:]+:[[:space:]]*//" || true
}

issue_id() {
  basename "$1" .md | sed -E 's/^[0-9]+-//'
}

for f in $ISSUES_GLOB; do
  [[ -f "$f" ]] || continue
  s="$(get_field "$f" "Status")"
  case "$s" in
    ready-for-agent) c_ready=$((c_ready+1)) ;;
    ready-for-human) c_human=$((c_human+1)) ;;
    needs-triage)    c_triage=$((c_triage+1)) ;;
    needs-info)      c_info=$((c_info+1)) ;;
    done)            c_done=$((c_done+1)) ;;
    wontfix)         c_wontfix=$((c_wontfix+1)) ;;
    *)               c_unset=$((c_unset+1)) ;;
  esac

  if [[ "$s" == "ready-for-agent" ]]; then
    blockers="$(get_field "$f" "Blocked-by")"
    case "$(echo "$blockers" | tr '[:upper:]' '[:lower:]' | xargs)" in
      none|-|n/a|na) blockers="" ;;
    esac
    if [[ -n "$blockers" ]]; then
      blocked=0
      IFS=',' read -ra BS <<< "$blockers"
      for b in "${BS[@]}"; do
        b="$(echo "$b" | xargs)"
        [[ -z "$b" ]] && continue
        case "$(echo "$b" | tr '[:upper:]' '[:lower:]')" in none|-|n/a|na) continue ;; esac
        bfile=""
        for cand in $ISSUES_GLOB; do
          [[ -f "$cand" ]] || continue
          if [[ "$(issue_id "$cand")" == "$b" ]] || [[ "$(basename "$cand" .md)" == "$b" ]]; then
            bfile="$cand"; break
          fi
        done
        if [[ -z "$bfile" ]] || [[ "$(get_field "$bfile" "Status")" != "done" ]]; then
          blocked=1; break
        fi
      done
      if [[ $blocked -eq 1 ]]; then
        blocked_list+=("$(issue_id "$f")  ($f)")
      else
        ready_list+=("$(issue_id "$f")  ($f)")
      fi
    else
      ready_list+=("$(issue_id "$f")  ($f)")
    fi
  fi
done

echo "Harness status: $(basename "$PROJECT_DIR")"
echo "============================================"
printf "  %-18s %d\n" "ready-for-agent:" "$c_ready"
printf "  %-18s %d\n" "ready-for-human:" "$c_human"
printf "  %-18s %d\n" "needs-triage:" "$c_triage"
printf "  %-18s %d\n" "needs-info:" "$c_info"
printf "  %-18s %d\n" "done:" "$c_done"
printf "  %-18s %d\n" "wontfix:" "$c_wontfix"
[[ $c_unset -gt 0 ]] && printf "  %-18s %d\n" "(no status):" "$c_unset"

if [[ ${#ready_list[@]} -gt 0 ]]; then
  echo
  echo "Ready for Ralph (unblocked):"
  for r in "${ready_list[@]}"; do echo "  • $r"; done
fi

if [[ ${#blocked_list[@]} -gt 0 ]]; then
  echo
  echo "Ready-for-agent but blocked:"
  for r in "${blocked_list[@]}"; do echo "  • $r"; done
fi
