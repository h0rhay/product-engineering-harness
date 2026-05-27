---
title: CMA arm for product-engineering-harness
date: 2026-05-27
status: design-approved
type: design-spec
---

# CMA Arm for the Product-Engineering Harness

## Goal

Add a Claude Managed Agents (CMA) execution mode to the existing local-only harness, proving the end-to-end cloud loop (coordinator + specialists + native outcome rubric + retry) on a disposable workpiece. The receipt-splitter calculator is the first workpiece; the calculator itself is incidental.

## Non-goals

- Building a polished calculator product.
- Adding remote triggers (Telegram, Slack, GitHub-issue webhooks).
- Multi-tenant or per-client configuration.
- Memory Stores, self-hosted sandboxes, or any client-facing surface.

## Architecture

Two repos, three specialist roles, one trigger.

**Repos:**
- `product-engineering-harness` gains a `cloud/` directory holding the CMA configuration and trigger script.
- `receipt-splitter` is a fresh, empty workpiece repo. CMA clones it, works on a branch, opens a PR. Local `harness init` scaffolds it (React + TypeScript + Tailwind + Vitest + Playwright) before CMA touches it.

**Specialist roles (native CMA `multiagent: coordinator` mode):**
- **Coordinator** (Opus or Sonnet): receives the goal, fans out, decides who runs next.
- **`pm`** (Sonnet): turns the goal text into `spec.md` in the workpiece repo.
- **`engineer`** (Sonnet): reads `spec.md`, writes code, commits.
- **`reviewer`** (Sonnet): grades output against the rubric. If fail, coordinator re-runs the engineer with reviewer notes. Cap at N=2 retries.

**Trigger:** `pnpm cloud:run --workpiece <repo-url> --goal "<text>" --rubric <name>`. Single TS script using `@anthropic-ai/sdk`. Creates the session, streams events to stdout, prints the Console URL.

**Auth:** GitHub PAT stored in Anthropic Credential Vault, bound to the coordinator. Specialists inherit. No secret on local disk.

**Per-tool permissions:**
- `pm`: read repo, write `spec.md`. Auto-execute.
- `engineer`: read repo, write code, run `pnpm install/test/build`. Auto-execute reads and tests; writes flow through a PR (no direct push to main).
- `reviewer`: read repo, run `pnpm test`, read CI logs. Read-only. Auto-execute.

**Observability:** Anthropic Console. No custom dashboard.

## Division of labour

- **Harness owns:** repo scaffolding (`harness init`), conventions, skills, CLAUDE.md contract, the `cloud/` config that defines the specialists.
- **CMA owns:** feature implementation on top of an already-build-ready repo. Specialists inherit the contract from the workpiece repo's CLAUDE.md.

## Outcome rubrics

Rubrics are markdown files at `cloud/rubrics/`. Each item is a pass/fail check the reviewer must justify with evidence (file path or command output).

### `hello-world.md`
1. A file `HELLO.md` exists at repo root.
2. It contains the string "hello world" (case-insensitive).
3. Reviewer justification cites the file path.

### `calculator-mvp.md`
(Applies only after `harness init` has scaffolded the repo.)
1. `pnpm test` exits 0 after engineer's changes.
2. A new Vitest test covers the split calculation.
3. App renders three inputs (total, people, tip %) and one output (per-person amount). Playwright smoke test passes.
4. No new axe-core accessibility violations introduced.

## Acceptance criteria for the harness change

Harness repo gains:
1. `cloud/` directory containing:
   - `agents/coordinator.md`, `agents/pm.md`, `agents/engineer.md`, `agents/reviewer.md`. One markdown spec per role (system prompt, tool scopes, model tier).
   - `rubrics/hello-world.md`, `rubrics/calculator-mvp.md`.
   - `run.ts`. The trigger script.
   - `README.md`. How to use it.
2. `pnpm cloud:run` script wired in `package.json`.
3. `@anthropic-ai/sdk` added as a dependency.
4. `.env.example` documenting `ANTHROPIC_API_KEY` and `CMA_CREDENTIAL_VAULT_ID`.
5. Existing local-harness behaviour unchanged. CMA is purely additive.

## Proof-of-life test (manual, one-time)

1. Create empty `receipt-splitter` repo on GitHub.
2. Run `pnpm cloud:run --workpiece <url> --goal "create HELLO.md saying hello world" --rubric hello-world`.
3. Session completes, reviewer passes, PR opens on `receipt-splitter`. Merge it.
4. Run `harness init` against `receipt-splitter` locally to scaffold the React app.
5. Run `pnpm cloud:run --workpiece <url> --goal "implement the receipt splitter MVP per the spec" --rubric calculator-mvp`. Session completes, PR opens. Human reviews and merges.

## Failure modes

- **Session timeout:** script exits non-zero, Console URL printed for diagnosis.
- **Reviewer fails N times:** coordinator opens draft PR labelled `needs-human`. Script reports `needs-human`.
- **Engineer cannot satisfy a rubric item:** reviewer must name the item and quote the failing evidence; that text lands in the PR description.

## Open questions for implementation

- Exact SDK surface for `multiagent: coordinator` + `user.define_outcome` (confirm against current Anthropic docs at implementation time, not from memory).
- Whether specialist definitions are markdown system prompts only, or include structured tool-scope blocks (depends on SDK surface).
- Whether Credential Vault setup is API-driven or Console-only (affects whether onboarding can be scripted).

These are deliberately deferred to implementation, not blockers for this design.
