const std = @import("std");

pub fn extract(content: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const t = std.mem.trim(u8, line, " \t\r");
        if (std.mem.startsWith(u8, t, "### ")) return t[4..];
        if (std.mem.startsWith(u8, t, "## ")) return t[3..];
        if (std.mem.startsWith(u8, t, "# ")) return t[2..];
    }
    return null;
}
