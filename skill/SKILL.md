---
name: zrouter
version: 0.1.0-phase0
description: Per-directory CLAUDE.md with auto-maintained file index. Use for setting up scoped agent context or checking it's up to date. Triggers on "zrouter init", "zrouter check", and "zr ..." shorthand.
---

# zrouter

Splits one big CLAUDE.md into a small root + one CLAUDE.md per code directory. Each subdirectory CLAUDE.md ends with an auto-managed file index block (`<!-- zr:files -->`) so a single read gives Claude both the local conventions and a one-line summary + token estimate for every file in that directory.

The user types `init` once and `check` when they want a health report. Everything else — keeping the file index and routing fresh — happens automatically as Claude edits code.

## The token-saving move

Before opening an unfamiliar file, **first read the surrounding directory's `<!-- zr:files -->` block** — it has a one-line description and token estimate per file. Only `Read` the file when that's not enough.

(Phase 1 will ship a `zrouter query <path>` CLI returning the same data per file. Until then, the files block is the source.)

## Project layout

```
CLAUDE.md            # root: stack, rules, routing block
.memory/
  decisions.md       # ADRs + Do-Not-Repeat
  patterns.md        # reusable code patterns
  inbox.md           # uncertain inferences (never authoritative)
<dir>/CLAUDE.md      # per-directory: purpose, conventions, gotchas, files block
```

Templates for every file are in `templates.md` — single source of truth for format.

`.gitignore` is the user's call. Suggest ignoring `.memory/` if asked, but don't auto-edit.

## Marker blocks

- `<!-- zr:files -->` ... `<!-- /zr:files -->` — at the end of each subdirectory CLAUDE.md
- `<!-- zr:routing -->` ... `<!-- /zr:routing -->` — in root CLAUDE.md

Inside the markers: tool-managed; manual edits overwritten on next refresh.
Outside the markers: human-owned; zrouter never touches.

## User commands

### `init`

1. Detect stack from signature files (`build.zig`, `package.json`, `Cargo.toml`, `go.mod`, `pyproject.toml`, ...).
2. Pre-fill the Stack section of root CLAUDE.md.
3. **Ask** the user what Critical Rules they want. Don't invent rules.
4. Decide subdirectories. Greenfield (≤2 source dirs) → root only. Brownfield → ask the user to confirm the list, don't blanket-create.
5. Create `.memory/` skeletons.
6. Populate the files block in each subdirectory CLAUDE.md and the routing block in root (using the refresh logic below).

### `check`

Read-only report; **don't fix automatically**. List:
- Files block stale: any file in `<dir>/` newer than the block, or files added/removed since last refresh
- Root CLAUDE.md > 250 tokens (excluding routing)
- Subdirectory CLAUDE.md > 300 tokens (excluding files block)
- Code directory without CLAUDE.md
- CLAUDE.md whose directory has no files

If the user wants the issues fixed, they ask explicitly — then apply the refresh logic below.

## Automatic behaviors (no user command — Claude does this while working)

- **After editing files in `<dir>/`** → refresh `<dir>/CLAUDE.md`'s `<!-- zr:files -->` block.
- **After creating or deleting a `<dir>/CLAUDE.md`** → refresh root's `<!-- zr:routing -->` block.
- **Before reading an unfamiliar file** → consult the surrounding `<!-- zr:files -->` block first; only `Read` if the summary is insufficient.

### How to refresh a files block

1. List files **in that directory only** — sub-subdirectories have their own CLAUDE.md.
2. Skip: binaries, files >1MB, `.env*`, and standard ignores: `node_modules`, `.git`, `dist`, `build`, `zig-out`, `target`, `__pycache__`, `.memory`, `vendor`, `third_party`, `external`, `references`.
3. Per file, write: `` - `<filename>` — <description> (~<n> tok) ``
   - Description: pick the single most informative line. Priority — known filename, markdown H1, docblock or leading non-license comment, exported symbols. Cap at 100 chars.
   - Tokens: `ceil(chars / 4)`.
4. Sort alphabetically. Replace contents between the markers; append a fresh block if missing.

### How to refresh the routing block

Between `<!-- zr:routing -->` markers in root CLAUDE.md, write one line per non-root `**/CLAUDE.md`, sorted by path. Apply the same standard ignores as the files block (so e.g. `references/foo/CLAUDE.md` doesn't pollute the table):

```
→ src: src/CLAUDE.md
→ src/api: src/api/CLAUDE.md
```

## Memory model

When editing or making decisions:
- ADRs and recurring-mistake entries → `.memory/decisions.md`
- Reusable code patterns → `.memory/patterns.md` (reference these from subdirectory CLAUDE.md instead of duplicating)
- Uncertain or inferred items → `.memory/inbox.md` (never canonical; promote only with user confirmation)

Don't overwrite ADRs — mark them superseded and add a new entry. Never write secrets or user data.
