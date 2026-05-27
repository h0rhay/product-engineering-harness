# CMA Harness Arm Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `cloud/` arm to the product-engineering-harness that triggers a Claude Managed Agents (CMA) multiagent session (coordinator + pm/engineer/reviewer specialists + native outcome rubric) against a workpiece repo from a CLI command.

**Architecture:** A new `cloud/` directory holds agent definitions (markdown source-of-truth) and rubric definitions (markdown), plus a TypeScript trigger script (`run.ts`). The script creates four CMA agents (or looks them up if already provisioned), wires the coordinator's `multiagent.agents` roster, then creates a session, sends a `user.define_outcome` event, streams session-thread events to stdout, and exits when the outcome resolves. No changes to existing local-harness behaviour. GitHub access is via the GitHub MCP server on the engineer agent, authenticated by an Anthropic Credential Vault attached to the session.

**Tech Stack:** TypeScript (strict), `@anthropic-ai/sdk` (with `managed-agents-2026-04-01` beta header set automatically by the SDK), Vitest for unit tests, pnpm. CMA primitives used: `multiagent: coordinator`, `vault_ids`, `user.define_outcome` (text rubric), GitHub MCP server, `agent_toolset_20260401`.

**Source spec:** `docs/superpowers/specs/2026-05-27-cma-harness-arm-design.md`.

**SDK surface verified against:**
- `/docs/en/managed-agents/quickstart`
- `/docs/en/managed-agents/sessions`
- `/docs/en/managed-agents/multi-agent`
- `/docs/en/managed-agents/define-outcomes`
- `/docs/en/managed-agents/tools`
- `/docs/en/managed-agents/self-hosted-sandboxes`

---

## File structure

Files to create in the harness repo:

- `cloud/agents/coordinator.md` — coordinator agent: model, system prompt, no tools (only delegates).
- `cloud/agents/pm.md` — pm specialist: model, system prompt, `agent_toolset_20260401`.
- `cloud/agents/engineer.md` — engineer specialist: model, system prompt, `agent_toolset_20260401` + GitHub MCP server.
- `cloud/agents/reviewer.md` — reviewer specialist: model, system prompt, `agent_toolset_20260401`, read-only behaviour by convention (no MCP).
- `cloud/rubrics/hello-world.md` — hello-world rubric (inline text body).
- `cloud/rubrics/calculator-mvp.md` — calculator-mvp rubric (inline text body).
- `cloud/run.ts` — CLI trigger script.
- `cloud/lib/args.ts` — pure function: parse CLI args.
- `cloud/lib/load-agents.ts` — pure function: read agent markdown files → typed `AgentDef` objects.
- `cloud/lib/load-rubric.ts` — pure function: read a rubric markdown file → typed `Rubric` object.
- `cloud/lib/ensure-agents.ts` — idempotent provisioner: look up existing CMA agents by name, create if missing, return their IDs. Persists a tiny `cloud/.state.json` of `{ name → id }` so we don't list-and-search on every run.
- `cloud/lib/__tests__/args.test.ts`
- `cloud/lib/__tests__/load-agents.test.ts`
- `cloud/lib/__tests__/load-rubric.test.ts`
- `cloud/README.md`
- `cloud/NOTES.md` — verified CMA SDK surface (authored from this plan, not deferred).
- `.env.example`

Files to modify:
- `package.json` — `cloud:run` script, `@anthropic-ai/sdk` dep.
- `README.md` — link to `cloud/README.md`.

Splitting `run.ts` from `lib/*` keeps the side-effect entry point thin and the parseable bits unit-testable.

---

## Task 1: Initialise `cloud/` skeleton and tooling

**Files:**
- Create: `cloud/.gitkeep`
- Modify: `package.json` (root)
- Create: `tsconfig.json` (root, if missing)

- [ ] **Step 1: Confirm the repo has a `package.json` at root**

```bash
cat package.json | head -20
```
Expected: A package.json exists. If not, initialise it (`pnpm init`) and add `"type": "module"`, `"private": true`.

- [ ] **Step 2: Install dependencies**

```bash
pnpm add @anthropic-ai/sdk
pnpm add -D typescript tsx vitest @types/node
```

- [ ] **Step 3: Create `tsconfig.json` if missing**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "resolveJsonModule": true,
    "types": ["node", "vitest/globals"]
  },
  "include": ["cloud/**/*.ts"]
}
```

- [ ] **Step 4: Wire scripts in `package.json`**

Add to `scripts`:
```json
"cloud:run": "tsx cloud/run.ts",
"test": "vitest run"
```

- [ ] **Step 5: Create the directory skeleton**

```bash
mkdir -p cloud/agents cloud/rubrics cloud/lib/__tests__
touch cloud/.gitkeep
echo "cloud/.state.json" >> .gitignore
```

- [ ] **Step 6: Commit**

```bash
git add package.json pnpm-lock.yaml tsconfig.json cloud/.gitkeep .gitignore
git commit -m "chore: scaffold cloud/ directory and tooling"
```

---

## Task 2: Author `cloud/NOTES.md` from verified SDK surface

**Files:**
- Create: `cloud/NOTES.md`

- [ ] **Step 1: Write the verified surface notes**

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add cloud/NOTES.md
git commit -m "docs(cloud): pin verified CMA SDK surface"
```

---

## Task 3: Write agent definition markdown files

Markdown is the source-of-truth; the loader (Task 5) parses frontmatter + body into SDK arguments. The coordinator's `multiagent.agents` array is filled in at runtime from the IDs returned by Task 6's provisioner.

**Files:**
- Create: `cloud/agents/coordinator.md`
- Create: `cloud/agents/pm.md`
- Create: `cloud/agents/engineer.md`
- Create: `cloud/agents/reviewer.md`

- [ ] **Step 1: Write `cloud/agents/coordinator.md`**

```markdown
---
name: harness-coordinator
role: coordinator
model: claude-sonnet-4-6
tools: []
multiagent_roster: [harness-pm, harness-engineer, harness-reviewer]
---

You coordinate a session that ends with a PR opened on the workpiece repo via the engineer's GitHub MCP server. Delegate in this order:

1. Send the user goal to the `harness-pm` agent. It will produce `spec.md` at the repo root.
2. Send the spec path to the `harness-engineer` agent. It will implement and commit on a working branch.
3. Send the rubric and the engineer's branch to the `harness-reviewer` agent. It will report pass/fail per criterion with evidence.

If the outcome grader returns `needs_revision`, delegate the engineer again with the grader's notes. You do not perform grading yourself; the platform grader does that. Do not write to the repo directly.
```

- [ ] **Step 2: Write `cloud/agents/pm.md`**

```markdown
---
name: harness-pm
role: pm
model: claude-sonnet-4-6
tools: [agent_toolset_20260401]
---

Turn the coordinator's goal into `spec.md` at the workpiece repo root. The spec must list pass/fail acceptance criteria the engineer can implement against and the reviewer can verify with evidence (file paths or command output). Keep it under 200 words. Commit `spec.md` on the working branch. Do not invent scope the coordinator did not ask for.
```

- [ ] **Step 3: Write `cloud/agents/engineer.md`**

```markdown
---
name: harness-engineer
role: engineer
model: claude-sonnet-4-6
tools: [agent_toolset_20260401, mcp_toolset:github]
mcp_servers:
  - name: github
    url: https://api.githubcopilot.com/mcp/
---

Read `spec.md` from the workpiece repo. Implement the acceptance criteria. Commit on a working branch and open a PR via the GitHub MCP server. Run `pnpm test` (or the repo's test command) before signalling done; if tests fail, fix and re-run before opening the PR. Follow conventions in the workpiece repo's `CLAUDE.md` if present. Never push directly to `main`.
```

- [ ] **Step 4: Write `cloud/agents/reviewer.md`**

```markdown
---
name: harness-reviewer
role: reviewer
model: claude-sonnet-4-6
tools: [agent_toolset_20260401]
---

Grade the engineer's output against the rubric the coordinator passed you. For each rubric item, output: pass/fail, the file path or command output that justifies the verdict, and a one-line note. Do not write to the repo. If any item fails, return failure with notes so the platform grader can decide whether to iterate.
```

- [ ] **Step 5: Commit**

```bash
git add cloud/agents/
git commit -m "feat(cloud): add specialist agent definitions"
```

---

## Task 4: Write rubric files

**Files:**
- Create: `cloud/rubrics/hello-world.md`
- Create: `cloud/rubrics/calculator-mvp.md`

- [ ] **Step 1: Write `cloud/rubrics/hello-world.md`**

```markdown
---
name: hello-world
max_iterations: 2
---

# Hello-world rubric

1. A file `HELLO.md` exists at the workpiece repo root on the engineer's working branch.
2. The file contains the string "hello world" (case-insensitive match).
3. A PR is open against `main` containing the change. The reviewer cites the PR URL.
```

- [ ] **Step 2: Write `cloud/rubrics/calculator-mvp.md`**

```markdown
---
name: calculator-mvp
max_iterations: 2
---

# Calculator MVP rubric

Applies only to a workpiece repo that has already been scaffolded via `harness init`.

1. `pnpm test` exits 0 after the engineer's changes (reviewer cites the command output).
2. A new Vitest test covers the per-person split calculation (reviewer cites the test file path).
3. The app renders three inputs (total, number of people, tip %) and one output (per-person amount). A Playwright smoke test in the engineer's branch verifies this (reviewer cites the test file path).
4. No new axe-core accessibility violations are introduced compared to `main` (reviewer cites the axe report).
```

`max_iterations` in rubric frontmatter overrides the SDK default (3); the loader passes it through to `user.define_outcome.max_iterations`.

- [ ] **Step 3: Commit**

```bash
git add cloud/rubrics/
git commit -m "feat(cloud): add hello-world and calculator-mvp rubrics"
```

---

## Task 5: Write the CLI arg parser (TDD)

**Files:**
- Create: `cloud/lib/args.ts`
- Create: `cloud/lib/__tests__/args.test.ts`

- [ ] **Step 1: Write the failing test**

```typescript
import { describe, it, expect } from "vitest";
import { parseArgs } from "../args";

describe("parseArgs", () => {
  it("parses required flags", () => {
    const result = parseArgs([
      "--workpiece", "owner/repo",
      "--goal", "do the thing",
      "--rubric", "hello-world",
    ]);
    expect(result).toEqual({
      workpiece: "owner/repo",
      goal: "do the thing",
      rubric: "hello-world",
    });
  });

  it("throws when --workpiece is missing", () => {
    expect(() => parseArgs(["--goal", "x", "--rubric", "hello-world"]))
      .toThrow(/workpiece/);
  });

  it("throws when --goal is missing", () => {
    expect(() => parseArgs(["--workpiece", "x", "--rubric", "hello-world"]))
      .toThrow(/goal/);
  });

  it("throws when --rubric is missing", () => {
    expect(() => parseArgs(["--workpiece", "x", "--goal", "y"]))
      .toThrow(/rubric/);
  });
});
```

`--workpiece` is `owner/repo` (e.g. `h0rhay/receipt-splitter`) because the GitHub MCP server expects that shape. We don't pass URLs through.

- [ ] **Step 2: Run test to verify it fails**

```bash
pnpm test cloud/lib/__tests__/args.test.ts
```
Expected: FAIL with "Cannot find module '../args'".

- [ ] **Step 3: Implement `cloud/lib/args.ts`**

```typescript
export interface CloudRunArgs {
  workpiece: string;
  goal: string;
  rubric: string;
}

export function parseArgs(argv: string[]): CloudRunArgs {
  const get = (flag: string): string | undefined => {
    const idx = argv.indexOf(flag);
    return idx >= 0 && idx + 1 < argv.length ? argv[idx + 1] : undefined;
  };
  const workpiece = get("--workpiece");
  const goal = get("--goal");
  const rubric = get("--rubric");
  if (!workpiece) throw new Error("--workpiece is required (owner/repo)");
  if (!goal) throw new Error("--goal is required");
  if (!rubric) throw new Error("--rubric is required");
  return { workpiece, goal, rubric };
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
pnpm test cloud/lib/__tests__/args.test.ts
```
Expected: PASS, 4/4 tests green.

- [ ] **Step 5: Commit**

```bash
git add cloud/lib/args.ts cloud/lib/__tests__/args.test.ts
git commit -m "feat(cloud): add CLI arg parser"
```

---

## Task 6: Write the agent loader (TDD)

**Files:**
- Create: `cloud/lib/load-agents.ts`
- Create: `cloud/lib/__tests__/load-agents.test.ts`

The loader converts each agent markdown file into a structured object the provisioner (Task 7) can hand to `client.beta.agents.create`.

- [ ] **Step 1: Write the failing test**

```typescript
import { describe, it, expect } from "vitest";
import { loadAgents } from "../load-agents";
import { mkdtempSync, writeFileSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

describe("loadAgents", () => {
  it("loads all four specialist files with frontmatter parsed", () => {
    const dir = mkdtempSync(join(tmpdir(), "agents-"));
    mkdirSync(join(dir, "agents"));
    const files: Record<string, string> = {
      "coordinator.md": `---\nname: harness-coordinator\nrole: coordinator\nmodel: claude-sonnet-4-6\ntools: []\nmultiagent_roster: [harness-pm, harness-engineer, harness-reviewer]\n---\n\nCoord body.\n`,
      "pm.md": `---\nname: harness-pm\nrole: pm\nmodel: claude-sonnet-4-6\ntools: [agent_toolset_20260401]\n---\n\nPM body.\n`,
      "engineer.md": `---\nname: harness-engineer\nrole: engineer\nmodel: claude-sonnet-4-6\ntools: [agent_toolset_20260401, mcp_toolset:github]\nmcp_servers:\n  - name: github\n    url: https://api.githubcopilot.com/mcp/\n---\n\nEng body.\n`,
      "reviewer.md": `---\nname: harness-reviewer\nrole: reviewer\nmodel: claude-sonnet-4-6\ntools: [agent_toolset_20260401]\n---\n\nRev body.\n`,
    };
    for (const [f, body] of Object.entries(files)) writeFileSync(join(dir, "agents", f), body);

    const agents = loadAgents(join(dir, "agents"));
    expect(agents.coordinator.name).toBe("harness-coordinator");
    expect(agents.coordinator.multiagentRoster).toEqual(["harness-pm", "harness-engineer", "harness-reviewer"]);
    expect(agents.engineer.mcpServers).toEqual([{ name: "github", url: "https://api.githubcopilot.com/mcp/" }]);
    expect(agents.engineer.tools).toContain("mcp_toolset:github");
    expect(agents.pm.systemPrompt).toContain("PM body");
  });

  it("throws if a required role file is missing", () => {
    const dir = mkdtempSync(join(tmpdir(), "agents-"));
    mkdirSync(join(dir, "agents"));
    writeFileSync(
      join(dir, "agents", "coordinator.md"),
      `---\nname: harness-coordinator\nrole: coordinator\nmodel: x\n---\n\nBody.\n`,
    );
    expect(() => loadAgents(join(dir, "agents"))).toThrow(/pm/);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
pnpm test cloud/lib/__tests__/load-agents.test.ts
```
Expected: FAIL with "Cannot find module '../load-agents'".

- [ ] **Step 3: Implement `cloud/lib/load-agents.ts`**

```typescript
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { parse as parseYaml } from "yaml";

export interface McpServer {
  name: string;
  url: string;
}

export interface AgentDef {
  name: string;
  role: "coordinator" | "pm" | "engineer" | "reviewer";
  model: string;
  tools: string[];
  mcpServers: McpServer[];
  multiagentRoster?: string[];
  systemPrompt: string;
}

export interface AgentSet {
  coordinator: AgentDef;
  pm: AgentDef;
  engineer: AgentDef;
  reviewer: AgentDef;
}

const REQUIRED_ROLES = ["coordinator", "pm", "engineer", "reviewer"] as const;

function parseAgentFile(path: string): AgentDef {
  const raw = readFileSync(path, "utf8");
  const match = raw.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
  if (!match) throw new Error(`Invalid agent file (no frontmatter): ${path}`);
  const fm = parseYaml(match[1]) as Record<string, unknown>;
  const tools = (fm.tools as string[] | undefined) ?? [];
  const mcpServers = ((fm.mcp_servers as McpServer[] | undefined) ?? []);
  return {
    name: String(fm.name),
    role: fm.role as AgentDef["role"],
    model: String(fm.model),
    tools,
    mcpServers,
    multiagentRoster: fm.multiagent_roster as string[] | undefined,
    systemPrompt: match[2].trim(),
  };
}

export function loadAgents(agentsDir: string): AgentSet {
  const out: Partial<AgentSet> = {};
  for (const role of REQUIRED_ROLES) {
    try {
      (out as Record<string, AgentDef>)[role] = parseAgentFile(join(agentsDir, `${role}.md`));
    } catch (e) {
      throw new Error(`Failed to load ${role}: ${(e as Error).message}`);
    }
  }
  return out as AgentSet;
}
```

Add `yaml` dep:

```bash
pnpm add yaml
```

- [ ] **Step 4: Run test to verify it passes**

```bash
pnpm test cloud/lib/__tests__/load-agents.test.ts
```
Expected: PASS, 2/2 tests green.

- [ ] **Step 5: Commit**

```bash
git add cloud/lib/load-agents.ts cloud/lib/__tests__/load-agents.test.ts package.json pnpm-lock.yaml
git commit -m "feat(cloud): add agent loader"
```

---

## Task 7: Write the agent provisioner

The provisioner takes the four `AgentDef`s, ensures each exists in the CMA workspace (creating if missing), and returns a map `{ name → cma_agent_id }`. The coordinator agent is created last because its `multiagent.agents` needs the specialists' IDs.

**Files:**
- Create: `cloud/lib/ensure-agents.ts`

- [ ] **Step 1: Implement `cloud/lib/ensure-agents.ts`**

```typescript
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import Anthropic from "@anthropic-ai/sdk";
import type { AgentSet, AgentDef, McpServer } from "./load-agents.js";

const STATE_PATH = "cloud/.state.json";

interface StateFile {
  agents: Record<string, string>;
}

function loadState(): StateFile {
  if (!existsSync(STATE_PATH)) return { agents: {} };
  return JSON.parse(readFileSync(STATE_PATH, "utf8")) as StateFile;
}

function saveState(s: StateFile): void {
  writeFileSync(STATE_PATH, JSON.stringify(s, null, 2));
}

function buildTools(def: AgentDef): unknown[] {
  return def.tools.map((t) => {
    if (t === "agent_toolset_20260401") return { type: "agent_toolset_20260401" };
    if (t.startsWith("mcp_toolset:")) return { type: "mcp_toolset", mcp_server_name: t.slice("mcp_toolset:".length) };
    throw new Error(`Unknown tool spec: ${t}`);
  });
}

function buildMcpServers(servers: McpServer[]): unknown[] {
  return servers.map((s) => ({ type: "url", name: s.name, url: s.url }));
}

async function createSpecialist(client: Anthropic, def: AgentDef): Promise<string> {
  const agent = await (client as any).beta.agents.create({
    name: def.name,
    model: def.model,
    system: def.systemPrompt,
    tools: buildTools(def),
    ...(def.mcpServers.length > 0 ? { mcp_servers: buildMcpServers(def.mcpServers) } : {}),
  });
  return agent.id as string;
}

async function createCoordinator(
  client: Anthropic,
  def: AgentDef,
  rosterIds: string[],
): Promise<string> {
  const agent = await (client as any).beta.agents.create({
    name: def.name,
    model: def.model,
    system: def.systemPrompt,
    tools: buildTools(def),
    multiagent: {
      type: "coordinator",
      agents: rosterIds.map((id) => ({ type: "agent", id })),
    },
  });
  return agent.id as string;
}

export async function ensureAgents(client: Anthropic, agents: AgentSet): Promise<Record<string, string>> {
  const state = loadState();

  // Provision specialists first.
  for (const def of [agents.pm, agents.engineer, agents.reviewer]) {
    if (!state.agents[def.name]) {
      state.agents[def.name] = await createSpecialist(client, def);
      saveState(state);
    }
  }

  // Coordinator references specialists by ID.
  if (!state.agents[agents.coordinator.name]) {
    const rosterIds = (agents.coordinator.multiagentRoster ?? []).map((rosterName) => {
      const id = state.agents[rosterName];
      if (!id) throw new Error(`Coordinator roster member not provisioned: ${rosterName}`);
      return id;
    });
    state.agents[agents.coordinator.name] = await createCoordinator(client, agents.coordinator, rosterIds);
    saveState(state);
  }

  return state.agents;
}
```

The `as any` casts on the SDK are present because the beta-namespaced multiagent types weren't in the SDK version we have at write time. If the types are available when implementing, remove the casts.

`cloud/.state.json` is gitignored (Task 1, step 5) because it holds workspace-specific CMA agent IDs.

- [ ] **Step 2: Commit**

```bash
git add cloud/lib/ensure-agents.ts
git commit -m "feat(cloud): idempotent CMA agent provisioner"
```

---

## Task 8: Write the rubric loader (TDD)

**Files:**
- Create: `cloud/lib/load-rubric.ts`
- Create: `cloud/lib/__tests__/load-rubric.test.ts`

- [ ] **Step 1: Write the failing test**

```typescript
import { describe, it, expect } from "vitest";
import { loadRubric } from "../load-rubric";
import { mkdtempSync, writeFileSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

describe("loadRubric", () => {
  it("loads a rubric by name", () => {
    const dir = mkdtempSync(join(tmpdir(), "rubrics-"));
    mkdirSync(join(dir, "rubrics"));
    writeFileSync(
      join(dir, "rubrics", "hello-world.md"),
      `---\nname: hello-world\nmax_iterations: 2\n---\n\n# Hello-world rubric\n\n1. A file exists.\n2. It contains text.\n`,
    );
    const rubric = loadRubric(join(dir, "rubrics"), "hello-world");
    expect(rubric.name).toBe("hello-world");
    expect(rubric.maxIterations).toBe(2);
    expect(rubric.body).toContain("Hello-world rubric");
  });

  it("throws if rubric does not exist", () => {
    const dir = mkdtempSync(join(tmpdir(), "rubrics-"));
    mkdirSync(join(dir, "rubrics"));
    expect(() => loadRubric(join(dir, "rubrics"), "nope")).toThrow(/nope/);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
pnpm test cloud/lib/__tests__/load-rubric.test.ts
```
Expected: FAIL with "Cannot find module '../load-rubric'".

- [ ] **Step 3: Implement `cloud/lib/load-rubric.ts`**

```typescript
import { readFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import { parse as parseYaml } from "yaml";

export interface Rubric {
  name: string;
  maxIterations: number;
  body: string;
}

export function loadRubric(rubricsDir: string, name: string): Rubric {
  const path = join(rubricsDir, `${name}.md`);
  if (!existsSync(path)) throw new Error(`Rubric not found: ${name}`);
  const raw = readFileSync(path, "utf8");
  const match = raw.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
  if (!match) throw new Error(`Invalid rubric file (no frontmatter): ${path}`);
  const fm = parseYaml(match[1]) as Record<string, unknown>;
  const maxIterations = typeof fm.max_iterations === "number" ? fm.max_iterations : 3;
  if (maxIterations < 1 || maxIterations > 20) {
    throw new Error(`max_iterations must be between 1 and 20 (got ${maxIterations})`);
  }
  return {
    name: String(fm.name ?? name),
    maxIterations,
    body: match[2].trim(),
  };
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
pnpm test cloud/lib/__tests__/load-rubric.test.ts
```
Expected: PASS, 2/2 tests green.

- [ ] **Step 5: Commit**

```bash
git add cloud/lib/load-rubric.ts cloud/lib/__tests__/load-rubric.test.ts
git commit -m "feat(cloud): add rubric loader"
```

---

## Task 9: Write `cloud/run.ts` (entry point)

The script orchestrates: parse args → load agents and rubric → ensure CMA agents are provisioned → create environment if not cached → create session with `vault_ids` → send `user.define_outcome` event → stream primary thread events → exit on `session.status_idle` or terminal outcome result.

**Files:**
- Create: `cloud/run.ts`

- [ ] **Step 1: Implement `cloud/run.ts`**

```typescript
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import Anthropic from "@anthropic-ai/sdk";
import { parseArgs } from "./lib/args.js";
import { loadAgents } from "./lib/load-agents.js";
import { loadRubric } from "./lib/load-rubric.js";
import { ensureAgents } from "./lib/ensure-agents.js";

const here = dirname(fileURLToPath(import.meta.url));
const STATE_PATH = join(here, ".state.json");

interface StateFile {
  agents: Record<string, string>;
  environmentId?: string;
}

function loadState(): StateFile {
  return existsSync(STATE_PATH) ? JSON.parse(readFileSync(STATE_PATH, "utf8")) : { agents: {} };
}

function saveState(s: StateFile): void {
  writeFileSync(STATE_PATH, JSON.stringify(s, null, 2));
}

async function ensureEnvironment(client: Anthropic): Promise<string> {
  const state = loadState();
  if (state.environmentId) return state.environmentId;
  const env = await (client as any).beta.environments.create({
    name: "harness-cloud",
    config: { type: "cloud", networking: { type: "unrestricted" } },
  });
  saveState({ ...state, environmentId: env.id });
  return env.id as string;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));

  if (!process.env.ANTHROPIC_API_KEY) throw new Error("ANTHROPIC_API_KEY is not set");
  const vaultId = process.env.CMA_GITHUB_VAULT_ID;
  if (!vaultId) throw new Error("CMA_GITHUB_VAULT_ID is not set");

  const agents = loadAgents(join(here, "agents"));
  const rubric = loadRubric(join(here, "rubrics"), args.rubric);
  const client = new Anthropic();

  const agentIds = await ensureAgents(client, agents);
  const coordinatorId = agentIds[agents.coordinator.name];
  if (!coordinatorId) throw new Error("Coordinator was not provisioned");

  const environmentId = await ensureEnvironment(client);

  const session = await (client as any).beta.sessions.create({
    agent: coordinatorId,
    environment_id: environmentId,
    vault_ids: [vaultId],
    title: `harness:${args.rubric}:${args.workpiece}`,
    metadata: { workpiece: args.workpiece, rubric: args.rubric },
  });

  console.log(`Session: ${session.id}`);
  console.log(`Console: https://console.anthropic.com/sessions/${session.id}`);

  const stream = await (client as any).beta.sessions.events.stream(session.id);

  await (client as any).beta.sessions.events.send(session.id, {
    events: [
      {
        type: "user.define_outcome",
        description: `Goal: ${args.goal}\nWorkpiece: ${args.workpiece}`,
        rubric: { type: "text", content: rubric.body },
        max_iterations: rubric.maxIterations,
      },
    ],
  });

  let outcomeResult: string | undefined;
  for await (const event of stream) {
    const e = event as { type: string; result?: string; content?: { text?: string }[]; agent_name?: string };
    switch (e.type) {
      case "agent.message":
        for (const block of e.content ?? []) if (block.text) process.stdout.write(block.text);
        break;
      case "session.thread_created":
        console.log(`\n[thread] ${e.agent_name} started`);
        break;
      case "agent.tool_use":
      case "agent.mcp_tool_use":
        // Quiet by default; uncomment to debug:
        // console.log(`[tool] ${(e as any).name}`);
        break;
      case "span.outcome_evaluation_start":
        console.log(`\n[grader] iteration ${(e as any).iteration} starting`);
        break;
      case "span.outcome_evaluation_end":
        outcomeResult = e.result;
        console.log(`\n[grader] iteration ${(e as any).iteration} -> ${e.result}`);
        break;
      case "session.status_idle":
        console.log(`\nSession idle. Outcome: ${outcomeResult ?? "(none)"}`);
        process.exit(outcomeResult === "satisfied" ? 0 : 1);
    }
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(2);
});
```

The `as any` casts are again because beta-namespaced types may not be on the SDK version at write time. Replace with real types when available.

- [ ] **Step 2: Type-check**

```bash
pnpm exec tsc --noEmit
```
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add cloud/run.ts
git commit -m "feat(cloud): add CMA session trigger script"
```

---

## Task 10: Add `.env.example` and `cloud/README.md`

**Files:**
- Create: `.env.example`
- Create: `cloud/README.md`

- [ ] **Step 1: Write `.env.example`**

```bash
# Anthropic API key (used by @anthropic-ai/sdk)
ANTHROPIC_API_KEY=

# ID of the Anthropic Credential Vault holding the GitHub OAuth credential
# bound to the GitHub MCP server (https://api.githubcopilot.com/mcp/).
CMA_GITHUB_VAULT_ID=
```

- [ ] **Step 2: Write `cloud/README.md`**

```markdown
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
```

- [ ] **Step 3: Update root `README.md`**

Append a new section near the bottom:
```markdown
## Cloud (Managed Agents)

The harness has a cloud execution arm that triggers a CMA multiagent session against a workpiece repo. See [`cloud/README.md`](./cloud/README.md).
```

- [ ] **Step 4: Commit**

```bash
git add .env.example cloud/README.md README.md
git commit -m "docs(cloud): add usage docs and .env.example"
```

---

## Task 11: Proof-of-life — hello-world run

Manual integration test. Cannot be automated until a CI-scoped Credential Vault exists.

- [ ] **Step 1: Create an empty `receipt-splitter` repo on GitHub**

```bash
gh repo create h0rhay/receipt-splitter --public --confirm
```
Leave it empty (no README).

- [ ] **Step 2: Create the Anthropic Credential Vault**

In the Anthropic Console, create a Credential Vault holding a GitHub OAuth credential whose `mcp_server_url` is `https://api.githubcopilot.com/mcp/` and scoped to `h0rhay/receipt-splitter`. Copy its ID into `.env` as `CMA_GITHUB_VAULT_ID`.

- [ ] **Step 3: Run the hello-world session**

```bash
pnpm cloud:run \
  --workpiece h0rhay/receipt-splitter \
  --goal "create HELLO.md saying hello world" \
  --rubric hello-world
```
Expected: session creates, Console URL prints, primary-thread events stream (including `session.thread_created` for each specialist and `span.outcome_evaluation_end` from the grader), final outcome `satisfied`, a PR opens on `receipt-splitter`.

- [ ] **Step 4: Merge the PR**

```bash
gh -R h0rhay/receipt-splitter pr list
gh -R h0rhay/receipt-splitter pr merge <num> --squash
```

- [ ] **Step 5: Record the outcome in `cloud/NOTES.md`**

Append a section `## Proof-of-life run 2026-MM-DD` with: session ID, iteration count, grader result, any surprises (e.g. did the engineer push directly instead of opening a PR? did the GitHub MCP require additional scopes?). This closes the loop on whether the spec's assumptions held in practice.

- [ ] **Step 6: Commit notes**

```bash
git add cloud/NOTES.md
git commit -m "docs(cloud): record hello-world proof-of-life run"
```

---

## Task 12: Update the PR

- [ ] **Step 1: Push and refresh PR**

```bash
git push
```
The existing plan PR will be replaced by implementation commits if you push to the same branch. If you prefer a separate PR for the implementation, branch from `main` instead:

```bash
git checkout main && git pull
git checkout -b feat/cma-harness-arm
# cherry-pick or re-author commits as needed
git push -u origin feat/cma-harness-arm
gh pr create --title "feat: CMA arm (cloud/) for product-engineering-harness" \
  --body "Implements docs/superpowers/specs/2026-05-27-cma-harness-arm-design.md per docs/superpowers/plans/2026-05-27-cma-harness-arm.md. Hello-world proof-of-life recorded in cloud/NOTES.md."
```

- [ ] **Step 2: Self-review the diff before requesting merge**

```bash
gh pr diff
```
Walk through the diff against the acceptance criteria in the spec. Check: `cloud/` contents present, `pnpm cloud:run` wired, SDK dep added, `.env.example` populated, existing local-harness files untouched, `cloud/.state.json` gitignored.

---

## Out of scope (deferred, do NOT add to this plan)

- Telegram/Slack/GitHub-issue triggers.
- The calculator-mvp run (Task 11 covers hello-world only; the MVP run is a follow-up issue after `harness init` is exercised against the receipt-splitter repo).
- Memory Stores.
- Self-hosted sandbox tier.
- Any UI surface or portal.
- MCP tunnels (research preview; request access separately if needed).

## Self-review notes

- **Spec coverage:** every item in the spec's "Acceptance criteria for the harness change" maps to Tasks 1-10. Proof-of-life maps to Task 11. Out-of-scope items in the spec are restated above.
- **Placeholder scan:** no `TBD` / `implement later`. The two `as any` casts on the SDK are documented in-place and resolve when SDK types catch up; not placeholders.
- **Type consistency:** `AgentDef`, `AgentSet`, `Rubric`, `CloudRunArgs`, `McpServer`, `StateFile` defined once and consumed unchanged. Field names (`workpiece`, `goal`, `rubric`, `maxIterations`) stable across files. `multiagentRoster` (camelCase in TS) ↔ `multiagent_roster` (snake_case in YAML frontmatter) intentional and isolated to the loader.
- **API surface accuracy:** SDK calls match `cloud/NOTES.md`, which was authored from the official docs (URLs listed at top of plan). `max_iterations` (1-20, default 3) replaces the earlier made-up `retry_cap`. Outcome result enum (`satisfied | needs_revision | max_iterations_reached | failed | interrupted`) consumed correctly in `run.ts`.
