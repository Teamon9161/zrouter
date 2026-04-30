# zrouter

zrouter is a lightweight context router for Claude Code. It keeps project guidance close to the files it applies to by splitting one large `CLAUDE.md` into a small root file plus scoped `CLAUDE.md` files for meaningful directories.

The main goal is simple: install the binary, install the Claude Code skill, then tell Claude to initialize zrouter for your project.

## What it does

zrouter helps Claude Code spend less context on navigation and more context on the code that matters.

- Maintains `<!-- zr:files -->` blocks with one-line file summaries and rough token counts.
- Maintains `<!-- zr:routing -->` blocks with links to child directory context files.
- Lets the agent inspect summaries and outlines before reading full files.
- Keeps generated index content inside marker blocks, while leaving human-written guidance outside those blocks untouched.

## Install

### Linux / macOS

```sh
curl -fsSL https://raw.githubusercontent.com/Teamon9161/zrouter/master/install.sh | sh
```

### Windows PowerShell

```powershell
irm https://raw.githubusercontent.com/Teamon9161/zrouter/master/install.ps1 | iex
```

The installer downloads the latest release, verifies checksums, installs `zrouter`, and offers to install the Claude Code skill when the `skill` CLI is available.

If you need to install the skill manually:

```sh
skill -A @Teamon9161/zrouter/skill
```

Check the binary:

```sh
zrouter version
```

## From source

Requires Zig `0.16.0` or newer.

```sh
zig build --fetch -Doptimize=ReleaseSafe
```

The binary is written to:

```sh
zig-out/bin/zrouter
```

## Usage

Use zrouter from inside Claude Code, not as a set of commands you run by hand.

After installing the binary and skill, open Claude Code in your project and type:

```text
zrouter init
```

The skill guides Claude through setup. Claude will create or update the project context files, inspect generated indexes, and keep the zrouter marker blocks fresh as it works.

You can also ask Claude to remove zrouter from a project:

```text
zrouter deinit
```

Agent-only commands such as `zrouter refresh` and `zrouter query` are normally run by Claude automatically:

- `refresh` updates generated `zr:files` and `zr:routing` blocks after edits.
- `query` lets Claude inspect a file or directory before deciding whether to read it.

## How it works

zrouter follows a “route before reading” workflow:

1. The root `CLAUDE.md` stores project-wide rules and routing links.
2. Important subdirectories can have their own `CLAUDE.md` with local purpose, conventions, and gotchas.
3. zrouter owns the generated marker blocks:
   - `<!-- zr:files -->` lists local files, summaries, and token estimates.
   - `<!-- zr:routing -->` lists child context files.
4. Claude first checks the already-loaded file index, then asks zrouter for an outline if needed, and only reads full source files when summaries are not enough.
5. Small directories are inlined into the nearest parent index; larger directories become their own routing nodes.
6. Ignore rules use gitignore-style `exclude` / `allow` patterns and respect supported root `.gitignore` rules by default.

Marker blocks are tool-managed and may be overwritten on refresh. Text outside the marker blocks is human-owned and preserved.

## Supported extraction

Summary extraction supports Markdown, Zig, TypeScript/JavaScript, Python, Go, Rust, C/C++/Objective-C, Java, Ruby, Shell, JSON/TOML/YAML, plus generic leading comments.

Outline extraction supports Zig, TypeScript/JavaScript, Python, Go, Rust, C/C++/Objective-C, Java, Ruby, Shell, JSON/TOML/YAML, and Markdown headings.

Unsupported file types may still get token estimates or leading-comment summaries, but they do not have reliable structured outlines.
