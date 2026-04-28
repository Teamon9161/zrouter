# zrouter templates

Skeletons for files `init` creates. Brackets are filled in per project — don't hard-code per-language rules.

## Root CLAUDE.md

```markdown
# Project: [Name]

## Stack
- [Language / framework / runtime]
- [Build / package manager]
- [Key dependencies, or "none"]

## Critical Rules
<!-- ask the user during init; leave this comment if they have none -->

## zrouter
- Reading an unknown file: first read the surrounding `<dir>/CLAUDE.md`'s `<!-- zr:files -->` block (or `zrouter query <path> --json` once the CLI ships).
- Editing in `<dir>/`: read `<dir>/CLAUDE.md` first; check `.memory/decisions.md` for ADRs and Do-Not-Repeat entries.
- After editing: refresh that directory's files block. Log decisions to `.memory/decisions.md`, patterns to `.memory/patterns.md`, guesses to `.memory/inbox.md`.
- `<!-- zr:files -->` and `<!-- zr:routing -->` blocks are tool-managed; everything else is yours.

<!-- zr:routing -->
<!-- /zr:routing -->
```

Target: ≤ 250 tokens excluding the routing block.

## Subdirectory CLAUDE.md

```markdown
# <dir>/

## Purpose
[one sentence]

## Conventions
- [...]

## Gotchas
- [...]

<!-- zr:files -->
<!-- /zr:files -->
```

Target: ≤ 300 tokens excluding the files block.

### Example after first scan

```markdown
# src/

## Purpose
Library and CLI entry points.

## Conventions
- `main.zig` is the CLI entry; `root.zig` is the library entry
- Process-lifetime allocations come from `init.arena.allocator()`

## Gotchas
- `std.Io` writers need `flush()` before exit or output is lost

<!-- zr:files -->
- `main.zig` — main, testOne (~640 tok)
- `root.zig` — printAnotherMessage (~140 tok)
<!-- /zr:files -->
```

## .memory/decisions.md

```markdown
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

(none yet)
```

## .memory/patterns.md

```markdown
# Patterns

For each pattern:
- **When to use**
- **Implementation** (minimum code)
- **Gotchas**

Reference these from subdirectory CLAUDE.md instead of duplicating.

---

(none yet)
```

## .memory/inbox.md

```markdown
# Inbox

Uncertain inferences. **Never authoritative** — Claude reads `decisions.md` and `patterns.md` for confirmed knowledge and writes here for guesses.

Triage:
- Confirm → move to `decisions.md` or `patterns.md`, delete here
- Reject → delete
- Revise → edit, then promote

---

### [Title] ([Date])
**Kind:** decision | pattern
**Confidence:** high | medium | low
**Evidence:** [files or config]
**Observed:** [what was seen]
**Proposed:** [what would be added if confirmed]
```
