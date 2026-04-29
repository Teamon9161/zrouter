const std = @import("std");
const common = @import("common.zig");
const outline_helpers = @import("outline.zig");

pub fn extract(content: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    var classes: std.ArrayList([]const u8) = .empty;
    var fns: std.ArrayList([]const u8) = .empty;
    var vars: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, content, '\n');

    while (lines.next()) |line| {
        if (classes.items.len + fns.items.len >= common.max_names) break;
        if (line.len > 0 and (line[0] == ' ' or line[0] == '\t')) continue;
        const t = std.mem.trim(u8, line, " \t\r");
        if (std.mem.startsWith(u8, t, "class ")) {
            const name = common.extractIdent(t["class ".len..]);
            if (name.len > 0) try classes.append(allocator, name);
        } else if (std.mem.startsWith(u8, t, "def ") or std.mem.startsWith(u8, t, "async def ")) {
            const prefix = if (std.mem.startsWith(u8, t, "async ")) "async def ".len else "def ".len;
            const name = common.extractIdent(t[prefix..]);
            if (name.len > 0 and !std.mem.startsWith(u8, name, "_")) try fns.append(allocator, name);
        } else if (vars.items.len < common.max_names and t.len > 1 and std.ascii.isLower(t[0])) {
            const name = common.extractIdent(t);
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
        try parts.append(allocator, try std.fmt.allocPrint(allocator, "class {s}", .{try common.joinNames(classes.items, allocator)}));
    }
    if (fns.items.len > 0) {
        try parts.append(allocator, try std.fmt.allocPrint(allocator, "def {s}", .{try common.joinNames(fns.items, allocator)}));
    }
    if (parts.items.len > 0) return try common.joinNames(parts.items, allocator);
    if (vars.items.len > 0) return try common.joinNames(vars.items, allocator);
    return common.extractHeaderComment(content);
}

pub fn outline(content: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        if (line.len > 0 and (line[0] == ' ' or line[0] == '\t')) continue;
        const t = std.mem.trim(u8, line, " \t\r");
        if (std.mem.startsWith(u8, t, "class ") or std.mem.startsWith(u8, t, "def ") or std.mem.startsWith(u8, t, "async def ")) {
            try outline_helpers.appendLine(allocator, &out, try outlineLine(t, allocator));
        }
        if (out.items.len > 0 and outline_helpers.countLines(out.items) >= common.max_names) break;
    }
    if (out.items.len == 0) return null;
    return std.mem.trimEnd(u8, out.items, "\n");
}

fn outlineLine(t: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    const colon = std.mem.indexOfScalar(u8, t, ':') orelse t.len;
    return try std.fmt.allocPrint(allocator, "{s}: ...", .{std.mem.trim(u8, t[0..colon], " \t\r:")});
}
