# Project: zrouter

## Stack
- Language: Zig (minimum 0.16.0)
- Build: build.zig + build.zig.zon
- Dependencies: zig-toml

## Critical Rules
<!-- ask the user when ready; left as placeholder for now -->

## zrouter
- Reading an unknown file: first consult the loaded/current directory's `<!-- zr:files -->` block; use `zrouter query <path> --json` only when the surrounding CLAUDE.md is not loaded or the file is outside the current routed context.
- Editing in `<dir>/`: read `<dir>/CLAUDE.md` first; check `.memory/decisions.md` for ADRs and Do-Not-Repeat entries.
- After editing: run `zrouter refresh <dir>` (or `zrouter refresh . -r --create` for hierarchy changes). Log decisions to `.memory/decisions.md`, patterns to `.memory/patterns.md`, guesses to `.memory/inbox.md`.
- `<!-- zr:files -->` and `<!-- zr:routing -->` blocks are tool-managed; everything else is yours.

<!-- zr:routing -->
<!-- /zr:routing -->
<!-- zr:files -->
- `.gitignore` —  (~14 tok)
- `PLAN.md` — zrouter 设计与实施计划 (~3196 tok)
- `build.zig` — pub fn build (~340 tok)
- `build.zig.zon` — Zig package manifest (~1125 tok)
- `skill/`
  - `SKILL.md` — zrouter (~2254 tok)
  - `configuration.md` — zrouter configuration (~1182 tok)
  - `templates.md` — zrouter templates (~761 tok)
- `src/`
  - `assets/default.toml` — zrouter built-in defaults — embedded at compile time. (~908 tok)
  - `claude_md.zig` — pub fn replaceBlock, ensureBlock, removeBlock, buildFilesBlock, buildRoutingBlock (~1371 tok)
  - `config.zig` — pub fn load (~1725 tok)
  - `desc.zig` — pub fn extract (~3756 tok)
  - `main.zig` — pub fn main (~4927 tok)
  - `root.zig` —  (~49 tok)
  - `walker.zig` — pub fn listFiles, listFilesForIndex, findSubdirsWithClaudeMd (~4062 tok)
<!-- /zr:files -->
