#!/usr/bin/env bash
# PreToolUse hook: blocks brute-force positioning workarounds in UI code.
# Rule (docs/rules.md): work WITH a library's positioning system, never
# against it. Absolute positioning that IMPLEMENTS a documented pattern is
# fine — and must say so with a citation comment (cite: <source>).
# Exit 2 = block; stderr is shown to the agent.

# Shared PEH banner output (peh_block).
_peh_lib="${PEH_LIB:-$HOME/.claude/harness/hooks/_peh.sh}"
[[ -r "$_peh_lib" ]] || _peh_lib="$(dirname "$0")/../harness/hooks/_peh.sh"
# shellcheck source=/dev/null
source "$_peh_lib"

input=$(cat)
tool=$(echo "$input" | jq -r '.tool_name // empty')
[[ "$tool" =~ ^(Write|Edit|MultiEdit)$ ]] || exit 0
file=$(echo "$input" | jq -r '.tool_input.file_path // empty')
[[ "$file" =~ \.(tsx|jsx|astro|css|ts)$ ]] || exit 0
content=$(echo "$input" | jq -r '.tool_input.new_string // .tool_input.content // empty')
[[ -n "$content" ]] || exit 0

# Smells of fighting a positioning system (not of using one):
#  - magic pixel offsets in arbitrary position utilities (left-[347px])
#  - z-index inflation (>= 3 digits)
#  - transform nudges with magic px
#  - !important position utilities
#  - position:fixed in components
PATTERN='((left|right|top|bottom|inset[a-z-]*)-\[[0-9]{2,}px\])|(\[(left|right|top|bottom|inset[^]:]*):[0-9]{2,}px\])|(z-\[[0-9]{3,}\])|(translate-[xy]-\[-?[0-9]+px\])|(!((absolute|relative|fixed|left|right|top|bottom|inset)))|(position:\s*fixed)'

if echo "$content" | grep -qE "$PATTERN"; then
  # Citation escape hatch: the SAME edit must say why this is the
  # library's/spec's own pattern, e.g.  /* cite: radix navigation-menu docs */
  if ! echo "$content" | grep -qiE '(cite:|per (radix|spec|capture|class-map|live probe))'; then
    peh_block "no-positioning-hacks" \
      "brute-force positioning in UI code (docs/rules.md: \"Work with the library\")" \
      "Magic px offsets / z-index inflation / transform nudges / !important position overrides are how library-fighting workarounds look." \
      "Read the library's docs for the INTENDED layout mechanism. If the library's own pattern genuinely needs this position, keep it AND add a citation in the same edit (e.g. /* cite: radix navigation-menu docs */). If you're overriding a library's positioning because it \"renders wrong\", that is the bug to understand — not paint over." \
      "(none — add a 'cite:' comment in the same edit if this IS the library's documented pattern)"
    exit 2
  fi
fi
exit 0
