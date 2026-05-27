# CMA Harness Arm Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `cloud/` arm to the product-engineering-harness that triggers a Claude Managed Agents session (coordinator + pm/engineer/reviewer specialists + native outcome rubric) against a workpiece repo from a CLI command.

**Architecture:** New `cloud/` directory holding agent definitions (markdown), rubric definitions (markdown), and a TypeScript trigger script (`run.ts`) that loads them and calls the Anthropic SDK. No changes to existing local-harness behaviour. Auth via Anthropic Credential Vault, not local secrets.

**Tech Stack:** TypeScript (strict), `@anthropic-ai/sdk`, Vitest for unit tests, pnpm, GitHub for workpiece repos, Anthropic Console for observability.

**Source spec:** `docs/superpowers/specs/2026-05-27-cma-harness-arm-design.md`.

---

## File structure

Files to create in the harness repo:

- `cloud/agents/coordinator.md` — coordinator system prompt + model tier.
- `cloud/agents/pm.md` — pm specialist definition.
- `cloud/agents/engineer.md` — engineer specialist definition.
- `cloud/agents/reviewer.md` — reviewer specialist definition.
- `cloud/rubrics/hello-world.md` — hello-world rubric.
- `cloud/rubrics/calculator-mvp.md` — calculator-mvp rubric.
- `cloud/run.ts` — CLI trigger script.
- `cloud/lib/load-agents.ts` — pure function: read agent markdown files into objects.
- `cloud/lib/load-rubric.ts` — pure function: read a rubric markdown file into an object.
- `cloud/lib/args.ts` — pure function: parse CLI args.
- `cloud/lib/__tests__/load-agents.test.ts` — Vitest unit test.
- `cloud/lib/__tests__/load-rubric.test.ts` — Vitest unit test.
- `cloud/lib/__tests__/args.test.ts` — Vitest unit test.
- `cloud/README.md` — usage docs.
- `cloud/NOTES.md` — short doc capturing the exact CMA SDK surface as verified at implementation time (see Task 2).
- `.env.example` — documents `ANTHROPIC_API_KEY` and `CMA_CREDENTIAL_VAULT_ID`.

Files to modify:
- `package.json` — add `cloud:run` script and `@anthropic-ai/sdk` dep.
- `README.md` — link to `cloud/README.md` under a new "Cloud (Managed Agents)" section.

Splitting `run.ts` from `lib/*` keeps the SDK side-effect entry point thin and the parseable bits unit-testable.

---

## Task 1: Initialise `cloud/` skeleton and tooling

**Files:**
- Create: `cloud/.gitkeep`
- Modify: `package.json` (root)

- [ ] **Step 1: Confirm the repo has a `package.json` at root**

```bash
cat package.json | head -20
```
Expected: A package.json exists. If not, initialise one (`pnpm init`) and add `"type": "module"`, `"private": true`.

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
```

- [ ] **Step 6: Commit**

```bash
git add package.json pnpm-lock.yaml tsconfig.json cloud/.gitkeep
git commit -m "chore: scaffold cloud/ directory and tooling"
```

---

## Task 2: Verify the CMA SDK surface and pin it in `NOTES.md`

The spec defers exact SDK shapes. Do this *before* writing `run.ts` so the rest of the plan can rely on concrete shapes.

**Files:**
- Create: `cloud/NOTES.md`

- [ ] **Step 1: Open the current Anthropic Managed Agents docs**

Fetch `https://platform.claude.com/docs/en/managed-agents/overview` and the linked pages on coordinator mode, `define_outcome`, Credential Vaults, and per-tool permissions.

- [ ] **Step 2: Record the exact API surface in `cloud/NOTES.md`**

Capture: the SDK call used to create a coordinator session, the shape of the `multiagent` config, how specialist definitions are passed in (inline objects vs IDs created out-of-band), the shape of `user.define_outcome`, and how to attach a Credential Vault.

Example structure (replace with verified content):
```markdown
# CMA SDK surface (verified YYYY-MM-DD)

## Session create
SDK method: `anthropic.<verify>`
Required fields: <list>
Multiagent config: <shape>

## Specialist definition
Inline or referenced? <answer>
Fields: <list>

## Outcome
Field name: `user.define_outcome` (verify)
Shape: <object>

## Credential Vault
How bound: <answer>
```

- [ ] **Step 3: Commit**

```bash
git add cloud/NOTES.md
git commit -m "docs(cloud): pin verified CMA SDK surface"
```

If the docs reveal that the spec's assumptions are wrong (e.g. `define_outcome` is named differently or coordinator mode requires a different shape), stop and surface the discrepancy before continuing. Do not silently adapt the plan.

---

## Task 3: Write agent definition files

**Files:**
- Create: `cloud/agents/coordinator.md`
- Create: `cloud/agents/pm.md`
- Create: `cloud/agents/engineer.md`
- Create: `cloud/agents/reviewer.md`

These are markdown files with frontmatter (model, tool scopes) + a system prompt body. The loader (Task 4) parses them.

- [ ] **Step 1: Write `cloud/agents/coordinator.md`**

```markdown
---
role: coordinator
model: claude-sonnet-4-6
tools: []
---

You orchestrate a session that ends with a PR opened on the workpiece repo. Fan out to specialists in this order: `pm` to produce `spec.md`, `engineer` to implement, `reviewer` to grade. If the reviewer fails the outcome rubric, dispatch `engineer` again with the reviewer's notes. Stop after 2 engineer retries; the platform will surface the result either way.
```

- [ ] **Step 2: Write `cloud/agents/pm.md`**

```markdown
---
role: pm
model: claude-sonnet-4-6
tools: [repo.read, repo.write]
auto_execute: true
---

Turn the user goal into `spec.md` at the workpiece repo root. The spec must list pass/fail acceptance criteria the engineer can implement against and the reviewer can verify with evidence (file paths or command output). Keep it under 200 words. Commit `spec.md` to the working branch.
```

- [ ] **Step 3: Write `cloud/agents/engineer.md`**

```markdown
---
role: engineer
model: claude-sonnet-4-6
tools: [repo.read, repo.write, shell.run]
auto_execute_reads: true
auto_execute_writes: false
---

Read `spec.md`. Implement the acceptance criteria. Commit to the working branch. Run `pnpm test` (or the repo's test command) before signalling done. Follow conventions in the workpiece repo's `CLAUDE.md` if present. Writes flow through a PR, never push to `main` directly.
```

- [ ] **Step 4: Write `cloud/agents/reviewer.md`**

```markdown
---
role: reviewer
model: claude-sonnet-4-6
tools: [repo.read, shell.run]
auto_execute: true
---

Grade the engineer's output against the rubric supplied by the coordinator. For each rubric item, output: pass/fail, the file path or command output that justifies the verdict, and a one-line note. Read-only; never write to the repo. If any item fails, return failure with notes so the coordinator can retry.
```

- [ ] **Step 5: Commit**

```bash
git add cloud/agents/
git commit -m "feat(cloud): add specialist definitions (coordinator, pm, engineer, reviewer)"
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
retry_cap: 2
---

# Hello-world rubric

1. A file `HELLO.md` exists at the workpiece repo root.
2. The file contains the string "hello world" (case-insensitive match).
3. The reviewer's justification cites the file path.
```

- [ ] **Step 2: Write `cloud/rubrics/calculator-mvp.md`**

```markdown
---
name: calculator-mvp
retry_cap: 2
---

# Calculator MVP rubric

Applies only to a workpiece repo that has already been scaffolded via `harness init`.

1. `pnpm test` exits 0 after the engineer's changes.
2. A new Vitest test covers the per-person split calculation.
3. The app renders three inputs (total, number of people, tip %) and one output (per-person amount). A Playwright smoke test verifies this.
4. No new axe-core accessibility violations are introduced compared to `main`.
```

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
      "--workpiece", "https://github.com/foo/bar",
      "--goal", "do the thing",
      "--rubric", "hello-world",
    ]);
    expect(result).toEqual({
      workpiece: "https://github.com/foo/bar",
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
  if (!workpiece) throw new Error("--workpiece is required");
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
    for (const role of ["coordinator", "pm", "engineer", "reviewer"]) {
      writeFileSync(
        join(dir, "agents", `${role}.md`),
        `---\nrole: ${role}\nmodel: claude-sonnet-4-6\n---\n\nBody for ${role}.\n`
      );
    }
    const agents = loadAgents(join(dir, "agents"));
    expect(agents.coordinator.model).toBe("claude-sonnet-4-6");
    expect(agents.engineer.systemPrompt).toContain("Body for engineer");
  });

  it("throws if a required role file is missing", () => {
    const dir = mkdtempSync(join(tmpdir(), "agents-"));
    mkdirSync(join(dir, "agents"));
    writeFileSync(
      join(dir, "agents", "coordinator.md"),
      `---\nrole: coordinator\nmodel: x\n---\n\nBody.\n`
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

export interface AgentDef {
  role: string;
  model: string;
  tools?: string[];
  auto_execute?: boolean;
  auto_execute_reads?: boolean;
  auto_execute_writes?: boolean;
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
  const fm = Object.fromEntries(
    match[1]
      .split("\n")
      .filter(Boolean)
      .map((line) => {
        const i = line.indexOf(":");
        const key = line.slice(0, i).trim();
        const value = line.slice(i + 1).trim();
        if (value.startsWith("[") && value.endsWith("]")) {
          return [key, value.slice(1, -1).split(",").map((s) => s.trim()).filter(Boolean)];
        }
        if (value === "true" || value === "false") return [key, value === "true"];
        return [key, value];
      })
  );
  return { ...(fm as Omit<AgentDef, "systemPrompt">), systemPrompt: match[2].trim() };
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

- [ ] **Step 4: Run test to verify it passes**

```bash
pnpm test cloud/lib/__tests__/load-agents.test.ts
```
Expected: PASS, 2/2 tests green.

- [ ] **Step 5: Commit**

```bash
git add cloud/lib/load-agents.ts cloud/lib/__tests__/load-agents.test.ts
git commit -m "feat(cloud): add agent loader"
```

---

## Task 7: Write the rubric loader (TDD)

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
      `---\nname: hello-world\nretry_cap: 2\n---\n\n1. A file exists.\n2. It contains text.\n`
    );
    const rubric = loadRubric(join(dir, "rubrics"), "hello-world");
    expect(rubric.name).toBe("hello-world");
    expect(rubric.retryCap).toBe(2);
    expect(rubric.body).toContain("A file exists");
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

export interface Rubric {
  name: string;
  retryCap: number;
  body: string;
}

export function loadRubric(rubricsDir: string, name: string): Rubric {
  const path = join(rubricsDir, `${name}.md`);
  if (!existsSync(path)) throw new Error(`Rubric not found: ${name}`);
  const raw = readFileSync(path, "utf8");
  const match = raw.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
  if (!match) throw new Error(`Invalid rubric file (no frontmatter): ${path}`);
  const fm = Object.fromEntries(
    match[1].split("\n").filter(Boolean).map((line) => {
      const i = line.indexOf(":");
      return [line.slice(0, i).trim(), line.slice(i + 1).trim()];
    })
  );
  return {
    name: String(fm.name ?? name),
    retryCap: Number(fm.retry_cap ?? 2),
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

## Task 8: Write `cloud/run.ts` (entry point)

This is the side-effect entry point. Logic is delegated to the loaders. The actual SDK call shape MUST follow `cloud/NOTES.md` from Task 2, not the placeholders below. If the SDK shape differs, adapt this task and note the deviation in the PR.

**Files:**
- Create: `cloud/run.ts`

- [ ] **Step 1: Implement `cloud/run.ts`**

```typescript
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import Anthropic from "@anthropic-ai/sdk";
import { parseArgs } from "./lib/args.js";
import { loadAgents } from "./lib/load-agents.js";
import { loadRubric } from "./lib/load-rubric.js";

const here = dirname(fileURLToPath(import.meta.url));

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const agents = loadAgents(join(here, "agents"));
  const rubric = loadRubric(join(here, "rubrics"), args.rubric);

  if (!process.env.ANTHROPIC_API_KEY) {
    throw new Error("ANTHROPIC_API_KEY is not set");
  }
  const vaultId = process.env.CMA_CREDENTIAL_VAULT_ID;
  if (!vaultId) throw new Error("CMA_CREDENTIAL_VAULT_ID is not set");

  const client = new Anthropic();

  // IMPORTANT: Replace the call below with the verified SDK shape from cloud/NOTES.md.
  // The shape used here is illustrative; do not assume field names.
  const session = await (client as any).beta.managedAgents.sessions.create({
    coordinator: {
      model: agents.coordinator.model,
      systemPrompt: agents.coordinator.systemPrompt,
    },
    specialists: {
      pm: { model: agents.pm.model, systemPrompt: agents.pm.systemPrompt, tools: agents.pm.tools },
      engineer: { model: agents.engineer.model, systemPrompt: agents.engineer.systemPrompt, tools: agents.engineer.tools },
      reviewer: { model: agents.reviewer.model, systemPrompt: agents.reviewer.systemPrompt, tools: agents.reviewer.tools },
    },
    credentialVaultId: vaultId,
    workpiece: { repoUrl: args.workpiece },
    user: {
      goal: args.goal,
      define_outcome: { rubric: rubric.body, retryCap: rubric.retryCap },
    },
  });

  console.log(`Session created: ${session.id}`);
  console.log(`Console: https://console.anthropic.com/sessions/${session.id}`);

  for await (const event of session.events) {
    process.stdout.write(`[${event.type}] ${JSON.stringify(event).slice(0, 200)}\n`);
    if (event.type === "session.complete") {
      console.log(`Result: ${event.result}`);
      console.log(`PR: ${event.prUrl ?? "(none)"}`);
      process.exit(event.result === "passed" ? 0 : 1);
    }
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(2);
});
```

- [ ] **Step 2: Reconcile against `cloud/NOTES.md`**

Open `cloud/NOTES.md`. Rewrite every line under the `// IMPORTANT` comment to match the verified SDK surface. Remove the `as any` cast once the real types are available.

- [ ] **Step 3: Type-check**

```bash
pnpm exec tsc --noEmit
```
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add cloud/run.ts
git commit -m "feat(cloud): add CMA session trigger script"
```

---

## Task 9: Add `.env.example` and `cloud/README.md`

**Files:**
- Create: `.env.example`
- Create: `cloud/README.md`

- [ ] **Step 1: Write `.env.example`**

```bash
# Anthropic API key (used by @anthropic-ai/sdk)
ANTHROPIC_API_KEY=

# ID of the Anthropic Credential Vault that holds the GitHub PAT
# bound to the workpiece repo.
CMA_CREDENTIAL_VAULT_ID=
```

- [ ] **Step 2: Write `cloud/README.md`**

```markdown
# Cloud (Managed Agents) arm

Trigger a Claude Managed Agents session against a workpiece repo from the CLI.

## Setup

1. Set `ANTHROPIC_API_KEY` and `CMA_CREDENTIAL_VAULT_ID` in `.env`.
2. The Credential Vault must hold a GitHub PAT scoped to the workpiece repo.

## Run

    pnpm cloud:run --workpiece <repo-url> --goal "<text>" --rubric <name>

Example:

    pnpm cloud:run \
      --workpiece https://github.com/h0rhay/receipt-splitter \
      --goal "create HELLO.md saying hello world" \
      --rubric hello-world

The script prints the Console URL on start. Watch the session there for richer detail.

## Available rubrics

- `hello-world` — sanity check, expects a `HELLO.md` file.
- `calculator-mvp` — requires the workpiece repo to be scaffolded via `harness init` first.

## Adding a rubric

Drop a markdown file at `cloud/rubrics/<name>.md` with frontmatter (`name`, `retry_cap`) and a numbered list of pass/fail criteria. The reviewer specialist must cite evidence for each.

## SDK surface

See `cloud/NOTES.md` for the verified Anthropic SDK shapes used by `run.ts`.
```

- [ ] **Step 3: Update root `README.md`**

Append a new section near the bottom:
```markdown
## Cloud (Managed Agents)

The harness has a cloud execution arm that triggers a Claude Managed Agents session against a workpiece repo. See [`cloud/README.md`](./cloud/README.md).
```

- [ ] **Step 4: Commit**

```bash
git add .env.example cloud/README.md README.md
git commit -m "docs(cloud): add usage docs and .env.example"
```

---

## Task 10: Proof-of-life — hello-world run

This is a manual integration test. It cannot be automated until a CI Credential Vault exists.

- [ ] **Step 1: Create an empty `receipt-splitter` repo on GitHub**

Use `gh repo create h0rhay/receipt-splitter --public --confirm` or via the web UI. Leave it empty (no README).

- [ ] **Step 2: Create the Anthropic Credential Vault**

In the Anthropic Console, create a Credential Vault holding a GitHub PAT with `repo` scope on `receipt-splitter`. Copy its ID into `.env` as `CMA_CREDENTIAL_VAULT_ID`.

- [ ] **Step 3: Run the hello-world session**

```bash
pnpm cloud:run \
  --workpiece https://github.com/h0rhay/receipt-splitter \
  --goal "create HELLO.md saying hello world" \
  --rubric hello-world
```
Expected: session creates, Console URL prints, events stream, terminal state is `passed`, a PR appears on `receipt-splitter`.

- [ ] **Step 4: Merge the PR and confirm `HELLO.md` is on `main`**

```bash
gh -R h0rhay/receipt-splitter pr list
gh -R h0rhay/receipt-splitter pr merge <num> --squash
```

- [ ] **Step 5: Record the outcome in `cloud/NOTES.md`**

Append a section `## Proof-of-life run YYYY-MM-DD` with: session ID, retry count, final verdict, any surprises. This is the artefact that closes the loop on whether the spec's assumptions held.

- [ ] **Step 6: Commit notes**

```bash
git add cloud/NOTES.md
git commit -m "docs(cloud): record hello-world proof-of-life run"
```

---

## Task 11: Open PR for the whole branch

- [ ] **Step 1: Push and open PR**

```bash
git push -u origin plan/cma-harness-arm
gh pr create --title "feat: CMA arm (cloud/) for product-engineering-harness" \
  --body "Implements the design at docs/superpowers/specs/2026-05-27-cma-harness-arm-design.md. Hello-world proof-of-life recorded in cloud/NOTES.md."
```

- [ ] **Step 2: Self-review the diff before requesting merge**

```bash
gh pr diff
```
Walk through the diff against the acceptance criteria in the spec. Check: `cloud/` directory contents present, `pnpm cloud:run` wired, SDK dep added, `.env.example` populated, existing local-harness files untouched.

---

## Out of scope (deferred, do NOT add to this plan)

- Telegram/Slack/GitHub-issue triggers.
- The calculator-mvp run (Task 10 only covers hello-world; the MVP run is a follow-up issue after `harness init` is exercised against the receipt-splitter repo).
- Memory Stores.
- Self-hosted sandbox tier.
- Any UI surface or portal.

## Self-review notes

- Spec coverage: every item in the spec's "Acceptance criteria for the harness change" maps to Tasks 1-9. Proof-of-life test in the spec maps to Task 10. Out-of-scope items in the spec are explicitly restated above.
- Placeholder scan: the only intentionally indeterminate content is the SDK surface in `run.ts`, which Task 2 pins and Task 8 reconciles. No `TBD` or `implement later`.
- Type consistency: `AgentDef`, `AgentSet`, `Rubric`, and `CloudRunArgs` are defined once and consumed unchanged. Field names (`workpiece`, `goal`, `rubric`, `retryCap`) are stable across files.
