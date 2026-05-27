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
