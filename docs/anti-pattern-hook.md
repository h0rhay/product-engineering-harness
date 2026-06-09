# Anti-pattern PreToolUse hook template

The harness's `CONTEXT_FILES` re-injection covers the rules; the
PreToolUse hook covers **specific anti-patterns about to be reintroduced
on this edit**. This doc describes the pattern so each project can add
its own targeted flags as the codebase's primitives are extracted.

## The mechanism

Claude Code's PreToolUse hook fires before every `Write` / `Edit`.
Configure it in `.claude/settings.json` and have it call a small Python
(or Bash) script:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "python3 \"$CLAUDE_PROJECT_DIR/.claude/hooks/engineering-standards.py\""
          }
        ]
      }
    ]
  }
}
```

The script reads the pending tool call from stdin, inspects the
incoming content, and emits `hookSpecificOutput.additionalContext` —
a soft reminder Claude sees before completing the edit. It is **not a
gate**; it cannot block the edit. Its job is to surface anti-patterns
early so the agent course-corrects in the same turn.

## The shape of a flag

A flag is two things: a **detection** (string match, regex, file-path
filter) and a **message** (short, prescriptive, names the primitive
to use instead).

```python
FLAG_INLINE_BTN = """\

⚠ This edit writes a raw `.btn` / `.btn--*` class string inline. STOP
and use the <Button variant=... size=...> primitive
(src/components/Button.tsx). The primitive owns the BEM class
composition; inline duplication is a composition-rule violation."""

# ... later in main() ...

new_content = (tool_input.get("content") or tool_input.get("new_string") or "")
nc_low = new_content.lower()

if 'btn btn--' in nc_low or 'class="btn ' in nc_low or "class='btn " in nc_low:
    if "button.tsx" not in path.lower() and "global.css" not in path.lower():
        message += FLAG_INLINE_BTN
```

Three pieces matter:

1. **Detection string is the literal anti-pattern signature** — the exact
   thing the agent might be about to type. Not a vague concept; the raw
   class-substring or import name.
2. **Path exemption** — the primitive file itself and the foundational
   CSS file must be exempt, because they're allowed to use the BEM
   class. Otherwise the hook fires on its own source-of-truth.
3. **Message names the alternative concretely** — the primitive's path
   and its API. Not "use a primitive" but `<Button variant=... size=...>`.

## When to add a flag

Add a flag the moment a primitive is extracted that replaces an inline
class string. The lifecycle:

1. **Slice N:** the codebase has 4 inline `class="btn btn--quaternary"`.
   No primitive yet.
2. **Slice N+1:** extract `<Button variant="quaternary">`; convert the 4
   callsites. **Add `FLAG_INLINE_BTN` in the same slice.**
3. **Slice N+2:** an agent tries to write `class="btn btn--quaternary"`
   in new code. The hook fires before the edit completes; the agent
   sees the flag, uses `<Button>` instead.

Without step 2, slice N+2 reintroduces the duplication and primitive
extraction has to happen a second time.

## Existing built-in flags

The harness ships two flags as part of the example hook
(`.claude/hooks/engineering-standards.py` template):

- **`FLAG_ISLAND`** — fires when an edit adds a `client:*` directive.
  Reminds the agent to confirm the interactivity genuinely needs JS;
  if it's layout/overflow/snap-scrolling/show-hide, use CSS instead.
- **`FLAG_SWIPER`** — fires when an edit references Swiper. Swiper is
  only justified for true draggable carousels with programmatic control;
  a static info row should be a pure-CSS Reel (scroll-snap + overflow).

These are project-agnostic. Anything beyond them is project-specific
and lives in the project's own hook file.

## Don't over-flag

The hook is a soft reminder. If it fires on every edit, agents start
ignoring it. Rule of thumb: a flag should fire **only when an edit is
about to violate a binding rule that has a named primitive alternative**.
"Could be cleaner" doesn't qualify. "Reintroducing the inline class
string that we extracted into `<Button>` two slices ago" does.
