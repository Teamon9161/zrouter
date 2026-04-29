const std = @import("std");
const common = @import("common.zig");
const outline_helpers = @import("outline.zig");

pub fn isExt(ext: []const u8) bool {
    const exts = [_][]const u8{
        ".c", ".h", ".cc", ".hh", ".cpp", ".cxx", ".hpp", ".hxx", ".m", ".mm",
    };
    for (&exts) |e| if (std.mem.eql(u8, ext, e)) return true;
    return false;
}

pub fn extract(content: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    var types: std.ArrayList([]const u8) = .empty;
    var fns: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, content, '\n');

    while (lines.next()) |line| {
        if (types.items.len + fns.items.len >= common.max_names) break;
        const t = std.mem.trim(u8, line, " \t\r");
        if (t.len == 0 or skipLine(t)) continue;

        if (std.mem.startsWith(u8, t, "class ") or std.mem.startsWith(u8, t, "struct ") or
            std.mem.startsWith(u8, t, "enum ") or std.mem.startsWith(u8, t, "namespace "))
        {
            const first_space = std.mem.indexOfScalar(u8, t, ' ') orelse continue;
            const kw = t[0..first_space];
            const name = common.extractIdent(skipCppQualifiers(t[first_space + 1 ..]));
            if (name.len > 0) try types.append(allocator, try std.fmt.allocPrint(allocator, "{s} {s}", .{ kw, name }));
            continue;
        }

        if (extractFunctionName(t)) |name| {
            if (name.len > 0 and !isControlKeyword(name)) try fns.append(allocator, name);
        }
    }

    var parts: std.ArrayList([]const u8) = .empty;
    if (types.items.len > 0) try parts.append(allocator, try common.joinNames(types.items, allocator));
    if (fns.items.len > 0) try parts.append(allocator, try std.fmt.allocPrint(allocator, "fn {s}", .{try common.joinNames(fns.items, allocator)}));
    if (parts.items.len > 0) return try common.joinNames(parts.items, allocator);
    return common.extractHeaderComment(content);
}

pub fn outline(content: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    return outline_helpers.collectMatchingLines(content, allocator, outlineLine);
}

fn outlineLine(t: []const u8, allocator: std.mem.Allocator) ?[]const u8 {
    const interesting = [_][]const u8{ "class ", "struct ", "enum ", "namespace " };
    for (&interesting) |prefix| {
        if (std.mem.startsWith(u8, t, prefix)) {
            if (std.mem.indexOfScalar(u8, t, '{') != null) return outline_helpers.braceItem(t, allocator, "") catch null;
            return allocator.dupe(u8, t) catch null;
        }
    }
    if (extractFunctionName(t)) |_| return outline_helpers.signatureLine(t, allocator) catch null;
    return null;
}

fn skipLine(t: []const u8) bool {
    return std.mem.startsWith(u8, t, "#") or
        std.mem.startsWith(u8, t, "//") or
        std.mem.startsWith(u8, t, "/*") or
        std.mem.startsWith(u8, t, "*") or
        std.mem.startsWith(u8, t, "using ") or
        std.mem.startsWith(u8, t, "typedef ");
}

fn skipCppQualifiers(s: []const u8) []const u8 {
    var rest = std.mem.trimStart(u8, s, " \t");
    while (std.mem.startsWith(u8, rest, "final ") or std.mem.startsWith(u8, rest, "alignas")) {
        if (std.mem.indexOfScalar(u8, rest, ' ')) |space| {
            rest = std.mem.trimStart(u8, rest[space + 1 ..], " \t");
        } else {
            break;
        }
    }
    return rest;
}

fn extractFunctionName(t: []const u8) ?[]const u8 {
    const paren = std.mem.indexOfScalar(u8, t, '(') orelse return null;
    if (paren == 0) return null;
    const before = std.mem.trimEnd(u8, t[0..paren], " \t*&");
    if (before.len == 0) return null;
    var start = before.len;
    while (start > 0 and common.isIdentChar(before[start - 1])) start -= 1;
    if (start == before.len) return null;
    const name = before[start..];

    const after = std.mem.trimStart(u8, t[paren + 1 ..], " \t");
    if (after.len == 0) return null;
    if (std.mem.indexOfScalar(u8, after, ')') == null) return null;
    if (!(std.mem.endsWith(u8, t, ";") or std.mem.indexOfScalar(u8, t, '{') != null)) return null;
    return name;
}

fn isControlKeyword(name: []const u8) bool {
    const controls = [_][]const u8{ "if", "for", "while", "switch", "return", "sizeof", "catch" };
    for (&controls) |kw| if (std.mem.eql(u8, name, kw)) return true;
    return false;
}
