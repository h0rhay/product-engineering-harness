#!/usr/bin/env bash
# visual-state: save a browser state (cookies, local storage) for the visual review, so
# "before" and "after" are both captured past the same consent prompt, sign-in or
# welcome dialog. Opens VISUAL_BASE_URL, then VISUAL_DEV_URL. Do what a returning
# visitor would have done on each, then close the browser window.
#
# Usage: visual-state.sh    (run from the project root, with the dev server up)

set -euo pipefail

CONFIG_FILE="$(pwd)/.claude/harness.config.sh"
[[ -f "$CONFIG_FILE" ]] || { echo "No harness config at $CONFIG_FILE" >&2; exit 1; }
# shellcheck disable=SC1090
source "$CONFIG_FILE"

die() { echo "✗ $1" >&2; exit 1; }
[[ -n "${VISUAL_STORAGE_STATE:-}" ]] || die "set VISUAL_STORAGE_STATE in $CONFIG_FILE first"
[[ -n "${VISUAL_BASE_URL:-}" && -n "${VISUAL_DEV_URL:-}" ]] || die "set VISUAL_BASE_URL and VISUAL_DEV_URL in $CONFIG_FILE first"
curl -sf -o /dev/null "$VISUAL_DEV_URL" || die "nothing answers at $VISUAL_DEV_URL; start the dev server first"

mkdir -p "$(dirname "$VISUAL_STORAGE_STATE")"
for url in "$VISUAL_BASE_URL" "$VISUAL_DEV_URL"; do
  echo "Opening $url. Dismiss whatever should not be in the screenshots, then close the window."
  load=()
  [[ -f "$VISUAL_STORAGE_STATE" ]] && load=(--load-storage "$VISUAL_STORAGE_STATE")
  npx -y playwright open ${load[@]+"${load[@]}"} --save-storage "$VISUAL_STORAGE_STATE" "$url"
done
echo "✓ Saved $VISUAL_STORAGE_STATE. Keep it out of git: it can hold session cookies."
