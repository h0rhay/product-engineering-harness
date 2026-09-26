# Cloud (Managed Agents) arm

Trigger a Claude Managed Agents multiagent session (coordinator + pm + engineer + reviewer) against a workpiece GitHub repo from the CLI.

## One-time setup

1. Create an Anthropic Credential Vault holding a GitHub OAuth credential bound to `https://api.githubcopilot.com/mcp/`. Copy the vault ID to `.env` as `CMA_GITHUB_VAULT_ID`.
2. Set `ANTHROPIC_API_KEY` in `.env`.

First `pnpm cloud:run` provisions the four CMA agents (`harness-coordinator`, `harness-pm`, `harness-engineer`, `harness-reviewer`) and a cloud environment, then caches their IDs in `cloud/.state.json` (gitignored). Subsequent runs reuse them.

## Run

    pnpm cloud:run --workpiece <owner/repo> --goal "<text>" --rubric <name>

Example (hello-world smoke test):

    pnpm cloud:run \
      --workpiece h0rhay/receipt-splitter \
      --goal "create HELLO.md saying hello world" \
      --rubric hello-world

The script prints the Anthropic Console URL on start. Watch the session there for thread-level detail.

## Available rubrics

- `hello-world` — sanity check; expects a `HELLO.md` file and an open PR.
- `calculator-mvp` — requires the workpiece repo to be scaffolded via `harness init` first.

## Adding a rubric

Drop a markdown file at `cloud/rubrics/<name>.md` with frontmatter (`name`, optional `max_iterations`) and a markdown body of explicit pass/fail criteria. The reviewer must cite evidence for each.

## Authoritative SDK surface

See `cloud/NOTES.md`.
