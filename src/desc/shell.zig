const std = @import("std");
const common = @import("common.zig");
const outline_helpers = @import("outline.zig");

pub fn isExt(ext: []const u8) bool {
    const exts = [_][]const u8{ ".sh", ".bash", ".zsh", ".fish" };
    for (&exts) |e| if (std.mem.eql(u8, ext, e)) return true;
    return false;
}

pub fn isFilename(filename: []const u8) bool {
    const base = std.fs.path.basename(filename);
    return std.mem.eql(u8, base, "configure") or
        std.mem.eql(u8, base, "install") or
        std.mem.eql(u8, base, "bootstrap");
}

pub fn extract(content: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    var fns: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, content, '\n');

    while (lines.next()) |line| {
        if (fns.items.len >= common.max_names) break;
        const t = std.mem.trim(u8, line, " \t\r");
        if (t.len == 0 or std.mem.startsWith(u8, t, "#")) continue;

        if (std.mem.startsWith(u8, t, "function ")) {
            const name = common.extractIdent(t["function ".len..]);
            if (name.len > 0) try fns.append(allocator, name);
        } else if (std.mem.indexOf(u8, t, "()")) |idx| {
            const name = std.mem.trim(u8, t[0..idx], " \t");
            const after = std.mem.trimStart(u8, t[idx + 2 ..], " \t");
            if (name.len > 0 and common.isIdent(name) and (after.len == 0 or after[0] == '{')) {
                try fns.append(allocator, name);
            }
        }
    }

    if (fns.items.len > 0) return try std.fmt.allocPrint(allocator, "sh fn {s}", .{try common.joinNames(fns.items, allocator)});
    return common.extractHeaderComment(content);
}

pub fn outline(content: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    return outline_helpers.collectMatchingLines(content, allocator, outlineLine);
}

fn outlineLine(t: []const u8, allocator: std.mem.Allocator) ?[]const u8 {
    if (std.mem.startsWith(u8, t, "function ")) return outline_helpers.braceItem(t, allocator, "") catch null;
    if (std.mem.indexOf(u8, t, "()")) |_| return outline_helpers.braceItem(t, allocator, "") catch null;
    return null;
}
