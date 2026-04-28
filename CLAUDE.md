# Project: zrouter

## Stack
- Language: Zig (minimum 0.16.0)
- Build: build.zig + build.zig.zon
- Dependencies: none

## Critical Rules
<!-- ask the user when ready; left as placeholder for now -->

## zrouter
- Reading an unknown file: first read the surrounding `<dir>/CLAUDE.md`'s `<!-- zr:files -->` block (or `zrouter query <path> --json` once the CLI ships).
- Editing in `<dir>/`: read `<dir>/CLAUDE.md` first; check `.memory/decisions.md` for ADRs and Do-Not-Repeat entries.
- After editing: refresh that directory's files block. Log decisions to `.memory/decisions.md`, patterns to `.memory/patterns.md`, guesses to `.memory/inbox.md`.
- `<!-- zr:files -->` and `<!-- zr:routing -->` blocks are tool-managed; everything else is yours.

<!-- zr:routing -->
- src/
<!-- /zr:routing -->
<!-- zr:files -->
- `build.zig.zon` — Zig package manifest (~1073 tok)
- `build.zig` — Zig build script (~2121 tok)
- `PLAN.md` — # zrouter 设计与实施计划 (~1846 tok)
<!-- /zr:files -->
