const std = @import("std");
const common = @import("common.zig");

pub fn isJsonExt(ext: []const u8) bool {
    return std.mem.eql(u8, ext, ".json") or std.mem.eql(u8, ext, ".jsonc") or std.mem.eql(u8, ext, ".json5");
}

pub fn extractJson(content: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    var keys: std.ArrayList([]const u8) = .empty;
    var depth: usize = 0;
    var in_string = false;
    var escape = false;
    var key_start: ?usize = null;
    var last_string: ?[]const u8 = null;

    for (content, 0..) |c, i| {
        if (escape) {
            escape = false;
            continue;
        }
        if (in_string and c == '\\') {
            escape = true;
            continue;
        }
        if (c == '"') {
            if (in_string) {
                in_string = false;
                if (key_start) |start| last_string = content[start..i];
                key_start = null;
            } else {
                in_string = true;
                key_start = i + 1;
            }
            continue;
        }
        if (in_string) continue;
        if (c == '{' or c == '[') {
            depth += 1;
        } else if ((c == '}' or c == ']') and depth > 0) {
            depth -= 1;
        }
        if (c == ':' and depth == 1) {
            if (last_string) |key| {
                if (key.len > 0 and keys.items.len < common.max_names) try keys.append(allocator, key);
            }
            last_string = null;
        }
        if (keys.items.len >= common.max_names) break;
    }

    if (keys.items.len > 0) return try std.fmt.allocPrint(allocator, "JSON keys {s}", .{try common.joinNames(keys.items, allocator)});
    return null;
}

pub fn extractToml(content: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    var sections: std.ArrayList([]const u8) = .empty;
    var keys: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, content, '\n');

    while (lines.next()) |line| {
        if (sections.items.len + keys.items.len >= common.max_names) break;
        const t = std.mem.trim(u8, line, " \t\r");
        if (t.len == 0 or std.mem.startsWith(u8, t, "#")) continue;
        if (std.mem.startsWith(u8, t, "[") and std.mem.endsWith(u8, t, "]")) {
            const inner = std.mem.trim(u8, t[1 .. t.len - 1], "[] \t");
            if (inner.len > 0) try sections.append(allocator, inner);
        } else if (std.mem.indexOfScalar(u8, t, '=')) |eq| {
            const key = std.mem.trim(u8, t[0..eq], " \t");
            if (key.len > 0) try keys.append(allocator, key);
        }
    }

    if (sections.items.len > 0) return try std.fmt.allocPrint(allocator, "TOML sections {s}", .{try common.joinNames(sections.items, allocator)});
    if (keys.items.len > 0) return try std.fmt.allocPrint(allocator, "TOML keys {s}", .{try common.joinNames(keys.items, allocator)});
    return null;
}

pub fn extractYaml(content: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    var keys: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, content, '\n');

    while (lines.next()) |line| {
        if (keys.items.len >= common.max_names) break;
        if (line.len > 0 and (line[0] == ' ' or line[0] == '\t' or line[0] == '-')) continue;
        const t = std.mem.trim(u8, line, " \t\r");
        if (t.len == 0 or std.mem.startsWith(u8, t, "#")) continue;
        if (std.mem.indexOfScalar(u8, t, ':')) |colon| {
            const key = std.mem.trim(u8, t[0..colon], " \t\"'");
            if (key.len > 0) try keys.append(allocator, key);
        }
    }

    if (keys.items.len > 0) return try std.fmt.allocPrint(allocator, "YAML keys {s}", .{try common.joinNames(keys.items, allocator)});
    return null;
}
