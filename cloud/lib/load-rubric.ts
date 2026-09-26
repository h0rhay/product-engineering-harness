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
