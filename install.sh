#!/usr/bin/env bash
# install.sh — wire the product-engineering-harness into ~/.claude/
#
# Usage:
#   ./install.sh            Copy agents + harness scripts into ~/.claude/ (safe, portable)
#   ./install.sh --link     Symlink instead of copy (for maintainers; repo edits go live)
#   ./install.sh --help
#
# Idempotent: re-running updates the installed files. Existing unrelated files
# in ~/.claude/agents and ~/.claude/harness are left untouched.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${HOME}/.claude"
MODE="copy"

case "${1:-}" in
  --link) MODE="link" ;;
  --help|-h)
    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  "") ;;
  *) echo "unknown flag: $1 (try --help)" >&2; exit 1 ;;
esac

echo "Installing product-engineering-harness into ${CLAUDE_DIR} (mode: ${MODE})"
echo

mkdir -p "${CLAUDE_DIR}/agents" "${CLAUDE_DIR}/harness" "${CLAUDE_DIR}/skills"

place() {
  # place <src> <dest>
  local src="$1" dest="$2"
  if [[ "$MODE" == "link" ]]; then
    ln -sf "$src" "$dest"
  else
    cp "$src" "$dest"
  fi
}

# --- agents ---------------------------------------------------------------
for f in "${REPO_DIR}"/agents/*.md; do
  place "$f" "${CLAUDE_DIR}/agents/$(basename "$f")"
done
echo "  agents:  $(ls "${REPO_DIR}"/agents/*.md | wc -l | tr -d ' ') specialist definitions"

# --- harness scripts ------------------------------------------------------
for f in "${REPO_DIR}"/harness/*.sh; do
  place "$f" "${CLAUDE_DIR}/harness/$(basename "$f")"
  chmod +x "${CLAUDE_DIR}/harness/$(basename "$f")"
done
echo "  harness: $(ls "${REPO_DIR}"/harness/*.sh | wc -l | tr -d ' ') scripts"

# --- skill installer helper ----------------------------------------------
if [[ -f "${REPO_DIR}/skills/_install-skill.sh" ]]; then
  place "${REPO_DIR}/skills/_install-skill.sh" "${CLAUDE_DIR}/skills/_install-skill.sh"
  chmod +x "${CLAUDE_DIR}/skills/_install-skill.sh"
  echo "  skills:  _install-skill.sh helper"
fi

# --- vendored skills (harness-native, shipped in this repo) ---------------
# Upstream skills (Vercel, Matt Pocock, Impeccable) are NOT vendored — install
# those via _install-skill.sh. Only skills the harness itself owns live here.
vendored=0
for d in "${REPO_DIR}"/skills/*/; do
  [[ -f "${d}SKILL.md" ]] || continue
  name="$(basename "$d")"
  mkdir -p "${CLAUDE_DIR}/skills/${name}"
  place "${d}SKILL.md" "${CLAUDE_DIR}/skills/${name}/SKILL.md"
  vendored=$((vendored + 1))
done
[[ "$vendored" -gt 0 ]] && echo "  skills:  ${vendored} vendored (producer, every-layout)"

# --- shell alias ----------------------------------------------------------
SHELL_RC="${HOME}/.zshrc"
[[ -f "${HOME}/.bashrc" && ! -f "$SHELL_RC" ]] && SHELL_RC="${HOME}/.bashrc"
ALIAS_LINE="alias harness='${CLAUDE_DIR}/harness/harness.sh'"
if [[ -f "$SHELL_RC" ]] && grep -q "alias harness=" "$SHELL_RC"; then
  echo "  alias:   already present in $(basename "$SHELL_RC")"
else
  printf '\n# product-engineering-harness\n%s\n' "$ALIAS_LINE" >> "$SHELL_RC"
  echo "  alias:   added to $(basename "$SHELL_RC") (run 'source $SHELL_RC' or restart shell)"
fi

# --- engineering contract -------------------------------------------------
CLAUDE_MD="${CLAUDE_DIR}/CLAUDE.md"
if [[ -f "$CLAUDE_MD" ]] && grep -q "^## Engineering Contract" "$CLAUDE_MD"; then
  echo "  contract: already in ~/.claude/CLAUDE.md"
else
  {
    echo
    # Print the fenced contract body from the contract doc, without the code fences.
    awk '/^```markdown$/{f=1;next} /^```$/{if(f){exit}} f' "${REPO_DIR}/contract/engineering-contract.md"
  } >> "$CLAUDE_MD"
  echo "  contract: appended to ~/.claude/CLAUDE.md"
fi

cat <<EOF

Done.

Next steps (prerequisites the harness expects):

  1. Install the skills it dispatches:
     ~/.claude/skills/_install-skill.sh <github-tree-url>
     Recommended: Vercel react-best-practices + composition-patterns,
     Matt Pocock's skills (grill-with-docs, to-prd, to-issues, triage, tdd, diagnose),
     Impeccable (npx skills add pbakaus/impeccable).

  2. For the design phase, install design tooling:
     npm install -g @pencil.dev/cli   &&  pencil login
     npm install -g skillui

  3. Bootstrap a project:
     cd <your-project>  &&  harness init

  See README.md for the full workflow.
EOF
