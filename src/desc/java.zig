const std = @import("std");
const common = @import("common.zig");
const outline_helpers = @import("outline.zig");

pub fn extract(content: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    var types: std.ArrayList([]const u8) = .empty;
    var methods: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, content, '\n');

    while (lines.next()) |line| {
        if (types.items.len + methods.items.len >= common.max_names) break;
        const t = std.mem.trim(u8, line, " \t\r");
        if (t.len == 0 or std.mem.startsWith(u8, t, "@") or
            std.mem.startsWith(u8, t, "import ") or std.mem.startsWith(u8, t, "package "))
        {
            continue;
        }

        const type_keywords = [_][]const u8{ " class ", " interface ", " enum ", " record " };
        for (&type_keywords) |kw| {
            if (std.mem.indexOf(u8, t, kw)) |idx| {
                const name = common.extractIdent(t[idx + kw.len ..]);
                if (name.len > 0) {
                    try types.append(allocator, try std.fmt.allocPrint(allocator, "{s} {s}", .{ std.mem.trim(u8, kw, " "), name }));
                }
                break;
            }
        }

        if (std.mem.startsWith(u8, t, "public ") or std.mem.startsWith(u8, t, "protected ")) {
            if (extractMethodName(t)) |name| {
                if (name.len > 0) try methods.append(allocator, name);
            }
        }
    }

    var parts: std.ArrayList([]const u8) = .empty;
    if (types.items.len > 0) try parts.append(allocator, try common.joinNames(types.items, allocator));
    if (methods.items.len > 0) try parts.append(allocator, try std.fmt.allocPrint(allocator, "method {s}", .{try common.joinNames(methods.items, allocator)}));
    if (parts.items.len > 0) return try common.joinNames(parts.items, allocator);
    return common.extractHeaderComment(content);
}

pub fn outline(content: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    return outline_helpers.collectMatchingLines(content, allocator, outlineLine);
}

fn outlineLine(t: []const u8, allocator: std.mem.Allocator) ?[]const u8 {
    const interesting = [_][]const u8{ "public ", "protected ", "class ", "interface ", "enum ", "record " };
    for (&interesting) |prefix| {
        if (std.mem.startsWith(u8, t, prefix)) {
            if (std.mem.indexOfScalar(u8, t, '{') != null) return outline_helpers.braceItem(t, allocator, "") catch null;
            if (std.mem.indexOfScalar(u8, t, '(') != null) return outline_helpers.signatureLine(t, allocator) catch null;
            return allocator.dupe(u8, t) catch null;
        }
    }
    return null;
}

fn extractMethodName(t: []const u8) ?[]const u8 {
    if (std.mem.indexOfScalar(u8, t, '(') == null or std.mem.indexOfScalar(u8, t, ')') == null) return null;
    if (!(std.mem.endsWith(u8, t, "{") or std.mem.endsWith(u8, t, ";"))) return null;

    const paren = std.mem.indexOfScalar(u8, t, '(') orelse return null;
    const before = std.mem.trimEnd(u8, t[0..paren], " \t");
    var start = before.len;
    while (start > 0 and common.isIdentChar(before[start - 1])) start -= 1;
    if (start == before.len) return null;
    const name = before[start..];
    if (isControlKeyword(name)) return null;
    return name;
}

fn isControlKeyword(name: []const u8) bool {
    const controls = [_][]const u8{ "if", "for", "while", "switch", "return", "sizeof", "catch" };
    for (&controls) |kw| if (std.mem.eql(u8, name, kw)) return true;
    return false;
}
