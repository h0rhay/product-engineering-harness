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
  const mcpServers = (fm.mcp_servers as McpServer[] | undefined) ?? [];
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
