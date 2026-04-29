const std = @import("std");
const common = @import("common.zig");
const outline_helpers = @import("outline.zig");

pub fn extract(content: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, content, '\n');

    while (lines.next()) |line| {
        if (names.items.len >= common.max_names) break;
        const t = std.mem.trim(u8, line, " \t\r");
        if (std.mem.startsWith(u8, t, "pub fn ")) {
            const name = common.extractIdent(t["pub fn ".len..]);
            if (name.len > 0) try names.append(allocator, name);
        }
    }

    if (names.items.len > 0) {
        return try std.fmt.allocPrint(allocator, "pub fn {s}", .{try common.joinNames(names.items, allocator)});
    }
    return common.extractHeaderComment(content);
}

pub fn outline(content: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    return outline_helpers.collectMatchingLines(content, allocator, outlineLine);
}

fn outlineLine(t: []const u8, allocator: std.mem.Allocator) ?[]const u8 {
    if (std.mem.startsWith(u8, t, "pub fn ")) return outline_helpers.signatureLine(t, allocator) catch null;
    if (std.mem.startsWith(u8, t, "pub const ")) {
        if (std.mem.indexOf(u8, t, " struct") != null or std.mem.indexOf(u8, t, " enum") != null or
            std.mem.indexOf(u8, t, " union") != null)
        {
            return outline_helpers.braceItem(t, allocator, ";") catch null;
        }
        return outline_helpers.constLine(t, allocator) catch null;
    }
    return null;
}
