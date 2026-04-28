const std = @import("std");

/// Extract a one-line description from file content.
/// Returns null if no meaningful description can be derived.
pub fn extract(filename: []const u8, content: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    if (knownFile(filename)) |desc| return desc;

    const ext = std.fs.path.extension(filename);
    if (std.mem.eql(u8, ext, ".md")) return extractMarkdown(content);
    if (std.mem.eql(u8, ext, ".zig")) return extractZig(content, allocator);
    if (std.mem.eql(u8, ext, ".ts") or std.mem.eql(u8, ext, ".tsx") or
        std.mem.eql(u8, ext, ".js") or std.mem.eql(u8, ext, ".jsx") or
        std.mem.eql(u8, ext, ".mjs") or std.mem.eql(u8, ext, ".mts")) return extractTsJs(content, allocator);
    if (std.mem.eql(u8, ext, ".py")) return extractPython(content, allocator);
    if (std.mem.eql(u8, ext, ".go")) return extractGo(content, allocator);
    if (std.mem.eql(u8, ext, ".rs")) return extractRust(content, allocator);

    return extractHeaderComment(content);
}

// ── Known files ──────────────────────────────────────────

const known_list = [_]struct { name: []const u8, desc: []const u8 }{
    .{ .name = "build.zig", .desc = "Zig build script" },
    .{ .name = "build.zig.zon", .desc = "Zig package manifest" },
    .{ .name = "package.json", .desc = "npm package manifest" },
    .{ .name = "package-lock.json", .desc = "npm lockfile" },
    .{ .name = "yarn.lock", .desc = "Yarn lockfile" },
    .{ .name = "Cargo.toml", .desc = "Rust project manifest" },
    .{ .name = "go.mod", .desc = "Go module definition" },
    .{ .name = "Makefile", .desc = "Build automation" },
    .{ .name = "Dockerfile", .desc = "Container image definition" },
    .{ .name = ".gitignore", .desc = "Git ignore patterns" },
    .{ .name = ".env.example", .desc = "Environment variable template" },
    .{ .name = "tsconfig.json", .desc = "TypeScript configuration" },
    .{ .name = "README.md", .desc = "Project documentation" },
    .{ .name = "LICENSE", .desc = "License file" },
    .{ .name = "claude.md", .desc = "Directory context & conventions" },
};

fn knownFile(filename: []const u8) ?[]const u8 {
    for (&known_list) |k| {
        if (std.mem.eql(u8, filename, k.name)) return k.desc;
    }
    return null;
}

// ── Markdown ─────────────────────────────────────────────

fn extractMarkdown(content: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const t = std.mem.trim(u8, line, " \t\r");
        if (std.mem.startsWith(u8, t, "# ")) return t;
        if (std.mem.startsWith(u8, t, "## ")) return t;
        if (std.mem.startsWith(u8, t, "### ")) return t;
    }
    return null;
}

// ── Zig ──────────────────────────────────────────────────

fn extractZig(content: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, content, '\n');

    while (lines.next()) |line| {
        const t = std.mem.trim(u8, line, " \t\r");
        if (std.mem.startsWith(u8, t, "pub fn ")) {
            const after = t["pub fn ".len..];
            const name = extractIdent(after);
            if (name.len > 0) try names.append(allocator, name);
        }
    }

    if (names.items.len > 0) {
        const joined = try joinNames(names.items, allocator);
        return try std.fmt.allocPrint(allocator, "pub fn {s}", .{joined});
    }
    return extractHeaderComment(content);
}

// ── TypeScript / JavaScript ──────────────────────────────

fn extractTsJs(content: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, content, '\n');

    while (lines.next()) |line| {
        const t = std.mem.trim(u8, line, " \t\r");
        const export_idx = std.mem.indexOf(u8, t, "export ") orelse continue;
        if (export_idx != 0) continue;

        var rest = t["export ".len..];

        if (std.mem.startsWith(u8, rest, "default ")) rest = rest["default ".len..];
        if (std.mem.startsWith(u8, rest, "async ")) rest = rest["async ".len..];

        const keywords = [_][]const u8{ "function ", "const ", "class ", "interface ", "type ", "enum " };
        for (&keywords) |kw| {
            if (std.mem.startsWith(u8, rest, kw)) {
                const name = extractIdent(rest[kw.len..]);
                if (name.len > 0) {
                    const full = try std.fmt.allocPrint(allocator, "export {s}{s}", .{ kw, name });
                    try names.append(allocator, full);
                }
                break;
            }
        }
    }

    if (names.items.len > 0) return @as(?[]const u8, try joinNames(names.items, allocator));
    return extractHeaderComment(content);
}

// ── Python ───────────────────────────────────────────────

fn extractPython(content: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, content, '\n');

    while (lines.next()) |line| {
        if (line.len > 0 and (line[0] == ' ' or line[0] == '\t')) continue;
        const t = std.mem.trim(u8, line, " \t\r");
        if (std.mem.startsWith(u8, t, "def ")) {
            const name = extractIdent(t["def ".len..]);
            if (name.len > 0) try names.append(allocator, name);
        } else if (std.mem.startsWith(u8, t, "class ")) {
            const name = extractIdent(t["class ".len..]);
            if (name.len > 0) try names.append(allocator, name);
        }
    }

    if (names.items.len > 0) {
        const joined = try joinNames(names.items, allocator);
        return try std.fmt.allocPrint(allocator, "def {s}", .{joined});
    }
    return extractHeaderComment(content);
}

// ── Go ───────────────────────────────────────────────────

fn extractGo(content: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, content, '\n');

    while (lines.next()) |line| {
        const t = std.mem.trim(u8, line, " \t\r");
        if (!std.mem.startsWith(u8, t, "func ")) continue;

        var rest = t["func ".len..];

        // Handle receiver: func (r Receiver) Name(...)
        const rt = std.mem.trim(u8, rest, " ");
        if (rt.len > 0 and rt[0] == '(') {
            const close_paren = std.mem.indexOfScalar(u8, rest, ')') orelse continue;
            rest = std.mem.trim(u8, rest[close_paren + 1 ..], " ");
        }

        const name = extractIdent(rest);
        if (name.len > 0) try names.append(allocator, name);
    }

    if (names.items.len > 0) {
        const joined = try joinNames(names.items, allocator);
        return try std.fmt.allocPrint(allocator, "func {s}", .{joined});
    }
    return extractHeaderComment(content);
}

// ── Rust ─────────────────────────────────────────────────

fn extractRust(content: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, content, '\n');

    while (lines.next()) |line| {
        const t = std.mem.trim(u8, line, " \t\r");
        if (!std.mem.startsWith(u8, t, "pub ")) continue;

        var rest = t["pub ".len..];

        const keywords = [_][]const u8{ "fn ", "struct ", "enum ", "trait ", "type ", "mod ", "union ", "const " };
        for (&keywords) |kw| {
            if (std.mem.startsWith(u8, rest, kw)) {
                const name = extractIdent(rest[kw.len..]);
                if (name.len > 0) try names.append(allocator, name);
                break;
            }
        }
    }

    if (names.items.len > 0) {
        const joined = try joinNames(names.items, allocator);
        return try std.fmt.allocPrint(allocator, "pub {s}", .{joined});
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
            std.mem.startsWith(u8, t, "#include") or
            std.mem.startsWith(u8, t, "use ")) continue;

        if (std.mem.startsWith(u8, t, "//")) {
            const text = std.mem.trim(u8, t[2..], " \t");
            if (text.len > 0 and !isBoilerplate(text)) return text;
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
    const t = std.mem.trim(u8, text, " \t\r");
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
