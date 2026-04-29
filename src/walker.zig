const std = @import("std");
const Io = std.Io;
const Dir = Io.Dir;

pub const FileInfo = struct {
    path: []const u8,
    size: u64,
};

pub const RoutingInfo = struct {
    paths: []const []const u8,
    route_set: []const bool,
    inline_dirs: []const []const u8,
    direct_inline_dirs: []const []const u8,
};

fn charClassMatch(pattern: []const u8, start: usize, c: u8) ?struct { matched: bool, next: usize } {
    if (start >= pattern.len or pattern[start] != '[') return null;
    var i = start + 1;
    if (i >= pattern.len) return null;

    var negated = false;
    if (pattern[i] == '!' or pattern[i] == '^') {
        negated = true;
        i += 1;
    }

    var matched = false;
    var saw = false;
    while (i < pattern.len and pattern[i] != ']') {
        saw = true;
        if (i + 2 < pattern.len and pattern[i + 1] == '-' and pattern[i + 2] != ']') {
            const lo = pattern[i];
            const hi = pattern[i + 2];
            if (lo <= c and c <= hi) matched = true;
            i += 3;
        } else {
            if (pattern[i] == c) matched = true;
            i += 1;
        }
    }

    if (i >= pattern.len or pattern[i] != ']' or !saw) return null;
    return .{ .matched = if (negated) !matched else matched, .next = i + 1 };
}

fn globMatch(pattern: []const u8, text: []const u8) bool {
    var p: usize = 0;
    var t: usize = 0;
    var star: ?usize = null;
    var star_text: usize = 0;

    while (t < text.len) {
        if (p < pattern.len and pattern[p] == '[') {
            if (charClassMatch(pattern, p, text[t])) |class| {
                if (class.matched) {
                    p = class.next;
                    t += 1;
                    continue;
                }
            }
        }

        if (p < pattern.len and (pattern[p] == '?' or pattern[p] == text[t])) {
            p += 1;
            t += 1;
        } else if (p < pattern.len and pattern[p] == '*') {
            star = p;
            star_text = t;
            p += 1;
        } else if (star) |s| {
            p = s + 1;
            star_text += 1;
            t = star_text;
        } else {
            return false;
        }
    }

    while (p < pattern.len and pattern[p] == '*') p += 1;
    return p == pattern.len;
}

fn normalizeSlashes(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const result = try allocator.dupe(u8, path);
    for (result) |*c| {
        if (c.* == '\\') c.* = '/';
    }
    return result;
}

fn splitPath(path: []const u8, out: *std.ArrayList([]const u8), allocator: std.mem.Allocator) !void {
    const normalized = try normalizeSlashes(allocator, path);
    var it = std.mem.splitScalar(u8, normalized, '/');
    while (it.next()) |part| {
        if (part.len == 0) continue;
        try out.append(allocator, part);
    }
}

fn matchSegments(pattern: []const []const u8, path: []const []const u8) bool {
    if (pattern.len == 0) return path.len == 0;
    if (std.mem.eql(u8, pattern[0], "**")) {
        if (matchSegments(pattern[1..], path)) return true;
        if (path.len > 0) return matchSegments(pattern, path[1..]);
        return false;
    }
    if (path.len == 0) return false;
    if (!globMatch(pattern[0], path[0])) return false;
    return matchSegments(pattern[1..], path[1..]);
}

fn normalizePattern(raw: []const u8) struct { pattern: []const u8, rooted: bool, dir_only: bool } {
    var p = std.mem.trim(u8, raw, " \t\r\n");
    const rooted = std.mem.startsWith(u8, p, "/");
    if (rooted) p = p[1..];
    const dir_only = std.mem.endsWith(u8, p, "/");
    if (dir_only) p = p[0 .. p.len - 1];
    return .{ .pattern = p, .rooted = rooted, .dir_only = dir_only };
}

fn patternMatchesPath(allocator: std.mem.Allocator, raw_pattern: []const u8, path: []const u8, is_dir: bool) bool {
    const norm = normalizePattern(raw_pattern);
    if (norm.pattern.len == 0 or std.mem.startsWith(u8, norm.pattern, "#")) return false;
    if (norm.dir_only and !is_dir) return false;

    var pattern_parts: std.ArrayList([]const u8) = .empty;
    var path_parts: std.ArrayList([]const u8) = .empty;
    splitPath(norm.pattern, &pattern_parts, allocator) catch return false;
    splitPath(path, &path_parts, allocator) catch return false;

    if (pattern_parts.items.len == 0) return false;
    const has_slash = std.mem.indexOfScalar(u8, norm.pattern, '/') != null;

    if (norm.rooted) return matchSegments(pattern_parts.items, path_parts.items);
    if (!has_slash and pattern_parts.items.len == 1) {
        for (path_parts.items) |part| if (globMatch(pattern_parts.items[0], part)) return true;
        return false;
    }

    var i: usize = 0;
    while (i <= path_parts.items.len) : (i += 1) {
        if (matchSegments(pattern_parts.items, path_parts.items[i..])) return true;
    }
    return false;
}

fn anyPatternMatches(allocator: std.mem.Allocator, patterns: []const []const u8, path: []const u8, is_dir: bool) bool {
    for (patterns) |raw| {
        if (patternMatchesPath(allocator, raw, path, is_dir)) return true;
    }
    return false;
}

fn isIgnored(allocator: std.mem.Allocator, path: []const u8, is_dir: bool, exclude: []const []const u8, allow: []const []const u8) bool {
    if (!anyPatternMatches(allocator, exclude, path, is_dir)) return false;
    return !anyPatternMatches(allocator, allow, path, is_dir);
}

fn isTransparentDir(name: []const u8, transparent_dirs: []const []const u8) bool {
    for (transparent_dirs) |d| if (std.mem.eql(u8, name, d)) return true;
    return false;
}

fn pathStartsWithDir(path: []const u8, dir_path: []const u8) bool {
    if (dir_path.len == 0) return true;
    return path.len > dir_path.len and
        std.mem.startsWith(u8, path, dir_path) and
        path[dir_path.len] == '/';
}

fn isUnderRoutedDir(path: []const u8, routed_dirs: []const []const u8) bool {
    for (routed_dirs) |routed| {
        if (pathStartsWithDir(path, routed)) return true;
    }
    return false;
}

fn hasIgnoredAncestor(allocator: std.mem.Allocator, path: []const u8, exclude: []const []const u8, allow: []const []const u8) bool {
    var start: usize = 0;
    while (std.mem.indexOfScalarPos(u8, path, start, '/')) |slash| {
        const dir_path = path[0..slash];
        if (isIgnored(allocator, dir_path, true, exclude, allow)) return true;
        start = slash + 1;
    }
    return false;
}

/// List files under `dir_path`. When `recursive` is false, only direct children
/// are returned; when true, the full subtree is walked.
/// Skips: excluded dirs, excluded extensions, hidden files, CLAUDE.md, files >1 MiB.
/// Results are sorted lexicographically by path.
pub fn listFiles(
    allocator: std.mem.Allocator,
    io: Io,
    dir_path: []const u8,
    exclude: []const []const u8,
    allow: []const []const u8,
    recursive: bool,
) ![]FileInfo {
    const inline_dirs: []const []const u8 = if (recursive) &.{""} else &.{};
    return listFilesForIndex(allocator, io, dir_path, exclude, allow, &.{}, inline_dirs, &.{});
}

fn isExplicitInlinePath(path: []const u8, inline_dirs: []const []const u8) bool {
    for (inline_dirs) |inline_dir| {
        if (pathStartsWithDir(path, inline_dir)) return true;
    }
    return false;
}

fn isDirectInlinePath(path: []const u8, direct_inline_dirs: []const []const u8) bool {
    for (direct_inline_dirs) |inline_dir| {
        if (!pathStartsWithDir(path, inline_dir)) continue;
        const rest = path[inline_dir.len + 1 ..];
        if (std.mem.indexOfScalar(u8, rest, '/') == null) return true;
    }
    return false;
}

/// List files, skipping any routed subtree and only recursing into explicit inline dirs.
pub fn listFilesForIndex(
    allocator: std.mem.Allocator,
    io: Io,
    dir_path: []const u8,
    exclude: []const []const u8,
    allow: []const []const u8,
    routed_dirs: []const []const u8,
    inline_dirs: []const []const u8,
    direct_inline_dirs: []const []const u8,
) ![]FileInfo {
    var dir = Dir.cwd().openDir(io, dir_path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return &.{},
        else => return err,
    };
    defer dir.close(io);

    var entries: std.ArrayList(FileInfo) = .empty;
    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        const normalized_path = try normalizeSlashes(allocator, entry.path);
        if (std.mem.indexOfScalar(u8, normalized_path, '/') != null and
            !isExplicitInlinePath(normalized_path, inline_dirs) and
            !isDirectInlinePath(normalized_path, direct_inline_dirs))
        {
            continue;
        }
        if (isUnderRoutedDir(normalized_path, routed_dirs)) continue;
        if (hasIgnoredAncestor(allocator, normalized_path, exclude, allow)) continue;
        if (isIgnored(allocator, normalized_path, false, exclude, allow)) continue;

        const base = entry.basename;
        if (std.mem.eql(u8, base, "CLAUDE.md")) continue;

        const child = entry.dir.openFile(io, base, .{}) catch continue;
        defer child.close(io);
        const size = child.length(io) catch continue;
        if (size > 1024 * 1024) continue;

        try entries.append(allocator, .{
            .path = normalized_path,
            .size = size,
        });
    }

    std.mem.sortUnstable(FileInfo, entries.items, {}, struct {
        fn lessThan(_: void, a: FileInfo, b: FileInfo) bool {
            return std.mem.lessThan(u8, a.path, b.path);
        }
    }.lessThan);

    return entries.items;
}

fn hasClaudeMd(allocator: std.mem.Allocator, io: Io, dir_path: []const u8) bool {
    const claude_path = std.fs.path.join(allocator, &.{ dir_path, "CLAUDE.md" }) catch return false;
    Dir.cwd().access(io, claude_path, .{}) catch return false;
    return true;
}

fn countFiles(
    allocator: std.mem.Allocator,
    io: Io,
    dir_path: []const u8,
    exclude: []const []const u8,
    allow: []const []const u8,
    recursive: bool,
) !usize {
    const files = try listFiles(allocator, io, dir_path, exclude, allow, recursive);
    return files.len;
}

fn shouldRouteDir(
    allocator: std.mem.Allocator,
    io: Io,
    dir_path: []const u8,
    exclude: []const []const u8,
    allow: []const []const u8,
    inline_max_files: u32,
) bool {
    const file_count = countFiles(allocator, io, dir_path, exclude, allow, true) catch return false;
    return file_count > inline_max_files;
}

fn appendRoutingDirs(
    allocator: std.mem.Allocator,
    io: Io,
    base_path: []const u8,
    rel_path: []const u8,
    exclude: []const []const u8,
    allow: []const []const u8,
    transparent_dirs: []const []const u8,
    inline_max_files: u32,
    paths: *std.ArrayList([]const u8),
    route_set: *std.ArrayList(bool),
    inline_dirs: *std.ArrayList([]const u8),
    direct_inline_dirs: *std.ArrayList([]const u8),
) !void {
    const scan_path = if (rel_path.len == 0) base_path else try std.fs.path.join(allocator, &.{ base_path, rel_path });
    var dir = Dir.cwd().openDir(io, scan_path, .{ .iterate = true }) catch return;
    defer dir.close(io);

    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        if (entry.kind != .directory) continue;

        const child_rel = if (rel_path.len == 0)
            try normalizeSlashes(allocator, entry.name)
        else
            try normalizeSlashes(allocator, try std.fs.path.join(allocator, &.{ rel_path, entry.name }));
        const child_path = try std.fs.path.join(allocator, &.{ base_path, child_rel });
        if (isIgnored(allocator, child_rel, true, exclude, allow)) continue;

        if (isTransparentDir(entry.name, transparent_dirs)) {
            try direct_inline_dirs.append(allocator, child_rel);
            try appendRoutingDirs(allocator, io, base_path, child_rel, exclude, allow, transparent_dirs, inline_max_files, paths, route_set, inline_dirs, direct_inline_dirs);
            continue;
        }

        if (hasClaudeMd(allocator, io, child_path)) {
            try paths.append(allocator, child_rel);
            try route_set.append(allocator, true);
            continue;
        }

        const routed = shouldRouteDir(allocator, io, child_path, exclude, allow, inline_max_files);
        if (!routed) try inline_dirs.append(allocator, child_rel);
    }
}

const RoutingPair = struct { path: []const u8, routed: bool };

fn routingLessThan(_: void, a: RoutingPair, b: RoutingPair) bool {
    return std.mem.lessThan(u8, a.path, b.path);
}

fn pathLessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

/// Find child directories that contain a CLAUDE.md. Transparent directories
/// are skipped and their children are promoted with full relative paths.
pub fn findSubdirsWithClaudeMd(
    allocator: std.mem.Allocator,
    io: Io,
    dir_path: []const u8,
    exclude: []const []const u8,
    allow: []const []const u8,
    transparent_dirs: []const []const u8,
    inline_max_files: u32,
) !RoutingInfo {
    var paths: std.ArrayList([]const u8) = .empty;
    var route_set: std.ArrayList(bool) = .empty;
    var inline_dirs: std.ArrayList([]const u8) = .empty;
    var direct_inline_dirs: std.ArrayList([]const u8) = .empty;
    try appendRoutingDirs(allocator, io, dir_path, "", exclude, allow, transparent_dirs, inline_max_files, &paths, &route_set, &inline_dirs, &direct_inline_dirs);

    var pairs: std.ArrayList(RoutingPair) = .empty;
    for (paths.items, route_set.items) |path, routed| {
        try pairs.append(allocator, .{ .path = path, .routed = routed });
    }
    std.mem.sortUnstable(RoutingPair, pairs.items, {}, routingLessThan);

    paths.clearRetainingCapacity();
    route_set.clearRetainingCapacity();
    for (pairs.items) |pair| {
        try paths.append(allocator, pair.path);
        try route_set.append(allocator, pair.routed);
    }
    std.mem.sortUnstable([]const u8, inline_dirs.items, {}, pathLessThan);
    std.mem.sortUnstable([]const u8, direct_inline_dirs.items, {}, pathLessThan);

    return .{
        .paths = paths.items,
        .route_set = route_set.items,
        .inline_dirs = inline_dirs.items,
        .direct_inline_dirs = direct_inline_dirs.items,
    };
}

/// Find all directories in a subtree that already contain CLAUDE.md, including root.
pub fn findAllDirsWithClaudeMd(
    allocator: std.mem.Allocator,
    io: Io,
    root_path: []const u8,
    exclude: []const []const u8,
    allow: []const []const u8,
) ![]const []const u8 {
    var result: std.ArrayList([]const u8) = .empty;
    if (hasClaudeMd(allocator, io, root_path)) try result.append(allocator, try allocator.dupe(u8, root_path));

    var root = Dir.cwd().openDir(io, root_path, .{ .iterate = true }) catch return result.items;
    defer root.close(io);

    var w = try root.walk(allocator);
    defer w.deinit();

    while (try w.next(io)) |entry| {
        if (entry.kind != .directory) continue;
        const normalized_path = try normalizeSlashes(allocator, entry.path);
        if (isIgnored(allocator, normalized_path, true, exclude, allow)) continue;

        const full = try normalizeSlashes(allocator, try std.fs.path.join(allocator, &.{ root_path, entry.path }));
        if (hasClaudeMd(allocator, io, full)) try result.append(allocator, full);
    }

    std.mem.sortUnstable([]const u8, result.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    return result.items;
}

fn shouldCreateClaudeMd(file_count: usize, inline_max_files: u32) bool {
    return file_count > inline_max_files;
}

/// Find directories that look useful enough for an auto-created CLAUDE.md.
pub fn findDirsNeedingClaudeMd(
    allocator: std.mem.Allocator,
    io: Io,
    root_path: []const u8,
    exclude: []const []const u8,
    allow: []const []const u8,
    transparent_dirs: []const []const u8,
    inline_max_files: u32,
) ![]const []const u8 {
    var result: std.ArrayList([]const u8) = .empty;
    var root = Dir.cwd().openDir(io, root_path, .{ .iterate = true }) catch return result.items;
    defer root.close(io);

    var w = try root.walk(allocator);
    defer w.deinit();

    while (try w.next(io)) |entry| {
        if (entry.kind != .directory) continue;
        const normalized_path = try normalizeSlashes(allocator, entry.path);
        if (isIgnored(allocator, normalized_path, true, exclude, allow)) continue;

        const full = try std.fs.path.join(allocator, &.{ root_path, entry.path });
        if (hasClaudeMd(allocator, io, full)) continue;
        if (isTransparentDir(entry.basename, transparent_dirs)) continue;

        const file_count = try countFiles(allocator, io, full, exclude, allow, true);
        if (shouldCreateClaudeMd(file_count, inline_max_files)) try result.append(allocator, full);
    }

    std.mem.sortUnstable([]const u8, result.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    return result.items;
}
