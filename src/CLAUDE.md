# src

## Purpose
Core zrouter CLI source code.

## Conventions
- Zig 0.16 std.Io API throughout
- Arena allocation for all temporary memory
<!-- zr:files -->
- `root.zig` —  (~49 tok)
- `main.zig` — pub fn main (~2119 tok)
- `desc.zig` — pub fn extract (~2825 tok)
- `config.zig` — pub fn load (~346 tok)
- `walker.zig` — pub fn listFiles, findSubdirsWithClaudeMd (~864 tok)
- `claude_md.zig` — pub fn replaceBlock, ensureBlock, buildFilesBlock, buildRoutingBlock (~797 tok)
<!-- /zr:files -->
