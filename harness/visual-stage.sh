#!/usr/bin/env bash
# visual-stage: screenshot the pages an issue changed and judge them against its
# acceptance criteria. Adds a `visual` axis to issues/<feature>/<id>.eval.json and
# sets the overall verdict to the worst axis.
#
# Usage:
#   visual-stage.sh <issue-file> [git-ref|STAGED]
#
# "After" is the local dev server (VISUAL_DEV_URL, started with VISUAL_DEV_CMD if it
# is not already up). "Before" is VISUAL_BASE_URL, usually staging. Screenshots stay
# local under issues/<feature>/screenshots/<id>/ and are gitignored.
#
# Exit codes: 0 pass, concerns or skipped; 2 fail; 1 the visual review did not run.
# Env: VISUAL_MODEL overrides the model (default sonnet).

set -euo pipefail

ISSUE_FILE="${1:-}"
GIT_REF="${2:-HEAD}"

if [[ -z "$ISSUE_FILE" || ! -f "$ISSUE_FILE" ]]; then
  echo "Usage: visual-stage.sh <issue-file> [git-ref|STAGED]" >&2
  exit 1
fi

CONFIG_FILE="$(pwd)/.claude/harness.config.sh"
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "No harness config at $CONFIG_FILE" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$CONFIG_FILE"

die() { echo "✗ visual review did not run: $1" >&2; exit 1; }

ID="$(basename "$ISSUE_FILE" .md | sed -E 's/^[0-9]+-//')"
EVAL_FILE="$(dirname "$ISSUE_FILE")/$(basename "$ISSUE_FILE" .md).eval.json"
SHOTS="$(dirname "$ISSUE_FILE")/screenshots/$(basename "$ISSUE_FILE" .md)"
MODEL="${VISUAL_MODEL:-sonnet}"
VIEWPORTS="${VISUAL_VIEWPORTS:-1440x900 390x844}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Write the visual axis into the eval file. Overall verdict = worst axis.
# Args: verdict, notes, skipped (true|false), detail JSON.
record() {
  python3 - "$EVAL_FILE" "$ID" "$1" "$2" "$3" "$4" <<'PY'
import json, os, sys
path, issue_id, verdict, notes, skipped, detail = sys.argv[1:]
data = json.load(open(path)) if os.path.exists(path) else {"issue_id": issue_id}
data.setdefault("axes", {})["visual"] = {"verdict": verdict, "notes": notes, "skipped": skipped == "true"}
data["visual"] = json.loads(detail)
rank = ["pass", "concerns", "fail"]
data["verdict"] = max((a.get("verdict", "pass") for a in data["axes"].values()), key=rank.index)
json.dump(data, open(path, "w"), indent=2)
PY
}

skip() {
  record pass "skipped: $1" true '{}'
  echo "✓ Visual review skipped: $1"
  exit 0
}

# Pull the first JSON object out of model output, or fail.
json_from() {
  python3 -c '
import json, sys
t = sys.stdin.read(); i, j = t.find("{"), t.rfind("}")
print(json.dumps(json.loads(t[i:j + 1])))' 2>/dev/null
}

# ponytail: fixed list of paths that never render; when in doubt, the review runs.
non_visual() {
  case "$1" in
    *.test.*|*.spec.*|tests/*|*/tests/*|__tests__/*|*/__tests__/*|e2e/*|*/e2e/*) return 0 ;;
    .github/*|docs/*|README*|*/README*|CHANGELOG*|LICENSE*) return 0 ;;
    pnpm-lock.yaml|package-lock.json|yarn.lock) return 0 ;;
    .claude/*|issues/*|.scratch/*) return 0 ;;
  esac
  return 1
}

if [[ "$GIT_REF" == "STAGED" ]]; then
  CHANGED="$(git diff --cached --name-only -- . ':(exclude)issues/')"
else
  CHANGED="$(git show --name-only --format= "$GIT_REF" -- . ':(exclude)issues/')"
fi

visible=0
while IFS= read -r f; do
  [[ -n "$f" ]] && ! non_visual "$f" && visible=1
done <<< "$CHANGED"
[[ $visible -eq 0 ]] && skip "no rendered files changed"

[[ -n "${VISUAL_BASE_URL:-}" ]] || die "VISUAL_BASE_URL is not set in $CONFIG_FILE"
[[ -n "${VISUAL_DEV_URL:-}" ]] || die "VISUAL_DEV_URL is not set in $CONFIG_FILE"
[[ -z "${VISUAL_STORAGE_STATE:-}" || -f "$VISUAL_STORAGE_STATE" ]] \
  || die "VISUAL_STORAGE_STATE file $VISUAL_STORAGE_STATE is missing; make it with: harness visual-state"

# "Before" is whatever VISUAL_BASE_URL deploys from. If that branch already has the
# change, both sides show it and the comparison proves nothing. A branch far behind
# it shows the base's newer work as differences, so say so.
BASE_BRANCH="${VISUAL_BASE_BRANCH:-$(git symbolic-ref -q --short refs/remotes/origin/HEAD || true)}"
BEHIND_NOTE=""
if [[ -n "$BASE_BRANCH" ]] && git rev-parse -q --verify "$BASE_BRANCH^{commit}" > /dev/null; then
  if [[ "$GIT_REF" != "STAGED" ]] && git merge-base --is-ancestor "$GIT_REF" "$BASE_BRANCH"; then
    die "$GIT_REF is already on $BASE_BRANCH, so $VISUAL_BASE_URL shows the change too; review it before it merges"
  fi
  behind="$(git rev-list --count "HEAD..$BASE_BRANCH")"
  if (( behind > ${VISUAL_MAX_BEHIND:-20} )); then
    BEHIND_NOTE="\"before\" also has $behind commits from $BASE_BRANCH that are not in this build; differences they explain are drift."
    echo "⚠ $behind commits on $BASE_BRANCH are not in this build; update the branch or expect drift from them" >&2
  fi
fi

mkdir -p "$SHOTS"
echo '*' > "$(dirname "$SHOTS")/.gitignore"
rm -f "$SHOTS"/*.png

# Dev server: reuse one that already answers, otherwise start it in its own process
# group so the whole tree (pnpm, vite, node) can be stopped on exit. Some dev commands
# detach into the background and escape the group. Nothing answered on this port before
# we started, so whatever listens on it now is ours.
SERVER_PID=""
stop_server() {
  [[ -n "$SERVER_PID" ]] || return 0
  kill -- -"$SERVER_PID" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true
  local port listeners
  port="$(sed -nE 's#^[a-z]+://[^/:]+:([0-9]+).*#\1#p' <<< "$VISUAL_DEV_URL")"
  [[ -n "$port" ]] || return 0
  listeners="$(lsof -ti "tcp:$port" -sTCP:LISTEN 2>/dev/null || true)"
  [[ -z "$listeners" ]] || kill $listeners 2>/dev/null || true
}
trap stop_server EXIT

if ! curl -sf -o /dev/null "$VISUAL_DEV_URL"; then
  [[ -n "${VISUAL_DEV_CMD:-}" ]] || die "nothing answers at $VISUAL_DEV_URL and VISUAL_DEV_CMD is not set"
  echo "Starting dev server: $VISUAL_DEV_CMD"
  set -m
  bash -c "$VISUAL_DEV_CMD" > "$SHOTS/dev-server.log" 2>&1 &
  SERVER_PID=$!
  set +m
  timeout="${VISUAL_DEV_TIMEOUT_SECS:-120}"
  waiting=1
  for ((i = 0; i < timeout; i++)); do
    curl -sf -o /dev/null "$VISUAL_DEV_URL" && break
    # A clean exit may mean the command detached a server that is still coming up.
    if [[ $waiting -eq 1 ]] && ! kill -0 "$SERVER_PID" 2>/dev/null; then
      wait "$SERVER_PID" || die "dev server exited; see $SHOTS/dev-server.log"
      waiting=0
    fi
    sleep 1
  done
  curl -sf -o /dev/null "$VISUAL_DEV_URL" \
    || die "dev server did not answer at $VISUAL_DEV_URL within ${timeout}s; see $SHOTS/dev-server.log"
fi

# Routes: an explicit `Routes:` line in the issue wins, otherwise the model picks.
ROUTES="$(sed -nE 's/^Routes:[[:space:]]*//p' "$ISSUE_FILE" | head -1 | tr ',' ' ')"
if [[ -z "$ROUTES" ]]; then
  ROUTES_PROMPT="VISUAL_ROUTES. You are picking which URL paths of a web app to screenshot so a
reviewer can see the change below. Read the changed files if you need to. Map each
changed file to the page routes that render it (any framework). Only list routes that
exist in the app after this change. When an acceptance criterion names variants of a
page (languages, regions, themes, signed in or out), list a route for each variant it
names, not just the default. If nothing changed renders in a browser (for
example server-only code), return an empty list.

## Issue

$(cat "$ISSUE_FILE")

## Changed files

${CHANGED}

Output nothing but JSON: {\"routes\": [\"/path\"], \"reason\": \"<one line>\"}"
  ROUTES_JSON="$(claude --dangerously-skip-permissions --model "$MODEL" -p "$ROUTES_PROMPT" 2>/dev/null | json_from)" \
    || die "route picker did not return JSON"
  ROUTES="$(python3 -c 'import json,sys; print(" ".join(json.loads(sys.argv[1]).get("routes", [])))' "$ROUTES_JSON")"
  [[ -n "$ROUTES" ]] || skip "$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("reason", "no routes render this change"))' "$ROUTES_JSON")"
fi

PLAYWRIGHT="$(npx -y -p playwright -c 'command -v playwright')" || die "could not find Playwright"
"$PLAYWRIGHT" install chromium > /dev/null 2>&1 || die "could not install Chromium for Playwright"
export NODE_PATH="$(dirname "$(dirname "$PLAYWRIGHT")")"
export VISUAL_STORAGE_STATE

SHOT_LIST=""
MISSING=""
DIFFS=""
for route in $ROUTES; do
  slug="$(echo "$route" | sed -E 's#^/+##; s#/+$##; s#[^A-Za-z0-9]+#-#g')"
  slug="${slug:-home}"
  for vp in $VIEWPORTS; do
    for side in before after; do
      base="$VISUAL_DEV_URL"; [[ $side == before ]] && base="$VISUAL_BASE_URL"
      out="$SHOTS/$side-$vp-$slug.png"
      if node "$HERE/visual-capture.js" "$vp" "${base%/}$route" "$out" > /dev/null 2>&1; then
        SHOT_LIST+="$out"$'\n'
      else
        MISSING+="$side $vp $route"$'\n'
      fi
    done
    before="$SHOTS/before-$vp-$slug.png"; after="$SHOTS/after-$vp-$slug.png"
    if [[ -f "$before" && -f "$after" ]]; then
      diff="$(python3 "$HERE/visual-diff.py" "$before" "$after" "$SHOTS/zoom-$vp-$slug" 2>&1)" \
        || diff="not measured: $diff"
      DIFFS+="### $route at $vp"$'\n'"$diff"$'\n\n'
    fi
  done
done
grep -q '/after-' <<< "$SHOT_LIST" || die "no 'after' screenshot could be taken from $VISUAL_DEV_URL"

VERDICT_PROMPT="You are reviewing a UI change from screenshots. Use the Read tool to open
every image listed below, then judge the change against the issue.

\"before\" is ${VISUAL_BASE_URL} (staging or production). \"after\" is the local build
with the change. File names are <before|after>-<viewport>-<route>.png. ${BEHIND_NOTE}

Full-page images are shrunk when you read them, so small details disappear. Use them
for overall layout. For detail, use the measured differences below: every band of pixels
that changed, with its size and main colour, and full-resolution crops. Open every crop
on every route and viewport before judging, including the ones that look like repeats. Do
not guess what a band is from its numbers.

1. For each acceptance criterion in the issue, decide \"done\", \"partial\" or
   \"not done\", with a one-line reason that cites what is visible or measured. \"done\"
   needs the thing itself: seen in an image, or confirmed by a measured size and colour.
   A side effect, such as the page getting taller, is not enough. If you cannot confirm a
   stated detail such as a colour, it is \"partial\"; if what you can see contradicts it,
   \"not done\". Criteria that cannot be seen in a screenshot (tests, analytics, code
   structure) are \"done\" with reason \"not visual\".
2. List unintended changes between before and after that the issue did not ask for.
   Things moving only because the requested change takes up space are not a change.
   Severity \"breakage\": horizontal overflow on mobile, overlapping or cut-off
   elements, missing sections, broken layout. Severity \"drift\": layout or styling that
   moved or changed without being asked for. Severity \"content\": the same element with
   different data, such as changed text, counts or reordered items, which staging and the
   local build can legitimately disagree on.

Screenshots are a secondhand signal. They show whether the ticket was done and whether
anything obviously broke. They are not a source of truth for pixel parity, so never
propose exact CSS values from them.

## Issue

$(cat "$ISSUE_FILE")

## Screenshots

${SHOT_LIST}
## Measured differences

${DIFFS:-none}
## Captures that failed (a failed \"after\" capture means the page is broken locally)

${MISSING:-none}

Output nothing but JSON:
{\"criteria\": [{\"criterion\": \"...\", \"status\": \"done|partial|not done\", \"reason\": \"...\"}],
 \"regressions\": [{\"route\": \"/\", \"viewport\": \"390x844\", \"severity\": \"breakage|drift|content\", \"description\": \"...\"}],
 \"follow_up\": [\"<remaining work, one line each>\"]}"

echo "Visual review of $ID: routes $ROUTES"
DETAIL="$(claude --dangerously-skip-permissions --model "$MODEL" -p "$VERDICT_PROMPT" 2>/dev/null | json_from)" \
  || die "visual reviewer did not return JSON"

# Deterministic gate: not done or breakage fails; partial or drift is concerns.
# Content differences are reported but never change the verdict.
read -r VERDICT NOTES < <(python3 -c '
import json, sys
d = json.loads(sys.argv[1])
s = [c.get("status") for c in d.get("criteria", [])]
r = [x.get("severity") for x in d.get("regressions", [])]
v = "fail" if "not done" in s or "breakage" in r else "concerns" if "partial" in s or "drift" in r else "pass"
print(v, "%d/%d criteria done, %d breakage, %d drift, %d content" % (s.count("done"), len(s), r.count("breakage"), r.count("drift"), r.count("content")))
' "$DETAIL")

DETAIL="$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); d["routes"]=sys.argv[2].split(); d["screenshots"]=sys.argv[3]; print(json.dumps(d))' "$DETAIL" "$ROUTES" "$SHOTS")"
record "$VERDICT" "$NOTES" false "$DETAIL"
echo "  visual: $VERDICT ($NOTES)"
echo "  screenshots: $SHOTS"

[[ "$VERDICT" == "fail" ]] && exit 2
exit 0
