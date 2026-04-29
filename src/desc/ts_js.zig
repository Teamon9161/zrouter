const std = @import("std");
const common = @import("common.zig");
const outline_helpers = @import("outline.zig");

pub fn extract(content: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, content, '\n');

    while (lines.next()) |line| {
        if (names.items.len >= common.max_names) break;
        const t = std.mem.trim(u8, line, " \t\r");
        if (!std.mem.startsWith(u8, t, "export ")) continue;

        var rest = t["export ".len..];
        if (std.mem.startsWith(u8, rest, "default ")) rest = rest["default ".len..];
        if (std.mem.startsWith(u8, rest, "async ")) rest = rest["async ".len..];

        const keywords = [_][]const u8{ "function ", "const ", "class ", "interface ", "type ", "enum " };
        for (&keywords) |kw| {
            if (std.mem.startsWith(u8, rest, kw)) {
                const name = common.extractIdent(rest[kw.len..]);
                if (name.len > 0) {
                    try names.append(allocator, try std.fmt.allocPrint(allocator, "export {s}{s}", .{ kw, name }));
                }
                break;
            }
        }
    }

    if (names.items.len > 0) return try common.joinNames(names.items, allocator);
    return common.extractHeaderComment(content);
}

pub fn outline(content: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    return outline_helpers.collectMatchingLines(content, allocator, outlineLine);
}

fn outlineLine(t: []const u8, allocator: std.mem.Allocator) ?[]const u8 {
    if (!std.mem.startsWith(u8, t, "export ")) return null;
    if (std.mem.indexOfScalar(u8, t, '{') != null) return outline_helpers.braceItem(t, allocator, "") catch null;
    return outline_helpers.signatureLine(t, allocator) catch null;
}
