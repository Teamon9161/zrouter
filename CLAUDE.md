# Project: zrouter

## Stack
- Language: Zig (minimum 0.16.0)
- Build: build.zig + build.zig.zon
- Dependencies: zig-toml

## Critical Rules
<!-- none yet -->

## zrouter
- Reading an unknown file: first consult the loaded/current directory's `<!-- zr:files -->` block; use `zrouter query <path> --json` only when the surrounding CLAUDE.md is not loaded or the file is outside the current routed context.
- Editing in `<dir>/`: read `<dir>/CLAUDE.md` first; check `.memory/decisions.md` for ADRs and Do-Not-Repeat entries.
- After editing: run `zrouter refresh <dir>` (or `zrouter refresh . -r --create` for hierarchy changes). Log decisions to `.memory/decisions.md`, patterns to `.memory/patterns.md`, guesses to `.memory/inbox.md`.
- `<!-- zr:files -->` and `<!-- zr:routing -->` blocks are tool-managed; everything else is yours.

<!-- zr:routing -->
<!-- /zr:routing -->
<!-- zr:files -->
- `.gitattributes` —  (~5 tok)
- `.gitignore` —  (~16 tok)
- `PLAN.md` — zrouter 设计与实施计划 (~3252 tok)
- `build.zig` — pub fn build (~456 tok)
- `build.zig.zon` — Zig package manifest (~1163 tok)
- `install.ps1` —  (~1554 tok)
- `install.sh` —  (~1228 tok)
- `skill/`
  - `SKILL.md` — zrouter (~2153 tok)
  - `configuration.md` — zrouter configuration (~1212 tok)
  - `templates.md` — zrouter templates (~796 tok)
- `src/`
  - `assets/default.toml` — zrouter built-in defaults — embedded at compile time. (~926 tok)
  - `claude_md.zig` — pub fn replaceBlock, ensureBlock, removeBlock, buildFilesBlock, buildRoutingBlock (~1402 tok)
  - `config.zig` — pub fn load (~1770 tok)
  - `desc.zig` — pub fn extract (~3842 tok)
  - `main.zig` — pub fn main (~5670 tok)
  - `root.zig` —  (~51 tok)
  - `walker.zig` — pub fn listFiles, listFilesForIndex (~4176 tok)
<!-- /zr:files -->
