# CMA SDK surface (verified 2026-05-27 against platform.claude.com/docs/en/managed-agents)

Beta header: `managed-agents-2026-04-01`. SDK sets it automatically.

## Agent create

`client.beta.agents.create({ name, model, system, tools, mcp_servers?, multiagent? })`

- `tools[]` may include `{ type: "agent_toolset_20260401" }` for the bash/file/web toolset, or `{ type: "mcp_toolset", mcp_server_name: "..." }` to expose a single declared MCP server, or `{ type: "custom", ... }`.
- `mcp_servers[]` declares MCP servers available to the agent: `{ type: "url", name, url }`.
- `multiagent: { type: "coordinator", agents: [{ type: "agent", id }] }` declares the delegation roster. Max 20 entries. Depth 1 only. `{ type: "self" }` is allowed.
- Returns `{ id, version, ... }`. Versioned; passing the bare `id` as a session's `agent` uses the latest version.

## Environment create

`client.beta.environments.create({ name, config })` where `config = { type: "cloud", networking: { type: "unrestricted" } }` or `{ type: "self_hosted" }`. We use `cloud` here.

## Session create

`client.beta.sessions.create({ agent, environment_id, title?, vault_ids?, metadata? })`
- `agent` may be a string ID (latest version) or `{ type: "agent", id, version }` (pinned).
- `vault_ids: [vault.id]` injects MCP OAuth credentials at session scope. Vaults are referenced by ID; credentials never enter the agent's context.
- Returns `{ id, status, ... }`. Status starts at `idle`; session only begins work when an event is sent.

## Outcome event

After session create, post `user.define_outcome`:

```json
{
  "type": "user.define_outcome",
  "description": "<one-line goal>",
  "rubric": { "type": "text", "content": "<markdown body>" },
  "max_iterations": 2
}
```

Rubric may also be `{ "type": "file", "file_id": "<files-api id>" }`. `max_iterations` default 3, max 20.

## Events to listen for

Primary thread stream: `client.beta.sessions.events.stream(sessionId)`. Key event types we care about:

- `agent.message` — agent text output.
- `agent.tool_use` / `agent.mcp_tool_use` — observability.
- `session.thread_created` — a sub-agent thread was spawned (multiagent).
- `agent.thread_message_sent` / `agent.thread_message_received` — coordinator ↔ specialist messages.
- `span.outcome_evaluation_start` / `_ongoing` / `_end` — grader lifecycle.
- `session.status_idle` — session is done with the current outcome.

`span.outcome_evaluation_end.result` ∈ `{ satisfied, needs_revision, max_iterations_reached, failed, interrupted }`. Terminal results (`satisfied`, `max_iterations_reached`, `failed`, `interrupted`) transition the session to `idle`.

## Deliverables

Agent writes to `/mnt/session/outputs/` inside the container. Retrieve via:

```ts
const files = await client.beta.files.list({ scope_id: sessionId });
const content = await client.beta.files.download(files.data[0].id);
```

For this plan, the engineer agent doesn't write to `/mnt/session/outputs/`; it writes to the workpiece repo via the GitHub MCP server. The session's deliverable is the PR URL it produces.
