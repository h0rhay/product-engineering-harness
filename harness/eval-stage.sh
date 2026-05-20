#!/usr/bin/env bash
# eval-stage — invoke the reviewer agent on a single issue + its diff.
# Writes a JSON eval to .scratch/<feature>/issues/<id>.eval.json.
#
# Usage:
#   eval-stage.sh <issue-file> [git-ref]
#
# git-ref defaults to HEAD (the most recent commit).

set -euo pipefail

ISSUE_FILE="${1:-}"
GIT_REF="${2:-HEAD}"

if [[ -z "$ISSUE_FILE" || ! -f "$ISSUE_FILE" ]]; then
  echo "Usage: eval-stage.sh <issue-file> [git-ref]" >&2
  exit 1
fi

PROJECT_DIR="$(pwd)"
CONFIG_FILE="${PROJECT_DIR}/.claude/harness.config.sh"
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "No harness config at $CONFIG_FILE" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$CONFIG_FILE"

REVIEWER_FILE="${HOME}/.claude/agents/reviewer.md"
if [[ ! -f "$REVIEWER_FILE" ]]; then
  echo "Reviewer agent not found at $REVIEWER_FILE" >&2
  exit 1
fi

issue_id() {
  basename "$1" .md | sed -E 's/^[0-9]+-//'
}

ID="$(issue_id "$ISSUE_FILE")"
EVAL_FILE="$(dirname "$ISSUE_FILE")/$(basename "$ISSUE_FILE" .md).eval.json"

# Strip frontmatter from the reviewer agent file to get just the system prompt body
REVIEWER_PROMPT="$(awk 'BEGIN{p=0} /^---$/{c++; if(c==2){p=1; next}} p' "$REVIEWER_FILE")"

# Build the binding context block
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

# Build the diff. Try to get just this issue's commit; fall back to full ref.
DIFF_CONTENT="$(git -C "$PROJECT_DIR" show --stat --patch "$GIT_REF" 2>/dev/null || echo "(no diff available)")"

PROMPT="${REVIEWER_PROMPT}

---

## Issue spec

File: ${ISSUE_FILE}

$(cat "$ISSUE_FILE")

---

## Binding context

$(build_context_block)

---

## Diff (${GIT_REF})

\`\`\`
${DIFF_CONTENT}
\`\`\`

---

Now produce the JSON eval as specified above. Output nothing but the JSON object."

echo "Evaluating $ID against $GIT_REF..."
RAW_OUTPUT="$(claude --dangerously-skip-permissions -p "$PROMPT" 2>/dev/null)"

# Strip code fences and any prose around the JSON
JSON_ONLY="$(echo "$RAW_OUTPUT" | sed -n '/^{/,/^}$/p')"
if [[ -z "$JSON_ONLY" ]]; then
  # Fallback: maybe the JSON is wrapped in ```json blocks
  JSON_ONLY="$(echo "$RAW_OUTPUT" | awk '/```json/{flag=1;next} /```$/{flag=0} flag')"
fi

if [[ -z "$JSON_ONLY" ]]; then
  echo "Reviewer did not produce JSON. Raw output:" >&2
  echo "$RAW_OUTPUT" | head -30 >&2
  exit 1
fi

# Validate it parses as JSON
if ! echo "$JSON_ONLY" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  echo "Reviewer output did not parse as JSON:" >&2
  echo "$JSON_ONLY" | head -30 >&2
  exit 1
fi

echo "$JSON_ONLY" > "$EVAL_FILE"
echo "✓ Eval written: $EVAL_FILE"

# Quick summary
python3 - "$EVAL_FILE" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
print(f"  verdict: {data.get('verdict','?')}")
scores = data.get('scores', {})
for k, v in scores.items():
    s = v.get('score') if isinstance(v, dict) else v
    print(f"  {k}: {s}")
vios = data.get('violations', [])
if vios:
    print(f"  {len(vios)} violation(s):")
    for v in vios[:3]:
        sev = v.get('severity','?')
        rule = v.get('rule','?')[:60]
        print(f"    [{sev}] {rule}")
PY
