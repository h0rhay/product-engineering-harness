/**
 * Template: safe CMS schema editor.
 *
 * Principle: EMBELLISH, DON'T REPLACE.
 *
 * Copy to scripts/<system>/update-<thing>-schema.ts and adapt the GET/PUT
 * paths to your CMS. The core invariant is:
 *
 *   1. GET the live shape
 *   2. Merge the patch on top of it in memory
 *   3. PUT the merged result back (or PATCH if your API supports it)
 *
 * Deletions are explicit (--delete-fields=a,b) and refuse to drop a field
 * still referenced in src/ unless --force-delete is passed.
 *
 * Replace the API constants + http() impl for your system.
 */

import { readFileSync, existsSync } from "node:fs";
import { execSync } from "node:child_process";

type FieldSpec = Record<string, unknown>;
type Schema = Record<string, FieldSpec>;

// --- replace these for your CMS ----------------------------------------------
const API = "https://api.example.com/v1";
function authHeaders(): Record<string, string> {
  return { Authorization: env("CMS_TOKEN"), "Content-Type": "application/json" };
}
function resourceUrl(id: string): string {
  return `${API}/${env("CMS_SCOPE")}/components/${id}`;
}
// -----------------------------------------------------------------------------

function die(msg: string): never { console.error(`[update-schema] ${msg}`); process.exit(1); }
function env(name: string): string { const v = process.env[name]; if (!v) die(`missing env: ${name}`); return v; }

async function http(method: "GET" | "PUT", url: string, body?: unknown): Promise<Record<string, unknown>> {
  const r = await fetch(url, { method, headers: authHeaders(), body: body ? JSON.stringify(body) : undefined });
  if (!r.ok) die(`${method} ${url} → ${r.status} ${await r.text()}`);
  return r.json() as Promise<Record<string, unknown>>;
}

function diff(before: Schema, after: Schema): string[] {
  const out: string[] = [];
  const b = new Set(Object.keys(before)), a = new Set(Object.keys(after));
  for (const k of a) if (!b.has(k)) out.push(`  + ${k}`);
  for (const k of b) if (!a.has(k)) out.push(`  - ${k}`);
  for (const k of a) if (b.has(k) && JSON.stringify(before[k]) !== JSON.stringify(after[k])) out.push(`  ~ ${k}`);
  return out;
}

function usedInSrc(field: string): boolean {
  try {
    const out = execSync(`grep -rln --include='*.astro' --include='*.ts' --include='*.tsx' '${field}' src/ 2>/dev/null || true`, { encoding: "utf8" });
    return out.trim().length > 0;
  } catch { return false; }
}

async function main() {
  const [, , idArg, patchPath, ...rest] = process.argv;
  if (!idArg || !patchPath) die("usage: tsx update-schema.ts <id> <patch.json> [--delete-fields=a,b] [--force-delete]");
  if (!existsSync(patchPath)) die(`patch file not found: ${patchPath}`);

  const id = idArg;
  const patch = JSON.parse(readFileSync(patchPath, "utf8")) as Schema;
  const deleteFields = rest.find((a) => a.startsWith("--delete-fields="))?.split("=")[1]?.split(",").map((s) => s.trim()).filter(Boolean) ?? [];
  const forceDelete = rest.includes("--force-delete");

  const url = resourceUrl(id);
  const got = await http("GET", url);
  // CHANGE THIS PATH to your API's "the resource" key (e.g. .component, .data, .type).
  const resource = (got.component ?? got.data ?? got) as { schema: Schema; [k: string]: unknown };
  const before = resource.schema;

  // EMBELLISH: clone, then layer patch in.
  const after: Schema = { ...before };
  for (const [field, spec] of Object.entries(patch)) {
    after[field] = { ...(after[field] ?? {}), ...spec };
  }
  for (const field of deleteFields) {
    if (!forceDelete && usedInSrc(field)) die(`refusing to delete field "${field}" — still referenced in src/. Pass --force-delete to override.`);
    delete after[field];
  }

  const d = diff(before, after);
  if (d.length === 0) { console.log("no changes; skipping write."); return; }
  console.log(`[update-schema] id=${id}:`);
  for (const l of d) console.log(l);

  if (process.env.DRY_RUN === "1") { console.log("DRY_RUN=1 — not writing."); return; }

  await http("PUT", url, { ...resource, schema: after });
  console.log("[update-schema] write OK.");
}

main().catch((e) => die(String(e)));
