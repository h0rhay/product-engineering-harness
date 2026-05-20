#!/usr/bin/env bash
# Install a skill from any GitHub repo into ~/.claude/skills/<name>/.
#
# Usage:
#   _install-skill.sh <github-tree-url> [local-name]
#
# Example:
#   _install-skill.sh https://github.com/vercel-labs/agent-skills/tree/main/skills/react-best-practices
#   _install-skill.sh https://github.com/owner/repo/tree/main/path/to/skill my-skill
#
# What it does:
#   1. Sparse-clones the repo (only the skill subpath, no blobs by default).
#   2. Copies SKILL.md and any sibling folders (rules/, scripts/, examples/) into
#      ~/.claude/skills/<local-name>/.
#   3. Skips build artifacts (AGENTS.md, README.md, metadata.json, package.json,
#      .git*, node_modules). Override with KEEP_EXTRAS=1 to copy everything.
#   4. Backs up any pre-existing destination to ~/.claude/backups/.
#
# Repeat the pattern for review/pen-testing/etc. skills by pointing at their
# upstream repos. No code changes needed.

set -euo pipefail

URL="${1:-}"
NAME="${2:-}"
SKILLS_DIR="${HOME}/.claude/skills"
BACKUP_DIR="${HOME}/.claude/backups"

if [[ -z "$URL" ]]; then
  sed -n '2,20p' "$0"
  exit 1
fi

# Parse https://github.com/<owner>/<repo>/tree/<ref>/<path>
if [[ ! "$URL" =~ ^https://github\.com/([^/]+)/([^/]+)/tree/([^/]+)/(.+)$ ]]; then
  echo "ERROR: URL must look like https://github.com/owner/repo/tree/<ref>/<path>" >&2
  exit 1
fi
OWNER="${BASH_REMATCH[1]}"
REPO="${BASH_REMATCH[2]}"
REF="${BASH_REMATCH[3]}"
SUBPATH="${BASH_REMATCH[4]}"
NAME="${NAME:-$(basename "$SUBPATH")}"

DEST="${SKILLS_DIR}/${NAME}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Source : github.com/${OWNER}/${REPO} @ ${REF}:${SUBPATH}"
echo "Dest   : ${DEST}"
echo

# Back up an existing install
if [[ -e "$DEST" ]]; then
  mkdir -p "$BACKUP_DIR"
  STAMP="$(date +%Y%m%d-%H%M%S)"
  BACKUP="${BACKUP_DIR}/${NAME}.${STAMP}.bak"
  echo "Backing up existing ${DEST} -> ${BACKUP}"
  mv "$DEST" "$BACKUP"
fi

# Sparse clone
cd "$TMP"
git clone --depth 1 --filter=blob:none --sparse \
  --branch "$REF" "https://github.com/${OWNER}/${REPO}.git" repo >/dev/null 2>&1
cd repo
git sparse-checkout set "$SUBPATH" >/dev/null

SRC="${TMP}/repo/${SUBPATH}"
if [[ ! -d "$SRC" ]]; then
  echo "ERROR: subpath '$SUBPATH' not found in repo" >&2
  exit 1
fi

mkdir -p "$DEST"

# Copy SKILL.md (required for auto-discovery)
if [[ ! -f "${SRC}/SKILL.md" ]]; then
  echo "WARNING: no SKILL.md found at source. Skill auto-discovery requires one." >&2
fi

# Default skip list (build artifacts, repo housekeeping)
SKIP_PATTERN='^(AGENTS\.md|README\.md|metadata\.json|package\.json|package-lock\.json|pnpm-lock\.yaml|tsconfig\.json|\.git.*|node_modules|src|dist|build|test-cases\.json)$'

cd "$SRC"
for entry in * .[!.]*; do
  [[ -e "$entry" ]] || continue
  if [[ "${KEEP_EXTRAS:-0}" != "1" ]] && [[ "$entry" =~ $SKIP_PATTERN ]]; then
    echo "  skip  $entry"
    continue
  fi
  echo "  copy  $entry"
  cp -R "$entry" "$DEST/"
done

echo
echo "Installed. Verify in next session via the available skills list."
if [[ -f "$DEST/SKILL.md" ]]; then
  python3 - "$DEST/SKILL.md" <<'PY'
import sys, re
text = open(sys.argv[1]).read()
m = re.match(r'---\n(.*?)\n---', text, re.S)
if not m:
    print("  (no frontmatter)")
    sys.exit()
fm = m.group(1)
name = re.search(r'^name:\s*(.+)$', fm, re.M)
print(f"  name:        {name.group(1).strip() if name else '(missing)'}")
desc = re.search(r'^description:\s*(.*(?:\n[ \t]+.+)*)', fm, re.M)
if desc:
    flat = re.sub(r'\s+', ' ', desc.group(1)).strip()
    print(f"  description: {flat[:140]}{'...' if len(flat) > 140 else ''}")
PY
fi
