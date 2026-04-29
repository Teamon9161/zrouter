const std = @import("std");
const common = @import("common.zig");

pub fn addHeaderComment(content: []const u8, body: []const u8, allocator: std.mem.Allocator, prefix: []const u8) ![]const u8 {
    const header = common.extractHeaderComment(content) orelse return body;
    if (std.mem.eql(u8, header, body)) return body;
    return try std.fmt.allocPrint(allocator, "{s} {s}\n{s}", .{ prefix, header, body });
}

pub fn collectMatchingLines(
    content: []const u8,
    allocator: std.mem.Allocator,
    comptime render: fn ([]const u8, std.mem.Allocator) ?[]const u8,
) !?[]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var lines = std.mem.splitScalar(u8, content, '\n');
    var count: usize = 0;

    while (lines.next()) |line| {
        if (count >= common.max_names) break;
        const t = std.mem.trim(u8, line, " \t\r");
        if (t.len == 0 or std.mem.startsWith(u8, t, "//") or std.mem.startsWith(u8, t, "#")) continue;
        if (render(t, allocator)) |rendered| {
            try appendLine(allocator, &out, rendered);
            count += 1;
        }
    }

    if (out.items.len == 0) return null;
    return std.mem.trimEnd(u8, out.items, "\n");
}

pub fn signatureLine(t: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    const body = if (std.mem.indexOfScalar(u8, t, '{')) |idx| t[0..idx] else t;
    return try std.fmt.allocPrint(allocator, "{s};", .{std.mem.trim(u8, body, " \t\r;")});
}

pub fn braceItem(t: []const u8, allocator: std.mem.Allocator, suffix: []const u8) ![]const u8 {
    const open = std.mem.indexOfScalar(u8, t, '{') orelse t.len;
    return try std.fmt.allocPrint(allocator, "{s} {{ ... }}{s}", .{ std.mem.trim(u8, t[0..open], " \t\r"), suffix });
}

pub fn constLine(t: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    const eq = std.mem.indexOfScalar(u8, t, '=') orelse t.len;
    return try std.fmt.allocPrint(allocator, "{s} = ...;", .{std.mem.trim(u8, t[0..eq], " \t\r")});
}

pub fn appendLine(allocator: std.mem.Allocator, out: *std.ArrayList(u8), line: []const u8) !void {
    try out.appendSlice(allocator, line);
    try out.append(allocator, '\n');
}

pub fn countLines(text: []const u8) usize {
    var count: usize = 0;
    for (text) |c| {
        if (c == '\n') count += 1;
    }
    return count;
}
