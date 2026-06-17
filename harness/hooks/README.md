# Harness hooks

Reusable PreToolUse hooks for projects driven by the product engineering harness.

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

- MCP `execute_destructive` (any).
- MCP `execute_mutating` whose `operation` is a known schema-shape mutation
  (`updateComponent`, `updateContentType`, `updateCustomType`, `updateSchema`, …).
- Bash commands hitting a registered hostname/pattern with PUT/POST/DELETE/PATCH
  unless the command invokes the project helper.
- Ad-hoc `scripts/(backfill|load|seed|migrate)*.ts` outside the
  `scripts/<system>/` convention. Bypass per-call with `DATA_WRITE_ALLOW_ADHOC=1`.

### What it allows

- GETs against the same endpoints (read is safe).
- Story / row / document content writes — only schema-shape edits are guarded.
- The project helper itself (matched by path).

### Helpers

Templates live in `~/.claude/harness/templates/`. Copy one to
`scripts/<system>/update-*.ts` and adapt the API constants. The template
enforces GET → merge → PUT and refuses to delete fields still referenced
in `src/` without `--force-delete`.

### What it now covers (June 2026 update)

After two consecutive wipe incidents — first the `item-category` schema, then the gold/jewellery/watches **story content** — the guard treats schema-shape mutations and row-content mutations the same. Both routes (PUT to `/components/*` and PUT to `/stories/*`) have the same partial-payload bug. Both must go through a helper that does GET → merge → PUT.

MCP operations blocked: `updateComponent`, `updateContentType`, `updateCustomType`, `updateSchema`, `updateStory`, `updateEntry`, `updateDocument`, `updateRecord` (and their delete/create variants).

Templates: `update-component-schema.template.ts` (schema) + `update-row-content.template.ts` (row/story/document content). Each enforces critical-field assertions and refuses to delete fields still referenced in `src/` without `--force-delete`.
