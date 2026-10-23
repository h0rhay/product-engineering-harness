#!/usr/bin/env bash
# Smallest check that fails if the eval gate logic breaks:
# eval-stage.sh must exit 0 on pass/concerns, 2 on fail, 1 when no JSON comes back.
# Uses a fake `claude` on PATH, so no model call and no cost.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
HARNESS="$HERE/../harness"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Fake project with config, issue and one staged change
mkdir -p "$TMP/proj/.claude" "$TMP/proj/issues/f" "$TMP/bin"
cd "$TMP/proj" && git init -q && git commit -q --allow-empty -m init
printf 'CONTEXT_FILES=()\n' > .claude/harness.config.sh
printf 'Status: ready-for-agent\n\n# Thing\n' > issues/f/01-thing.md
echo hello > src.txt && git add -A
printf -- '---\nname: reviewer\nmodel: haiku\n---\nprompt\n' > "$TMP/reviewer.md"

# Fake claude: prints whatever FAKE_VERDICT says
cat > "$TMP/bin/claude" <<'SH'
#!/usr/bin/env bash
[[ "$FAKE_VERDICT" == "none" ]] && { echo "I refuse"; exit 0; }
printf '{\n"issue_id":"thing","verdict":"%s","scores":{},"violations":[]\n}\n' "$FAKE_VERDICT"
SH
chmod +x "$TMP/bin/claude"
export PATH="$TMP/bin:$PATH" REVIEWER_FILE="$TMP/reviewer.md"

run() { FAKE_VERDICT="$1" "$HARNESS/eval-stage.sh" issues/f/01-thing.md STAGED >/dev/null 2>&1; echo $?; }
[[ "$(run pass)" == 0 ]]     || { echo "FAIL: pass should exit 0"; exit 1; }
[[ "$(run concerns)" == 0 ]] || { echo "FAIL: concerns should exit 0"; exit 1; }
[[ "$(run fail)" == 2 ]]     || { echo "FAIL: fail should exit 2"; exit 1; }
[[ "$(run none)" == 1 ]]     || { echo "FAIL: no JSON should exit 1"; exit 1; }
grep -q '"verdict":"fail"' issues/f/01-thing.eval.json || { echo "FAIL: eval file not written"; exit 1; }
echo "eval-gate: 5 checks passed"
