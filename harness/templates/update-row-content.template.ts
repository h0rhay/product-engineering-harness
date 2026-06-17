/**
 * Template: safe row / story / document content editor.
 *
 * Principle: EMBELLISH, DON'T REPLACE.
 *
 * Copy to scripts/<system>/update-<row-thing>.ts and adapt the API paths.
 *
 *   1. GET the row's current content
 *   2. Merge the patch over it in memory (shallow merge at the top level)
 *   3. PUT the merged content back
 *
 * Critical fields (defined per-CMS) are asserted before write so a malformed
 * GET cannot lead to writing a story whose `component` or `_uid` has gone
 * missing. Deletions are explicit and refuse to drop a field still referenced
 * in src/ unless --force-delete is passed.
 */

import { readFileSync, existsSync } from "node:fs";
import { execSync } from "node:child_process";

const API = "https://api.example.com/v1";
const CRITICAL_FIELDS = ["_uid", "component"]; // change per CMS

function authHeaders(): Record<string, string> {
  return { Authorization: env("CMS_TOKEN"), "Content-Type": "application/json" };
}
function resourceUrl(id: string): string {
  return `${API}/${env("CMS_SCOPE")}/rows/${id}`;
}

function die(msg: string): never { console.error(`[update-row] ${msg}`); process.exit(1); }
function env(name: string): string { const v = process.env[name]; if (!v) die(`missing env: ${name}`); return v; }

async function http(method: "GET" | "PUT", url: string, body?: unknown): Promise<Record<string, unknown>> {
  const r = await fetch(url, { method, headers: authHeaders(), body: body ? JSON.stringify(body) : undefined });
  if (!r.ok) die(`${method} ${url} → ${r.status} ${await r.text()}`);
  return r.json() as Promise<Record<string, unknown>>;
}

function diff(before: Record<string, unknown>, after: Record<string, unknown>): string[] {
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
  if (!idArg || !patchPath) die("usage: tsx update-row.ts <id> <patch.json> [--delete-fields=a,b] [--force-delete]");
  if (!existsSync(patchPath)) die(`patch file not found: ${patchPath}`);

  const patch = JSON.parse(readFileSync(patchPath, "utf8")) as Record<string, unknown>;
  const deleteFields = rest.find((a) => a.startsWith("--delete-fields="))?.split("=")[1]?.split(",").map((s) => s.trim()).filter(Boolean) ?? [];
  const forceDelete = rest.includes("--force-delete");

  const url = resourceUrl(idArg);
  const got = await http("GET", url);
  // CHANGE THIS PATH to your API's "the row's content" key.
  const row = (got.row ?? got.story ?? got.data ?? got) as { content: Record<string, unknown>; [k: string]: unknown };
  const before = row.content;

  const after: Record<string, unknown> = { ...before };
  for (const [k, v] of Object.entries(patch)) after[k] = v;
  for (const field of deleteFields) {
    if (!forceDelete && usedInSrc(field)) die(`refusing to delete "${field}" — still referenced in src/. --force-delete to override.`);
    delete after[field];
  }

  for (const k of CRITICAL_FIELDS) {
    if (!(k in after)) die(`refusing to write: critical field "${k}" missing from merged content.`);
  }

  const d = diff(before, after);
  if (d.length === 0) { console.log("no changes; skipping write."); return; }
  console.log(`[update-row] id=${idArg}:`);
  for (const l of d) console.log(l);

  if (process.env.DRY_RUN === "1") { console.log("DRY_RUN=1 — not writing."); return; }

  await http("PUT", url, { ...row, content: after });
  console.log("[update-row] write OK.");
}

main().catch((e) => die(String(e)));
