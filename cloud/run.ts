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
