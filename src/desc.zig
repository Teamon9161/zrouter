const std = @import("std");
const config = @import("config.zig");

const max_names = 5;

/// Extract a one-line description from file content.
/// known_files is checked first (project > global > embedded defaults).
/// Returns null if no meaningful description can be derived.
pub fn extract(filename: []const u8, content: []const u8, allocator: std.mem.Allocator, known_files: []const config.KnownFile) !?[]const u8 {
    if (knownFile(filename, known_files)) |desc| return desc;

    const ext = std.fs.path.extension(filename);
    if (std.mem.eql(u8, ext, ".md")) return extractMarkdown(content);
    if (std.mem.eql(u8, ext, ".zig")) return extractZig(content, allocator);
    if (std.mem.eql(u8, ext, ".ts") or std.mem.eql(u8, ext, ".tsx") or
        std.mem.eql(u8, ext, ".js") or std.mem.eql(u8, ext, ".jsx") or
        std.mem.eql(u8, ext, ".mjs") or std.mem.eql(u8, ext, ".mts")) return extractTsJs(content, allocator);
    if (std.mem.eql(u8, ext, ".py") or std.mem.eql(u8, ext, ".pyi")) return extractPython(content, allocator);
    if (std.mem.eql(u8, ext, ".go")) return extractGo(content, allocator);
    if (std.mem.eql(u8, ext, ".rs")) return extractRust(content, allocator);

    return extractHeaderComment(content);
}

// ── Known files ──────────────────────────────────────────

fn knownFile(filename: []const u8, known_files: []const config.KnownFile) ?[]const u8 {
    const base = std.fs.path.basename(filename);
    for (known_files) |k| {
        if (std.mem.eql(u8, base, k.name)) return k.desc;
    }
    return null;
}

// ── Markdown ─────────────────────────────────────────────

fn extractMarkdown(content: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const t = std.mem.trim(u8, line, " \t\r");
        // Strip leading '#' markers and return the heading text
        if (std.mem.startsWith(u8, t, "### ")) return t[4..];
        if (std.mem.startsWith(u8, t, "## ")) return t[3..];
        if (std.mem.startsWith(u8, t, "# ")) return t[2..];
    }
    return null;
}

// ── Zig ──────────────────────────────────────────────────

fn extractZig(content: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, content, '\n');

    while (lines.next()) |line| {
        if (names.items.len >= max_names) break;
        const t = std.mem.trim(u8, line, " \t\r");
        if (std.mem.startsWith(u8, t, "pub fn ")) {
            const name = extractIdent(t["pub fn ".len..]);
            if (name.len > 0) try names.append(allocator, name);
        }
    }

    if (names.items.len > 0) {
        return try std.fmt.allocPrint(allocator, "pub fn {s}", .{try joinNames(names.items, allocator)});
    }
    return extractHeaderComment(content);
}

// ── TypeScript / JavaScript ──────────────────────────────

fn extractTsJs(content: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, content, '\n');

    while (lines.next()) |line| {
        if (names.items.len >= max_names) break;
        const t = std.mem.trim(u8, line, " \t\r");
        if (!std.mem.startsWith(u8, t, "export ")) continue;

        var rest = t["export ".len..];
        if (std.mem.startsWith(u8, rest, "default ")) rest = rest["default ".len..];
        if (std.mem.startsWith(u8, rest, "async ")) rest = rest["async ".len..];

        const keywords = [_][]const u8{ "function ", "const ", "class ", "interface ", "type ", "enum " };
        for (&keywords) |kw| {
            if (std.mem.startsWith(u8, rest, kw)) {
                const name = extractIdent(rest[kw.len..]);
                if (name.len > 0) {
                    try names.append(allocator, try std.fmt.allocPrint(allocator, "export {s}{s}", .{ kw, name }));
                }
                break;
            }
        }
    }

    if (names.items.len > 0) return try joinNames(names.items, allocator);
    return extractHeaderComment(content);
}

// ── Python ───────────────────────────────────────────────

fn extractPython(content: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    var classes: std.ArrayList([]const u8) = .empty;
    var fns: std.ArrayList([]const u8) = .empty;
    var vars: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, content, '\n');

    while (lines.next()) |line| {
        if (classes.items.len + fns.items.len >= max_names) break;
        // Only top-level definitions (not indented)
        if (line.len > 0 and (line[0] == ' ' or line[0] == '\t')) continue;
        const t = std.mem.trim(u8, line, " \t\r");
        if (std.mem.startsWith(u8, t, "class ")) {
            const name = extractIdent(t["class ".len..]);
            if (name.len > 0) try classes.append(allocator, name);
        } else if (std.mem.startsWith(u8, t, "def ") or std.mem.startsWith(u8, t, "async def ")) {
            const prefix = if (std.mem.startsWith(u8, t, "async ")) "async def ".len else "def ".len;
            const name = extractIdent(t[prefix..]);
            if (name.len > 0 and !std.mem.startsWith(u8, name, "_")) try fns.append(allocator, name);
        } else if (vars.items.len < max_names and t.len > 1 and std.ascii.isLower(t[0])) {
            // Module-level assignment: snake_case_name = ... (ctypes FFI, re-exports, etc.)
            const name = extractIdent(t);
            if (name.len > 1) {
                const after = std.mem.trimStart(u8, t[name.len..], " \t");
                if (after.len >= 2 and after[0] == '=' and after[1] != '=') {
                    try vars.append(allocator, name);
                }
            }
        }
    }

    var parts: std.ArrayList([]const u8) = .empty;
    if (classes.items.len > 0) {
        try parts.append(allocator, try std.fmt.allocPrint(allocator, "class {s}", .{try joinNames(classes.items, allocator)}));
    }
    if (fns.items.len > 0) {
        try parts.append(allocator, try std.fmt.allocPrint(allocator, "def {s}", .{try joinNames(fns.items, allocator)}));
    }
    if (parts.items.len > 0) return try joinNames(parts.items, allocator);
    // Fallback: module-level variable assignments (e.g. ctypes FFI bindings)
    if (vars.items.len > 0) return try joinNames(vars.items, allocator);
    return extractHeaderComment(content);
}

// ── Go ───────────────────────────────────────────────────

fn extractGo(content: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, content, '\n');

    while (lines.next()) |line| {
        if (names.items.len >= max_names) break;
        const t = std.mem.trim(u8, line, " \t\r");
        if (!std.mem.startsWith(u8, t, "func ")) continue;

        var rest = t["func ".len..];

        // Skip receiver: func (r Receiver) Name(...)
        if (rest.len > 0 and rest[0] == '(') {
            const close = std.mem.indexOfScalar(u8, rest, ')') orelse continue;
            rest = std.mem.trimStart(u8, rest[close + 1 ..], " ");
        }

        const name = extractIdent(rest);
        // Only exported (uppercase first letter) functions
        if (name.len > 0 and std.ascii.isUpper(name[0])) try names.append(allocator, name);
    }

    if (names.items.len > 0) {
        return try std.fmt.allocPrint(allocator, "func {s}", .{try joinNames(names.items, allocator)});
    }
    return extractHeaderComment(content);
}

// ── Rust ─────────────────────────────────────────────────

fn skipGenericParams(s: []const u8) []const u8 {
    const rest = std.mem.trimStart(u8, s, " \t");
    if (rest.len == 0 or rest[0] != '<') return rest;
    var depth: usize = 0;
    for (rest, 0..) |c, i| {
        if (c == '<') depth += 1 else if (c == '>') {
            depth -= 1;
            if (depth == 0) return std.mem.trimStart(u8, rest[i + 1 ..], " \t");
        }
    }
    return rest;
}

fn extractRust(content: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    var pub_names: std.ArrayList([]const u8) = .empty;
    var impl_types: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, content, '\n');

    while (lines.next()) |line| {
        if (pub_names.items.len >= max_names) break;
        const t = std.mem.trim(u8, line, " \t\r");

        // Skip attribute lines like #[derive(...)]
        if (std.mem.startsWith(u8, t, "#[")) continue;

        // Extract impl block types (fallback for impl-only files)
        if (impl_types.items.len < max_names and
            (std.mem.startsWith(u8, t, "impl ") or std.mem.startsWith(u8, t, "impl<")))
        {
            var rest2 = skipGenericParams(std.mem.trimStart(u8, t["impl".len..], " \t"));
            const name = if (std.mem.indexOf(u8, rest2, " for ")) |for_idx| blk: {
                const after = skipGenericParams(std.mem.trimStart(u8, rest2[for_idx + " for ".len..], " \t"));
                break :blk extractIdent(after);
            } else extractIdent(rest2);
            if (name.len > 0) {
                var dup = false;
                for (impl_types.items) |e| if (std.mem.eql(u8, e, name)) { dup = true; break; };
                if (!dup) try impl_types.append(allocator, name);
            }
            continue;
        }

        if (!std.mem.startsWith(u8, t, "pub ")) continue;
        var rest = t["pub ".len..];

        // pub use re-exports
        if (std.mem.startsWith(u8, rest, "use ")) {
            var use_rest = std.mem.trim(u8, rest["use ".len..], "; \t\r");
            const name = if (std.mem.lastIndexOf(u8, use_rest, " as ")) |as_idx|
                extractIdent(std.mem.trimStart(u8, use_rest[as_idx + " as ".len..], " \t"))
            else if (std.mem.lastIndexOfScalar(u8, use_rest, ':')) |colon|
                extractIdent(use_rest[colon + 1 ..])
            else
                extractIdent(use_rest);
            if (name.len > 0) try pub_names.append(allocator, name);
            continue;
        }

        // Skip qualifiers: unsafe, extern "C", default
        while (true) {
            rest = std.mem.trimStart(u8, rest, " ");
            if (std.mem.startsWith(u8, rest, "unsafe ")) {
                rest = rest["unsafe ".len..];
            } else if (std.mem.startsWith(u8, rest, "default ")) {
                rest = rest["default ".len..];
            } else if (std.mem.startsWith(u8, rest, "extern ")) {
                rest = rest["extern ".len..];
                if (rest.len > 0 and rest[0] == '"') {
                    const close = std.mem.indexOfScalar(u8, rest[1..], '"') orelse break;
                    rest = rest[1 + close + 1 ..];
                }
            } else {
                break;
            }
        }

        const keywords = [_][]const u8{ "fn ", "struct ", "enum ", "trait ", "type ", "union " };
        for (&keywords) |kw| {
            if (std.mem.startsWith(u8, rest, kw)) {
                const name = extractIdent(rest[kw.len..]);
                if (name.len > 0) try pub_names.append(allocator, name);
                break;
            }
        }
    }

    if (pub_names.items.len > 0) {
        return try std.fmt.allocPrint(allocator, "pub {s}", .{try joinNames(pub_names.items, allocator)});
    }
    if (impl_types.items.len > 0) {
        return try std.fmt.allocPrint(allocator, "impl {s}", .{try joinNames(impl_types.items, allocator)});
    }
    return extractHeaderComment(content);
}

// ── Header comment fallback ──────────────────────────────

fn extractHeaderComment(content: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, content, '\n');
    var idx: usize = 0;

    while (lines.next()) |line| : (idx += 1) {
        if (idx > 30) break;
        const t = std.mem.trim(u8, line, " \t\r");
        if (t.len == 0) continue;
        if (idx == 0 and std.mem.startsWith(u8, t, "#!")) continue;
        if (isBoilerplate(t)) continue;
        if (std.mem.startsWith(u8, t, "package ") or
            std.mem.startsWith(u8, t, "module ") or
            std.mem.startsWith(u8, t, "import ") or
            std.mem.startsWith(u8, t, "from ") or
            std.mem.startsWith(u8, t, "#include") or
            std.mem.startsWith(u8, t, "use ")) continue;

        if (std.mem.startsWith(u8, t, "//")) {
            const text = std.mem.trim(u8, t[2..], " \t");
            if (text.len > 0 and !isBoilerplate(text) and !std.mem.startsWith(u8, text, "use ")) return text;
        } else if (std.mem.startsWith(u8, t, "#") and !std.mem.startsWith(u8, t, "#!")) {
            const text = std.mem.trim(u8, t[1..], " \t");
            if (text.len > 0 and !isBoilerplate(text)) return text;
        } else if (std.mem.startsWith(u8, t, "--")) {
            const text = std.mem.trim(u8, t[2..], " \t");
            if (text.len > 0 and !isBoilerplate(text)) return text;
        } else {
            return null;
        }
    }
    return null;
}

fn isBoilerplate(s: []const u8) bool {
    if (s.len == 0) return false;
    var lower_buf: [128]u8 = undefined;
    if (s.len > lower_buf.len) return false;
    const lower = std.ascii.lowerString(lower_buf[0..s.len], s);
    const markers = [_][]const u8{
        "copyright", "license", "spdx", "all rights reserved",
        "generated by", "auto-generated", "automatically generated",
        "strict", "eslint", "pragma", "@ts-", "@eslint-",
    };
    for (&markers) |m| {
        if (std.mem.indexOf(u8, lower, m) != null) return true;
    }
    return false;
}

// ── Helpers ──────────────────────────────────────────────

fn extractIdent(text: []const u8) []const u8 {
    const t = std.mem.trimStart(u8, text, " \t\r");
    var end: usize = 0;
    for (t, 0..) |c, i| {
        if (!std.ascii.isAlphanumeric(c) and c != '_') break;
        end = i + 1;
    }
    return t[0..end];
}

fn joinNames(names: []const []const u8, allocator: std.mem.Allocator) ![]u8 {
    var result: std.ArrayList(u8) = .empty;
    for (names, 0..) |name, i| {
        if (i > 0) try result.appendSlice(allocator, ", ");
        try result.appendSlice(allocator, name);
    }
    return result.items;
}
