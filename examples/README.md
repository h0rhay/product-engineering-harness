# Examples

## TodoTest

The harness was first validated end-to-end on a deliberately tiny project: the simplest possible browser-storage todo app. It exists to prove the harness works, not to be a product.

What it exercised:

- **Phase 1-5 (poc mode):** scaffold, add-todo, toggle-done, delete-todo, polish-edge-cases. Plain `harness ralph` with product-manager + engineer + tester.
- **Design phase (design enabled):** a Stripe Dashboard register applied across the app via art-director → designer → audit → engineer:
  - `06-stripe-redesign` — Geist + Geist Mono, tinted-neutral palette, one indigo accent, hairline rows. SkillUI distilled stripe.com into a reusable skill; reviewer caught a Tailwind-only-rule violation that the engineer had self-justified.
  - `07-empty-state` — a single `// nothing open` mono line. First slice to drive Pencil MCP from the designer sub-agent.
  - `08-done-section` — Open / Done section split. First slice composed via Pencil CLI Agent Mode with on-disk `.pen` persistence.
- **Graduation (full mode):** `harness graduate` flipped it to full; devops then created the private GitHub repo and opened the PR without manual git work.

The reference repo is private (it's a throwaway test), but the issue files, direction briefs, Pencil mockups, and reviewer evals it produced are the canonical illustration of the artefact shapes described in the root README.

## Recommended first run on your own project

```bash
cd ~/your-project
harness init
# open Claude Code
/grill-with-docs        # interview until the plan is sharp
/to-prd                 # synthesise the PRD
/to-issues              # vertical-slice it
harness status          # confirm what's ready
harness ralph 5         # let it build
```

Add `harness design on` before the ralph run if the work is visual. Run `harness graduate` when you're heading to production.
