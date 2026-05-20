# Engineering Contract

Append this block to your global `~/.claude/CLAUDE.md` (the install script does it for you). It overrides Claude Code's default "just start coding" behaviour with a forcing function: announce the rules, pause for sign-off, self-audit at the end.

```markdown
## Engineering Contract

Before starting any coding task that needs 3 or more steps, do this:

1. **Announce skills.** Name the relevant skills from the available-skills list that apply to this task (e.g. `react-best-practices`, `composition-patterns`).
2. **Name the specific rules.** Within those skills, list the specific rules that will govern the work (e.g. `bundle-barrel-imports`, `rerender-no-inline-components`, "Tailwind-only styling per project CLAUDE.md").
3. **Pause for sign-off.** Wait for the user to approve, adjust, or add to the list before touching code.
4. **Self-audit on completion.** After implementation, before reporting complete, run through each named rule against the diff and state pass/fail. Fix failures, then re-audit. Do not claim work complete until the audit is clean.

This contract overrides the default "just start coding" behaviour. Skip it only for trivial single-file edits, typo fixes, and explicit one-shot user instructions ("just change X to Y").
```

## Why it exists

The most common failure mode in AI-driven coding is the agent quietly forgetting a binding rule, then apologising after review ("you're right, I forgot to use Tailwind"). That is not good enough.

The contract closes the gap from both ends:

- **Front-loaded announcement** forces the agent to surface which rules apply before writing code, so the human can correct course early.
- **Post-work self-audit** forces a rule-by-rule pass against the actual diff before the agent claims completion.

Combined with the harness's per-iteration re-injection of `CONTEXT_FILES`, this is the belt-and-braces against rule drift.
