const std = @import("std");

pub const FileEntry = struct {
    path: []const u8,
    desc: []const u8,
    tokens: usize,
};

/// Find a `<!-- tag -->` comment on its own line.
fn findTag(content: []const u8, comptime tag: []const u8) ?usize {
    const ftag = "<!-- " ++ tag ++ " -->";
    var start: usize = 0;
    while (start < content.len) {
        const found = std.mem.indexOf(u8, content[start..], ftag) orelse return null;
        const abs = start + found;
        const preceded = abs == 0 or content[abs - 1] == '\n';
        const after_end = abs + ftag.len;
        const followed = after_end >= content.len or content[after_end] == '\n';
        if (preceded and followed) return abs;
        start = abs + ftag.len;
    }
    return null;
}

/// Replace the content inside a `<!-- tag -->...<!-- /tag -->` block.
pub fn replaceBlock(content: []const u8, comptime tag: []const u8, new_inner: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const open_tag = "<!-- " ++ tag ++ " -->";
    const close_tag = "<!-- /" ++ tag ++ " -->";

    const open_pos = findTag(content, tag) orelse return error.BlockNotFound;
    const after_open = open_pos + open_tag.len;
    const after_slice = content[after_open..];
    const close_pos = std.mem.indexOf(u8, after_slice, close_tag) orelse return error.BlockNotFound;
    const close_abs = after_open + close_pos;

    var result: std.ArrayList(u8) = .empty;
    try result.appendSlice(allocator, content[0..open_pos]);
    try result.appendSlice(allocator, open_tag);
    try result.append(allocator, '\n');
    try result.appendSlice(allocator, new_inner);
    try result.appendSlice(allocator, content[close_abs..]);

    return result.items;
}

/// Ensure the block tag exists on its own line. If missing, append it at the end.
pub fn ensureBlock(content: []const u8, comptime tag: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const open_tag = "<!-- " ++ tag ++ " -->";
    const close_tag = "<!-- /" ++ tag ++ " -->";

    if (findTag(content, tag) != null) {
        return try allocator.dupe(u8, content);
    }

    var result: std.ArrayList(u8) = .empty;
    try result.appendSlice(allocator, content);

    if (content.len == 0 or content[content.len - 1] != '\n') {
        try result.append(allocator, '\n');
    }
    try result.appendSlice(allocator, open_tag);
    try result.append(allocator, '\n');
    try result.appendSlice(allocator, close_tag);
    try result.append(allocator, '\n');

    return result.items;
}

/// Build content for a `<!-- zr:files -->` block from file entries.
pub fn buildFilesBlock(entries: []const FileEntry, allocator: std.mem.Allocator) ![]u8 {
    var result: std.ArrayList(u8) = .empty;
    for (entries) |e| {
        try result.print(allocator, "- `{s}` — {s} (~{d} tok)\n", .{ e.path, e.desc, e.tokens });
    }
    return result.items;
}

/// Build content for a `<!-- zr:routing -->` block from subdirectory names.
pub fn buildRoutingBlock(subdirs: []const []const u8, allocator: std.mem.Allocator) ![]u8 {
    var result: std.ArrayList(u8) = .empty;
    for (subdirs) |d| {
        try result.print(allocator, "- {s}/\n", .{d});
    }
    return result.items;
}
