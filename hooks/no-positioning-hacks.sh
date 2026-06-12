#!/usr/bin/env bash
# PreToolUse hook: blocks brute-force positioning workarounds in UI code.
# Rule (docs/rules.md): work WITH a library's positioning system, never
# against it. Absolute positioning that IMPLEMENTS a documented pattern is
# fine — and must say so with a citation comment (cite: <source>).
# Exit 2 = block; stderr is shown to the agent.

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
    cat >&2 <<'MSG'
BLOCKED by no-positioning-hacks hook (docs/rules.md: "Work with the library").

This edit contains brute-force positioning (magic px offsets / z-index
inflation / transform nudges / !important position overrides). These are
how library-fighting workarounds look, and they are forbidden.

Before reaching for positioning:
1. Read the library's docs for the component's INTENDED layout mechanism
   (e.g. Radix NavigationMenu: per-trigger anchoring = no Viewport,
   Content inside a relative Item — not viewport offset hacks).
2. If the intended mechanism genuinely requires this positioning, keep it
   AND add a citation in the same edit, e.g.:
     /* cite: radix navigation-menu — content anchors in relative item */
     /* cite: live probe — source uses fixed 48px cell padding at 1440 */
3. If you are overriding a library's own positioning because it "renders
   in the wrong place" — STOP. That is the bug to understand, not paint
   over. Escalate in your report instead of hacking around it.
MSG
    exit 2
  fi
fi
exit 0
