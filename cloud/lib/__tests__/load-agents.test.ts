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
