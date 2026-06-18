# Harness hooks

Reusable PreToolUse hooks for projects driven by the product engineering harness.

## Branded output (`_peh.sh`)

Every harness hook sources `_peh.sh` and emits blocks via `peh_block`. The
shared banner makes blocks instantly recognisable as harness-driven (not
generic system noise the agent will gloss over):

```
══ [[PEH]] <hook-name> ════════════════════════════════════════════════
   This block is from the product engineering harness.
   BLOCKED: <headline>
   Why:      <one-line reason>
   Fix:      <what to do instead>
   Override: <per-call env var, or "(none)">
════════════════════════════════════════════════════════════════════════
```

Adding a new hook? Source the library at the top:

```sh
_peh_lib="${PEH_LIB:-$HOME/.claude/harness/hooks/_peh.sh}"
[[ -r "$_peh_lib" ]] || _peh_lib="$(dirname "$0")/_peh.sh"
source "$_peh_lib"

# ...later, when blocking:
peh_block "my-hook" "<headline>" "<why>" "<fix>" "<override-hint>"
exit 2
```

## `data-write-guard.sh`

Blocks direct destructive writes (PUT/POST/DELETE/PATCH) to CMS / database admin endpoints, forcing all schema-shape edits through a project-owned helper that performs `GET → embellish → PUT`.

### Why

Most upstream APIs full-replace on PUT. An agent that constructs a partial payload and PUTs it silently wipes every field it didn't include. The fix is non-obvious at the API level; this hook makes the wrong path impossible.

Burned twice in 48h on Storyblok in the vcc-migration repo (June 2026).

### Wire-up

In any project's `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|mcp__.*__execute_mutating|mcp__.*__execute_destructive",
        "hooks": [
          { "type": "command", "command": "$HOME/.claude/harness/hooks/data-write-guard.sh" }
        ]
      }
    ]
  }
}
```

Declare write surfaces in `.claude/harness.config.sh`:

```sh
DATA_WRITE_HELPERS=(
  # "<label>:<helper-script-path>:<host-or-url-regex>:<methods-regex>"
  "storyblok-schema:scripts/storyblok/update-component-schema.ts:mapi.storyblok.com/v[0-9]+/spaces/[0-9]+/components:PUT|POST|DELETE"
  "convex-schema:scripts/convex/update-schema.ts:convex\\.(cloud|site)/(admin|_system|schema):PUT|POST|DELETE"
)
```

Built-in defaults cover the common foot-guns even with no project declaration:
Storyblok components, Strapi content-type builder, Prismic custom types,
Sanity schemas, Supabase admin, Convex schema/admin. Disable with
`DATA_WRITE_DEFAULTS_OFF=1` in `harness.config.sh`.

### What it blocks

- MCP `execute_destructive` (any). Override per-call with
  `DATA_WRITE_ALLOW_DESTRUCTIVE=1` for the deliberate-delete case.
- MCP `execute_mutating` with a schema-shape **update/delete**
  (`updateComponent`, `deleteComponent`, `updateContentType`, `updateCustomType`,
  `updateSchema`, …). Creates are NOT blocked (nothing to wipe).
- MCP `execute_mutating` with a row-content **update**
  (`updateStory`, `updateEntry`, `updateDocument`, `updateRecord`).
- Bash commands hitting a registered hostname/pattern with a mutating method
  unless the command invokes the project helper as an executable. Mutating
  method = explicit `-X PUT|POST|DELETE|PATCH` / `--request …` / `method: '…'`,
  OR body-bearing curl flags that imply a write (`-d`, `--data*`, `-T`,
  `--upload-file`).
- Ad-hoc `scripts/(backfill|load|seed|migrate)*.ts` outside the
  `scripts/<system>/` convention. Bypass per-call with `DATA_WRITE_ALLOW_ADHOC=1`.

### What it allows

- GETs against the same endpoints (read is safe).
- MCP `createComponent` / `createContentType` / other create ops — no
  partial-payload risk on creation.
- The project helper itself — matched only when invoked as an executable
  (`tsx|node|bun|deno|npx|pnpm|yarn|python|sh|bash` followed by the helper
  path). Merely mentioning the helper path in a string does not unlock the
  rule.

### Per-call overrides

| Env var                          | Effect                                                    |
| -------------------------------- | --------------------------------------------------------- |
| `DATA_WRITE_ALLOW_DESTRUCTIVE=1` | Allow one MCP `execute_destructive` call (deliberate del).|
| `DATA_WRITE_ALLOW_ADHOC=1`       | Allow one ad-hoc backfill/load/seed/migrate script.       |
| `DATA_WRITE_DEFAULTS_OFF=1`      | Disable built-in defaults; rely on project rules only.    |

### Helpers

Templates live in `~/.claude/harness/templates/`. Copy one to
`scripts/<system>/update-*.ts` and adapt the API constants. The template
enforces GET → merge → PUT and refuses to delete fields still referenced
in `src/` without `--force-delete`.

### What it now covers (June 2026 update)

After two consecutive wipe incidents — first the `item-category` schema, then the gold/jewellery/watches **story content** — the guard treats schema-shape mutations and row-content mutations the same. Both routes (PUT to `/components/*` and PUT to `/stories/*`) have the same partial-payload bug. Both must go through a helper that does GET → merge → PUT.

MCP operations blocked: `updateComponent`, `updateContentType`, `updateCustomType`, `updateSchema`, `updateStory`, `updateEntry`, `updateDocument`, `updateRecord` (and their delete variants). Create variants are intentionally allowed — there are no sibling fields to wipe on a fresh create.

Templates: `update-component-schema.template.ts` (schema) + `update-row-content.template.ts` (row/story/document content). Each enforces critical-field assertions and refuses to delete fields still referenced in `src/` without `--force-delete`.

### Hardening (post-review)

Adversarial review tightened a few rough edges:

- **Creates allowed.** `createComponent` / `createContentType` removed from
  the blocklist — no partial-payload risk on a brand-new record.
- **Deliberate deletes have an override.** `DATA_WRITE_ALLOW_DESTRUCTIVE=1`
  per-call instead of forcing the hook to be disabled globally.
- **Supabase default narrowed.** Was matching the `/rest/` data API (routine
  CRUD); now scoped to `/admin/` and `/pg-meta/` only.
- **Helper-path match anchored.** A command must invoke the helper as an
  executable (runner-token check). Previous substring match passed on
  `echo helper && curl -X PUT …`.
- **Implicit-mutation curl caught.** `curl -d @x.json …` (POST without
  `-X`) and `curl -T file …` (PUT) now count as mutating methods.
