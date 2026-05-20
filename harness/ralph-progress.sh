#!/usr/bin/env bash
# ralph-progress — stream-json parser for the harness.
# Reads NDJSON from stdin, prints a single live progress line,
# writes the full text output to $1.

OUTPUT_FILE="$1"
START=$(date +%s)
spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
spin_i=0
action=""
phase=""

update() {
  local elapsed=$(( $(date +%s) - START ))
  local mins=$((elapsed / 60))
  local secs=$((elapsed % 60))
  local c="${spin:spin_i:1}"
  spin_i=$(( (spin_i + 1) % 10 ))

  local line=""
  [[ -n "$phase" ]] && line="$phase"
  [[ -n "$action" ]] && line="${line:+$line │ }$action"
  [[ -n "$line" ]] || line="working"

  # Truncate
  if [[ ${#line} -gt 80 ]]; then
    line="${line:0:80}…"
  fi

  printf "\r\033[K%s %s [%02d:%02d]" "$c" "$line" "$mins" "$secs"
}

while IFS= read -r raw; do
  [[ -z "$raw" ]] && continue

  if echo "$raw" | grep -q '"type":"tool_use"'; then
    tool="$(echo "$raw" | sed -n 's/.*"name":"\([^"]*\)".*/\1/p')"
    case "$tool" in
      Read)
        f="$(echo "$raw" | sed -n 's/.*"file_path":"\([^"]*\)".*/\1/p')"
        [[ -n "$f" ]] && action="Reading $(basename "$f")" || action="Reading"
        ;;
      Edit|Write)
        f="$(echo "$raw" | sed -n 's/.*"file_path":"\([^"]*\)".*/\1/p')"
        [[ -n "$f" ]] && action="$tool $(basename "$f")" || action="$tool"
        ;;
      Bash)
        c="$(echo "$raw" | sed -n 's/.*"command":"\([^"]*\)".*/\1/p' | head -c 80)"
        case "$c" in
          *"pnpm lint"*|*"npm run lint"*)        action="Linting"; phase="Quality" ;;
          *"pnpm test"*|*"npm test"*|*"vitest"*) action="Running tests"; phase="Quality" ;;
          *"pnpm typecheck"*|*"tsc"*)            action="Typechecking"; phase="Quality" ;;
          *"pnpm build"*|*"npm run build"*)      action="Building"; phase="Quality" ;;
          *"git commit"*)                        action="Committing"; phase="Finishing" ;;
          *"git add"*)                           action="Staging"; phase="Finishing" ;;
          *)                                     action="\$ ${c:0:50}" ;;
        esac
        ;;
      Glob)
        p="$(echo "$raw" | sed -n 's/.*"pattern":"\([^"]*\)".*/\1/p')"
        action="Searching ${p:-files}"
        ;;
      Grep)
        p="$(echo "$raw" | sed -n 's/.*"pattern":"\([^"]*\)".*/\1/p')"
        action="Grep ${p:0:30}"
        ;;
    esac
    update
  fi

  if echo "$raw" | grep -q '"text_delta"'; then
    text="$(echo "$raw" | sed -n 's/.*"text":"\([^"]*\)".*/\1/p')"
    if echo "$text" | grep -qi 'implement\|creating\|building\|adding'; then
      [[ "$phase" != "Quality" && "$phase" != "Finishing" ]] && phase="Implementing"
    fi
    if echo "$text" | grep -qi 'simplif\|reviewing.*changes\|clean.*code'; then
      [[ "$phase" != "Quality" && "$phase" != "Finishing" ]] && phase="Simplify"
    fi

    if [[ -n "$OUTPUT_FILE" ]]; then
      echo -n "$text" | sed 's/\\n/\n/g; s/\\t/\t/g; s/\\"/"/g' >> "$OUTPUT_FILE"
    fi
  fi
done

printf "\r\033[K"
echo
