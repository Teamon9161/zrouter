# zrouter configuration

zrouter reads configuration from two optional TOML files:

1. Global: first existing platform path:
   - Linux/BSD: `$XDG_CONFIG_HOME/zrouter/config.toml`, then `~/.config/zrouter/config.toml`
   - macOS: `~/Library/Application Support/zrouter/config.toml`, then `~/.config/zrouter/config.toml`
   - Windows: `%APPDATA%\\zrouter\\config.toml`, then `%USERPROFILE%\\.config\\zrouter\\config.toml`
2. Project: `.zrouter/config.toml`

List fields are appended across layers. Scalar fields are overridden by the later layer. Project config overrides global config for scalar fields.

## Common fields

```toml
# chars / coefficient ≈ token count
token_coefficient = 4.0

# max bytes read from each file while extracting descriptions
max_content_size = 12288

# child subtrees with <= N filtered files are inlined into the parent index
inline_max_files = 12

# append supported root .gitignore rules to exclude/allow
respect_gitignore = true

# directories that should not appear as routing nodes; their children are promoted
transparent_dirs = ["src", "lib", "app", "pkg", "cmd", "internal"]

# paths to ignore, using zrouter's gitignore-ish pattern subset
exclude = ["target/", "*.py[co]"]

# paths to include even when they match exclude
allow = ["fixtures/schema.json"]

# opaque file names whose descriptions cannot be extracted from content
known_files = [{name = "schema.db", desc = "SQLite schema snapshot"}]
```

## `respect_gitignore`

When `respect_gitignore = true` (default), zrouter reads the root `.gitignore` and appends supported rules to `exclude` / `allow` before scanning. A normal line becomes an `exclude` rule; a `!pattern` line becomes an `allow` rule.

Unsupported `.gitignore` lines are skipped rather than interpreted incorrectly. Currently skipped: escaped patterns containing `\\`.

## `inline_max_files`

`refresh -r --create` creates CLAUDE.md files only for non-transparent directories whose filtered recursive file count is greater than `inline_max_files`. Smaller child subtrees are inlined into the nearest parent `zr:files` block. Lower the value to create more routing nodes; raise it to reduce CLAUDE.md read round trips.

## `exclude` and `allow`

`exclude` and `allow` use the same pattern syntax. zrouter first checks `exclude`; if a path matches `allow`, it is included again.

Examples:

```toml
exclude = [
  ".*/",                    # hidden/tooling dirs: .git, .claude, .pytest_cache, ...
  "__*__/",                 # Python dunder dirs: __pycache__, ...
  "target/",                # any directory named target
  "/vendor/",               # only vendor/ at the refresh root
  "pybond/tests/fixtures/",  # that path at any depth
  "/pybond/tests/fixtures/", # that path from the refresh root only
  "*.py[co]",               # .pyc and .pyo files
  "*.{not-supported}",      # brace expansion is not supported; write multiple rules
]

allow = [
  "fixtures/schema.json",
  "keep/a.pyc",
]
```

## Pattern syntax

Supported subset:

| Pattern | Meaning |
|---|---|
| `foo/` | any directory named `foo` |
| `/foo/` | `foo/` only at the refresh root |
| `a/b/` | path segment `a/b/` at any depth |
| `/a/b/` | `a/b/` only from the refresh root |
| `a.py` | any path component named `a.py` |
| `/a.py` | `a.py` only at the refresh root |
| `*` | any characters within one path component |
| `?` | one character within one path component |
| `**` | zero or more path components |
| `[abc]` | one character from the set |
| `[a-z]` | one character in the range |
| `[!a-z]` or `[^a-z]` | one character not in the range |

Not supported in zrouter config patterns: brace expansion (`*.{ppt,docx}`), POSIX character classes (`[[:digit:]]`). Write multiple patterns for multiple extensions.

In `.gitignore` import, `!pattern` is translated to `allow`. Full gitignore ordering semantics are not implemented.

## Transparent directories

`transparent_dirs` are exact directory names used only for routing. If a transparent directory has no CLAUDE.md, zrouter does not create one during `refresh -r --create`; instead, its files are inlined into the parent `zr:files` block and child CLAUDE.md files are promoted into the parent routing block. If the directory already has its own CLAUDE.md, that file wins and the parent routes to it.

Higher config layers can remove defaults with `!name` or clear the whole list with `!*`:

```toml
# remove only the default src entry, then add source
transparent_dirs = ["!src", "source"]

# replace all defaults
transparent_dirs = ["!*", "source"]
```

A project with no `src/CLAUDE.md` but with `src/bond/CLAUDE.md` will route as:

```markdown
- [src/bond/](src/bond/CLAUDE.md)
```

not:

```markdown
- [src/](src/CLAUDE.md)
```

