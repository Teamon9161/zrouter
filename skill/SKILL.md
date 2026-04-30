---
name: zrouter
version: 0.1.0-phase1
description: Per-directory CLAUDE.md with auto-maintained file indexes and routing. Use for setting up scoped agent context and keeping indexes fresh. Triggers on "zrouter init" and "zr ..." shorthand.
---

# zrouter

Splits one big CLAUDE.md into a small root + routed CLAUDE.md files for meaningful code directories. Each CLAUDE.md ends with auto-managed `<!-- zr:files -->` and `<!-- zr:routing -->` blocks, so a single read gives Claude local conventions, direct file summaries, and the next routing choices.

The user types `init` once. Init writes durable operating instructions into root CLAUDE.md so future sessions can navigate, refresh indexes, and maintain project memory without relying on this skill to trigger again.

## The token-saving move

Before opening an unfamiliar file, first consult the loaded/current directory's `<!-- zr:files -->` block. Use `zrouter query <path> --json` only when the surrounding CLAUDE.md is not loaded or the file is outside the current routed context: file paths return one summary; directory paths return the filtered files/routes/inline_dirs index. If the summary is too thin, run `zrouter query <path> --outline` before `Read`: outline returns the file header comment plus top-level structure/signatures, but does not include function-level comments. Only `Read` the file when summary/outline are insufficient.

Supported extraction:
- Summary: Markdown, Zig, TypeScript/JavaScript, Python, Go, Rust, C/C++/Objective-C, Java, Ruby, Shell, JSON/TOML/YAML, plus generic leading comments.
- Outline: Zig, TypeScript/JavaScript, Python, Go, Rust, C/C++/Objective-C, Java, Ruby, Shell, JSON/TOML/YAML, Markdown headings. Unsupported file types may still return a header comment/token count, but do not provide reliable structure.
- Outline deliberately excludes function-level comments. Use `Read` when function docs or implementation details matter.

## Project layout

```
CLAUDE.md            # root: stack, rules, routing block
.memory/
  decisions.md       # ADRs + Do-Not-Repeat
  patterns.md        # reusable code patterns
  inbox.md           # uncertain inferences (never authoritative)
<dir>/CLAUDE.md      # per-directory: purpose, conventions, gotchas, files/routing blocks
```

Templates for every file are in `templates.md` — single source of truth for format.

Configuration reference is in `configuration.md`. Consult it when the user wants to ignore paths, allow ignored files, tune routing, or edit `.zrouter/config.toml` / the platform global config.

zrouter respects supported root `.gitignore` rules by default (`respect_gitignore = true`). `.gitignore` is still the user's call: suggest additions when generated indexes contain irrelevant paths, but don't auto-edit user ignore rules without confirmation.

## Marker blocks

- `<!-- zr:files -->` ... `<!-- /zr:files -->` — files for this routing node, including small child subtrees inlined by `inline_max_files`
- `<!-- zr:routing -->` ... `<!-- /zr:routing -->` — routed child CLAUDE.md files

Inside the markers: tool-managed; manual edits overwritten on next refresh.
Outside the markers: human-owned; zrouter never touches.

## User commands

### `init`

1. Detect stack from signature files (`build.zig`, `package.json`, `Cargo.toml`, `go.mod`, `pyproject.toml`, ...), README, and existing docs.
2. Prepare root CLAUDE.md human sections above the marker blocks:
   - Stack: repository-level component map — major crates/packages/apps/directories, their roles, and dependency flow. This may include the repo's one-sentence purpose when it reads naturally.
   - Purpose: add only if Stack does not already clearly state what the whole repository is for. Avoid duplicating Stack.
   - Supported Extraction: short note based on detected languages; mention outline only for supported extensions.
   - Code Navigation: durable zrouter usage rules for future sessions:
     ```markdown
     ## Code Navigation

     Before reading unfamiliar files:
     1. Check the loaded/current `<!-- zr:files -->` block first.
     2. If the file or directory is outside the loaded routed context, run `zrouter query <path> --json`.
     3. If the summary is too thin, run `zrouter query <path> --outline`.
     4. Only read the file when summary/outline are insufficient.

     After adding, deleting, or moving files, run `zrouter refresh <dir>` for the affected directory; if routed CLAUDE.md files were created or removed, run `zrouter refresh <parent>` or `zrouter refresh . -r`.
     ```
   - Project Memory: durable memory rules for future sessions:
     ```markdown
     ## Project Memory

     Use `.memory/` for durable project knowledge that is not obvious from current code or git history:
     - `.memory/decisions.md` — ADRs and do-not-repeat decisions. Check before architectural or behavior changes; append new decisions and mark old ones `[SUPERSEDED]` instead of overwriting.
     - `.memory/patterns.md` — reusable code patterns. Check before implementing common functionality; update when a pattern becomes reusable.
     - `.memory/inbox.md` — uncertain inferences. Never treat as canonical or promote without user confirmation.

     After work, update relevant CLAUDE.md files when conventions or routing context change, and update `.memory/` only for durable decisions/patterns/inferences. Never record secrets, credentials, or user data.
     ```
   Keep Code Navigation and Project Memory in human-owned CLAUDE.md content, not inside generated marker blocks, because future sessions should not need this skill to trigger for routine behavior.
3. **Ask** the user whether there are project-specific Critical Rules. Keep this section short, leave it empty if there are none, and don't repeat global agent instructions.
4. Decide subdirectories. Greenfield (≤2 source dirs) → root only. Brownfield → use `zrouter refresh . -r --create` and review the generated indexes before writing human sections.
5. Create `.memory/` skeletons.
6. Populate files/routing blocks using the refresh logic below.
7. Inspect `<!-- zr:files -->` blocks for irrelevant generated, fixture, cache, binary, vendored, or benchmark-data paths. If the index looks noisy, stop and suggest `.gitignore`, `exclude`, or `allow` changes; rerun refresh before writing Purpose/Conventions/Stack. Do not paper over noisy indexes with prose.
8. For each newly created subdirectory CLAUDE.md whose generated index looks relevant, write human content **above** the `<!-- zr:files -->` marker:
   - Purpose: always one sentence explaining the directory's role.
   - Stack: optional local structure map for this directory's children/modules/layers, not a repeat of the root Stack. Add it when the directory contains meaningful internal structure, a distinct runtime/language/framework/binding layer, or multiple submodules whose roles are not obvious from filenames.
   - Conventions and Gotchas: include anything worth knowing before touching files here — one bullet is enough. If a key extracted function/type/file/folder needs purpose or intent beyond its generated symbol list, explain it here rather than inside the marker block. Skip a section only if there's truly nothing to add.

### `deinit`

Inverse of `init`. Run from the project root. Removes the `<!-- zr:files -->` and `<!-- zr:routing -->` blocks from CLAUDE.md files, leaving all human-written content intact.

```
zrouter deinit                   Strip zr: blocks from ./CLAUDE.md only
zrouter deinit -r                Also strip blocks from every subdirectory CLAUDE.md
zrouter deinit -r --delete-file  Strip ./CLAUDE.md; delete all subdirectory CLAUDE.md files entirely
```

`--delete-file` never deletes the root `./CLAUDE.md` — only subdirectory ones.

## Automatic behaviors (no user command — Claude does this while working)

- **After editing, adding, deleting, or moving files in `<dir>/`** → run `zrouter refresh <dir>` to refresh that directory's files/routing blocks.
- **After creating, deleting, or moving a `<dir>/CLAUDE.md`** → run `zrouter refresh <parent>` or `zrouter refresh . -r` to refresh routing.
- **When bootstrapping an existing project** → run `zrouter refresh . -r --create`, then inspect generated CLAUDE.md files. If indexes include irrelevant paths, suggest ignore/config changes and refresh again before writing Purpose/Stack/Conventions.
- **Before reading an unfamiliar file** → consult the loaded/current `<!-- zr:files -->` block first; use `zrouter query <path> --json` only when the surrounding CLAUDE.md is not loaded or the file is outside the current routed context. If that is not enough, use `zrouter query <path> --outline` for the file header comment plus top-level structure/signatures. Query a directory when you need the local filtered index without reading another CLAUDE.md.

### How to refresh a files block

1. List files for this routing node: direct files plus child subtrees whose filtered recursive file count is `<= inline_max_files`; routed child subtrees stay in `zr:routing` instead.
2. Skip: binaries, files >1MB, paths matching supported root `.gitignore` rules when `respect_gitignore = true`, and paths matching `exclude` gitignore-ish patterns unless an `allow` pattern matches.
3. Per file, write: `` - `<filename>` — <description> (~<n> tok) ``. For inlined child paths, group by the first directory as `` - `<dir>/` `` with two-space-indented child entries.
   - Description: pick the single most informative line. Priority — known filename, markdown H1, docblock or leading non-license comment, exported symbols. Cap at 100 chars.
   - Tokens: `ceil(chars / 4)`.
4. Sort alphabetically, preserving grouped child paths under their directory heading. Replace contents between the markers; append a fresh block if missing.

### How to refresh the routing block

Between `<!-- zr:routing -->` markers, write one line per routed child CLAUDE.md, sorted by path. Apply `exclude`/`allow` gitignore-ish patterns. For `transparent_dirs` (`src`, `lib`, `app`, `pkg`, `cmd`, `internal` by default), skip the transparent directory itself, inline only its direct files, and promote/judge its child directories separately:

```markdown
- [src/bond/](src/bond/CLAUDE.md)
- [src/future/](src/future/CLAUDE.md)
```

Use `zrouter refresh <dir> -r --create` to create CLAUDE.md files for useful non-transparent directories whose filtered recursive file count exceeds `inline_max_files`; smaller subtrees are inlined into their nearest routed parent. Existing CLAUDE.md files always win over transparent-dir promotion. If a transparent directory's direct files make the parent index too large, create a CLAUDE.md in that transparent directory or remove it from `transparent_dirs` with `!name`.

## What the file scan captures — and what it doesn't

`zr:files` answers **what exists**: exported symbol names and token counts. It does not explain purpose, behaviour, or intent.

`zrouter query <path> --outline` is the next step before `Read` when a one-line summary is not enough. It shows the file header comment and top-level structure/signatures. It deliberately does not include function-level comments; those require reading the file or a future docs/full-outline detail mode.

Fill the gap in the human-written sections above `<!-- zr:files -->`:
- **Purpose** — what the root project or routed directory/module is for, in one sentence.
- **Stack** — at root, a repository-level component map; in subdirectories, an optional local structure map for child modules/layers when useful.
- **Conventions** — recurring patterns a reader must know before touching the code.
- **Gotchas** — non-obvious behaviour, edge cases, or constraints the scanner can't infer (private helpers with surprising side-effects, cross-file invariants, etc.).

Don't annotate individual files inside the markers — the tool overwrites them on the next refresh. If a key type, function, file, or folder needs purpose or intent explained, put it in the human-written sections, not next to its filename.

## Where conventions live

Write a convention in the CLAUDE.md of the directory where it is implemented. Outer directories reference by routing link, not by repeating the rule.

Example: a parsing quirk in `src/parser/` goes in `src/parser/CLAUDE.md`, not in the root.

Cross-cutting rules that apply everywhere (project-wide coding style, security constraints) belong in the root CLAUDE.md only.

## Memory model

When editing or making decisions:
- ADRs and recurring-mistake entries → `.memory/decisions.md`
- Reusable code patterns → `.memory/patterns.md` (reference these from subdirectory CLAUDE.md instead of duplicating)
- Uncertain or inferred items → `.memory/inbox.md` (never canonical; promote only with user confirmation)

Don't overwrite ADRs — mark them superseded and add a new entry. Never write secrets or user data.
