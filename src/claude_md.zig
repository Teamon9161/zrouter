const std = @import("std");

pub const FileEntry = struct {
    path: []const u8,
    desc: []const u8,
    tokens: usize,
};

/// Find a standalone `<!-- tag -->` marker (must occupy its own line).
fn findTag(content: []const u8, comptime open: []const u8) ?usize {
    var start: usize = 0;
    while (start < content.len) {
        const found = std.mem.indexOf(u8, content[start..], open) orelse return null;
        const abs = start + found;
        const preceded = abs == 0 or content[abs - 1] == '\n';
        const after = abs + open.len;
        const followed = after >= content.len or content[after] == '\n' or content[after] == '\r';
        if (preceded and followed) return abs;
        start = abs + open.len;
    }
    return null;
}

/// Replace the content inside `<!-- tag -->...<!-- /tag -->`.
/// Returns error.BlockNotFound if either marker is missing.
pub fn replaceBlock(content: []const u8, comptime tag: []const u8, new_inner: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const open_tag = "<!-- " ++ tag ++ " -->";
    const close_tag = "<!-- /" ++ tag ++ " -->";

    const open_pos = findTag(content, open_tag) orelse return error.BlockNotFound;
    const after_open = open_pos + open_tag.len;
    const close_rel = std.mem.indexOf(u8, content[after_open..], close_tag) orelse return error.BlockNotFound;
    const close_abs = after_open + close_rel;

    var result: std.ArrayList(u8) = .empty;
    try result.appendSlice(allocator, content[0..open_pos]);
    try result.appendSlice(allocator, open_tag);
    try result.append(allocator, '\n');
    try result.appendSlice(allocator, new_inner);
    try result.appendSlice(allocator, content[close_abs..]);
    return result.items;
}

/// Ensure both `<!-- tag -->` and `<!-- /tag -->` markers exist.
/// If absent, appends them at the end of the content.
pub fn ensureBlock(content: []const u8, comptime tag: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const open_tag = "<!-- " ++ tag ++ " -->";
    const close_tag = "<!-- /" ++ tag ++ " -->";

    if (findTag(content, open_tag) != null) return try allocator.dupe(u8, content);

    var result: std.ArrayList(u8) = .empty;
    try result.appendSlice(allocator, content);
    if (result.items.len > 0 and result.items[result.items.len - 1] != '\n') {
        try result.append(allocator, '\n');
    }
    try result.appendSlice(allocator, open_tag);
    try result.append(allocator, '\n');
    try result.appendSlice(allocator, close_tag);
    try result.append(allocator, '\n');
    return result.items;
}

/// Remove a `<!-- tag -->...<!-- /tag -->` block entirely from content.
/// Uses a lenient search (tag may be embedded mid-line) so it handles
/// malformed content from other tools. Returns a copy unchanged if absent.
pub fn removeBlock(content: []const u8, comptime tag: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const open_tag = "<!-- " ++ tag ++ " -->";
    const close_tag = "<!-- /" ++ tag ++ " -->";

    const open_pos = std.mem.indexOf(u8, content, open_tag) orelse return allocator.dupe(u8, content);
    const after_open = open_pos + open_tag.len;
    const close_rel = std.mem.indexOf(u8, content[after_open..], close_tag) orelse return allocator.dupe(u8, content);
    const close_pos = after_open + close_rel + close_tag.len;

    // consume trailing newline after the close marker
    const end = if (close_pos < content.len and content[close_pos] == '\n') close_pos + 1 else close_pos;
    // if the open tag is preceded only by whitespace on its line, remove that line prefix too
    var start = open_pos;
    if (open_pos > 0) {
        const line_start = if (std.mem.lastIndexOfScalar(u8, content[0..open_pos], '\n')) |nl| nl + 1 else 0;
        const prefix = std.mem.trim(u8, content[line_start..open_pos], " \t\r");
        if (prefix.len == 0) start = line_start; // nothing before tag on this line
    }

    var result: std.ArrayList(u8) = .empty;
    try result.appendSlice(allocator, content[0..start]);
    try result.appendSlice(allocator, content[end..]);
    return result.items;
}

/// Build the inner content for a `<!-- zr:files -->` block.
pub fn buildFilesBlock(entries: []const FileEntry, allocator: std.mem.Allocator) ![]u8 {
    var result: std.ArrayList(u8) = .empty;
    var current_group: ?[]const u8 = null;

    for (entries) |e| {
        if (std.mem.indexOfScalar(u8, e.path, '/')) |slash| {
            const group = e.path[0..slash];
            const rest = e.path[slash + 1 ..];
            if (current_group == null or !std.mem.eql(u8, current_group.?, group)) {
                current_group = group;
                try result.print(allocator, "- `{s}/`\n", .{group});
            }
            try result.print(allocator, "  - `{s}` — {s} (~{d} tok)\n", .{ rest, e.desc, e.tokens });
        } else {
            try result.print(allocator, "- `{s}` — {s} (~{d} tok)\n", .{ e.path, e.desc, e.tokens });
        }
    }
    return result.items;
}

/// Build the inner content for a `<!-- zr:routing -->` block.
pub fn buildRoutingBlock(subdirs: []const []const u8, route_set: []const bool, allocator: std.mem.Allocator) ![]u8 {
    var result: std.ArrayList(u8) = .empty;
    for (subdirs, route_set) |d, routed| {
        if (routed) {
            try result.print(allocator, "- [{s}/]({s}/CLAUDE.md)\n", .{ d, d });
        } else {
            try result.print(allocator, "- `{s}/` — inlined below\n", .{d});
        }
    }
    return result.items;
}
