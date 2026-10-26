#!/usr/bin/env bash
# Smallest check that fails if the visual gate logic breaks:
# visual-stage.sh must skip non-visual diffs without a model call, map criteria and
# regressions to pass/concerns/fail (exit 0/0/2), exit 1 when it cannot run, and stop
# the dev server it started. Fake `claude` and `npx` on PATH, so no model, no browser.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
HARNESS="$HERE/../harness"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("",0)); print(s.getsockname()[1])')"

mkdir -p "$TMP/proj/.claude" "$TMP/proj/issues/f" "$TMP/bin"
cd "$TMP/proj" && git init -q && git commit -q --allow-empty -m init
cat > .claude/harness.config.sh <<EOF
VISUAL_REVIEW=on
VISUAL_BASE_URL="http://staging.invalid"
VISUAL_DEV_URL="http://127.0.0.1:$PORT"
VISUAL_DEV_CMD="python3 -m http.server $PORT"
EOF
printf 'Status: ready-for-agent\n\n# Thing\n\n## Acceptance criteria\n\n- [ ] Shows a banner\n' > issues/f/01-thing.md

# Fake npx: "playwright screenshot ... <url> <out>" writes <out>, anything else succeeds
cat > "$TMP/bin/npx" <<'SH'
#!/usr/bin/env bash
[[ " $* " == *" screenshot "* ]] && echo png > "${@: -1}"
exit 0
SH
# Fake claude: logs each call; route-picking prompt gets routes, verdict prompt gets FAKE_VISUAL
cat > "$TMP/bin/claude" <<'SH'
#!/usr/bin/env bash
echo call >> "$CLAUDE_LOG"
if [[ "$*" == *"VISUAL_ROUTES"* ]]; then echo '{"routes":["/"],"reason":"index"}'; else echo "$FAKE_VISUAL"; fi
SH
chmod +x "$TMP/bin/npx" "$TMP/bin/claude"
export PATH="$TMP/bin:$PATH" CLAUDE_LOG="$TMP/claude.log"

EVAL=issues/f/01-thing.eval.json
run() { FAKE_VISUAL="$1" "$HARNESS/visual-stage.sh" issues/f/01-thing.md STAGED >/dev/null 2>&1 && echo 0 || echo $?; }
verdict() { python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['axes']['visual']['verdict'])" "$EVAL"; }
fail() { echo "FAIL: $1"; exit 1; }

# Skip path: only a test file changed, so no model call and a pass
mkdir -p src && echo t > src/a.test.ts && git add -A
: > "$CLAUDE_LOG"
[[ "$(run x)" == 0 ]] || fail "skip should exit 0"
[[ ! -s "$CLAUDE_LOG" ]] || fail "skip should not call the model"
grep -q '"skipped": true' "$EVAL" || fail "skip not recorded in eval file"

# Visible change: verdict mapping
echo '<h1>hi</h1>' > index.html && git add -A
done_='{"criteria":[{"criterion":"Shows a banner","status":"done","reason":"visible"}],"regressions":[]}'
partial='{"criteria":[{"criterion":"Shows a banner","status":"partial","reason":"no mobile"}],"regressions":[]}'
notdone='{"criteria":[{"criterion":"Shows a banner","status":"not done","reason":"absent"}],"regressions":[]}'
broken='{"criteria":[{"criterion":"Shows a banner","status":"done","reason":"ok"}],"regressions":[{"route":"/","severity":"breakage","description":"overflow"}]}'
drift='{"criteria":[{"criterion":"Shows a banner","status":"done","reason":"ok"}],"regressions":[{"route":"/","severity":"drift","description":"copy differs"}]}'

[[ "$(run "$done_")" == 0 ]]   || fail "done should exit 0";       [[ "$(verdict)" == pass ]]     || fail "done should pass"
[[ "$(run "$partial")" == 0 ]] || fail "partial should exit 0";    [[ "$(verdict)" == concerns ]] || fail "partial should be concerns"
[[ "$(run "$notdone")" == 2 ]] || fail "not done should exit 2";   [[ "$(verdict)" == fail ]]     || fail "not done should fail"
[[ "$(run "$broken")" == 2 ]]  || fail "breakage should exit 2";   [[ "$(verdict)" == fail ]]     || fail "breakage should fail"
[[ "$(run "$drift")" == 0 ]]   || fail "drift should exit 0";      [[ "$(verdict)" == concerns ]] || fail "drift should be concerns"
[[ "$(run 'I refuse')" == 1 ]] || fail "no JSON should exit 1"

# The dev server it started is stopped again, and screenshots stay out of git
curl -sf -o /dev/null "http://127.0.0.1:$PORT" && fail "dev server left running"
[[ -z "$(git status --porcelain -- issues/f/screenshots)" ]] || fail "screenshots not gitignored"

# Overall verdict is the worst axis: a reviewer pass plus a visual fail is a fail
echo '{"verdict":"pass","axes":{"standards":{"verdict":"pass"},"spec":{"verdict":"pass"}}}' > "$EVAL"
run "$notdone" >/dev/null
python3 -c "import json,sys; assert json.load(open(sys.argv[1]))['verdict']=='fail'" "$EVAL" || fail "overall verdict not worst axis"

# Missing base URL: refuses to run
sed -i.bak '/VISUAL_BASE_URL/d' .claude/harness.config.sh
[[ "$(run "$done_")" == 1 ]] || fail "missing VISUAL_BASE_URL should exit 1"

echo "visual-gate: 14 checks passed"
