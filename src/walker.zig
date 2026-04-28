const std = @import("std");
const Io = std.Io;
const Dir = Io.Dir;

pub const FileInfo = struct {
    path: []const u8,
    size: u64,
};

const builtin_excludes = [_][]const u8{
    ".git", "node_modules", "target", "zig-cache", ".zig-cache",
    "zig-out", "dist", "build", "vendor", "third_party",
    "external", "references", ".claude", ".zrouter", ".memory",
    "skill",
};

fn shouldSkipDir(component: []const u8, extra: []const []const u8) bool {
    for (&builtin_excludes) |e| {
        if (std.mem.eql(u8, component, e)) return true;
    }
    for (extra) |e| {
        if (std.mem.eql(u8, component, e)) return true;
    }
    return false;
}

fn isBinaryExt(path: []const u8) bool {
    const exts = [_][]const u8{
        ".png", ".jpg", ".jpeg", ".gif", ".ico", ".svg",
        ".woff", ".woff2", ".ttf", ".eot",
        ".zip", ".tar", ".gz", ".bz2", ".7z",
        ".wasm", ".exe", ".dll", ".so", ".dylib",
        ".o", ".obj", ".a", ".lib",
        ".mp3", ".mp4", ".avi", ".mov",
        ".pdf", ".doc", ".docx",
    };
    const ext = std.fs.path.extension(path);
    for (&exts) |e| {
        if (std.mem.eql(u8, ext, e)) return true;
    }
    return false;
}

/// List direct children files (non-recursive) in a directory.
pub fn listFiles(allocator: std.mem.Allocator, io: Io, dir_path: []const u8, extra_exclude: []const []const u8) ![]FileInfo {
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

        // Only direct children (no '/' in path relative to walk root)
        if (std.mem.indexOfScalar(u8, entry.path, '/') != null) continue;
        if (std.mem.eql(u8, entry.basename, "CLAUDE.md")) continue;
        if (std.mem.startsWith(u8, entry.basename, ".")) continue;
        if (isBinaryExt(entry.basename)) continue;
        if (shouldSkipDir(entry.basename, extra_exclude)) continue;

        const child = entry.dir.openFile(io, entry.basename, .{}) catch continue;
        defer child.close(io);
        const size = child.length(io) catch continue;
        if (size > 1024 * 1024) continue;

        try entries.append(allocator, .{
            .path = try allocator.dupe(u8, entry.basename),
            .size = size,
        });
    }

    return entries.items;
}

/// Find immediate subdirectories that contain a CLAUDE.md file.
pub fn findSubdirsWithClaudeMd(allocator: std.mem.Allocator, io: Io, dir_path: []const u8, extra_exclude: []const []const u8) ![]const []const u8 {
    var dir = Dir.cwd().openDir(io, dir_path, .{ .iterate = true }) catch return &.{};
    defer dir.close(io);

    var result: std.ArrayList([]const u8) = .empty;

    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        if (entry.kind != .directory) continue;
        if (shouldSkipDir(entry.name, extra_exclude)) continue;

        // Check if this subdirectory has a CLAUDE.md
        const claude_path = try std.fs.path.join(allocator, &.{ dir_path, entry.name, "CLAUDE.md" });
        Dir.cwd().access(io, claude_path, .{}) catch continue;

        try result.append(allocator, try allocator.dupe(u8, entry.name));
    }

    return result.items;
}
