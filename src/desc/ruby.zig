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
        if (t.len == 0 or std.mem.startsWith(u8, t, "#")) continue;
        if (std.mem.startsWith(u8, t, "class ") or std.mem.startsWith(u8, t, "module ")) {
            const first_space = std.mem.indexOfScalar(u8, t, ' ') orelse continue;
            const kw = t[0..first_space];
            const name = extractName(t[first_space + 1 ..]);
            if (name.len > 0) try types.append(allocator, try std.fmt.allocPrint(allocator, "{s} {s}", .{ kw, name }));
        } else if (std.mem.startsWith(u8, t, "def ")) {
            const name = extractName(t["def ".len..]);
            if (name.len > 0 and !std.mem.startsWith(u8, name, "_")) try methods.append(allocator, name);
        }
    }

    var parts: std.ArrayList([]const u8) = .empty;
    if (types.items.len > 0) try parts.append(allocator, try common.joinNames(types.items, allocator));
    if (methods.items.len > 0) try parts.append(allocator, try std.fmt.allocPrint(allocator, "def {s}", .{try common.joinNames(methods.items, allocator)}));
    if (parts.items.len > 0) return try common.joinNames(parts.items, allocator);
    return common.extractHeaderComment(content);
}

pub fn outline(content: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    return outline_helpers.collectMatchingLines(content, allocator, outlineLine);
}

fn outlineLine(t: []const u8, allocator: std.mem.Allocator) ?[]const u8 {
    if (std.mem.startsWith(u8, t, "class ") or std.mem.startsWith(u8, t, "module ") or std.mem.startsWith(u8, t, "def ")) {
        return allocator.dupe(u8, t) catch null;
    }
    return null;
}

fn extractName(text: []const u8) []const u8 {
    const t = std.mem.trimStart(u8, text, " \t\r");
    var end: usize = 0;
    for (t, 0..) |c, i| {
        if (!isNameChar(c)) break;
        end = i + 1;
    }
    return t[0..end];
}

fn isNameChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_' or c == ':' or c == '?' or c == '!' or c == '=';
}
