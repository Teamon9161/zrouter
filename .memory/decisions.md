# Decisions

ADR format:
- **Status:** active | superseded | deprecated
- **Context:** what prompted this
- **Decision:** what was chosen
- **Alternatives:** rejected options + brief reasoning
- **Consequences:** implications for future work

Never delete — supersede.

---

## Do-Not-Repeat

Recurring mistakes. Each entry: date, what went wrong, why, how to avoid.

- (none yet)

---

## ADRs

### 2026-04-29 — Release self-update and skill installation UX
- **Status:** active
- **Context:** zrouter needs published binaries, a `zrouter update` command, and clear installation for the Claude Code skill that makes zrouter useful during agent workflows.
- **Decision:** Publish GitHub release assets with checksums, embed installer scripts in the binary for self-update, and have installers offer zrouter skill installation only when the `skill` CLI is already available. Otherwise they print `skill -A @Teamon9161/zrouter/skill --claude` as the manual step.
- **Alternatives:** Auto-download/install the `skill` CLI from the zrouter installer; rejected because it adds another trust boundary and more brittle cross-platform logic. Use raw GitHub URLs for skill installation; rejected as primary docs because the current `skill` parser explicitly supports `@owner/repo/path`.
- **Consequences:** Binary install/update remains simple and auditable. Users still get clear guidance that Claude Code integration requires the zrouter skill, while environments without `skill` are not mutated unexpectedly.

### 2026-04-29 — Inline small directories into parent indexes
- **Status:** active
- **Context:** Full-tree `refresh -r --create` created many shallow CLAUDE.md files, causing extra Read round trips before Claude still had to read source files for edits.
- **Decision:** Add scalar config `inline_max_files` (default 6). Directories whose filtered recursive file count is at or below the threshold are not auto-created as routing nodes; their file entries are inlined into the nearest routed parent. Transparent directories without their own CLAUDE.md are also inlined into the parent while their child routes are promoted. Add `respect_gitignore` (default true) so supported `.gitignore` rules are appended to `exclude`/`allow` before scanning.
- **Alternatives:** Always create per-directory CLAUDE.md; rejected because shallow directories become pure navigation overhead. Count only direct files; rejected because roots with few direct files but large subtrees would be over-inlined. Require users to duplicate `.gitignore` rules in `.zrouter/config.toml`; rejected as unnecessary configuration friction.
- **Consequences:** Parent indexes get slightly larger for small subtrees, but fewer CLAUDE.md files need to be read during normal edits. Users can raise/lower the threshold globally or per project, and can disable `.gitignore` loading with `respect_gitignore = false`.

### 2026-04-29 — Gitignore-ish excludes and transparent routing directories
- **Status:** active
- **Context:** Hierarchical routing should not waste hops on generic container directories like `src/`, and ignore config should cover directories, paths, and file extensions with one familiar syntax.
- **Decision:** Use `exclude` and `allow` as gitignore-ish pattern lists. `allow` uses the same matcher and overrides `exclude`. `transparent_dirs` remains a list of exact directory names whose children are promoted in routing and skipped by `refresh -r --create`.
- **Alternatives:** Directory-name regexes with vendored mvzr; rejected because path-specific ignores and extension ignores are more naturally expressed with gitignore-style patterns. Full `.gitignore` semantics with `!`; rejected because separate `allow` avoids order-dependent rules.
- **Consequences:** Users can write patterns like `fixtures/`, `/vendor/`, `pybond/tests/fixtures/`, and `*.py[co]`. Because zrouter has not shipped yet, old config fields were removed instead of supported.
