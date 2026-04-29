const std = @import("std");
const Io = std.Io;
const Dir = Io.Dir;
const toml = @import("toml");

pub const KnownFile = struct {
    name: []const u8,
    desc: []const u8,
};

const Raw = struct {
    token_coefficient: ?f64 = null,
    max_content_size: ?u32 = null,
    inline_max_files: ?u32 = null,
    respect_gitignore: ?bool = null,
    exclude: ?[]const []const u8 = null,
    allow: ?[]const []const u8 = null,
    transparent_dirs: ?[]const []const u8 = null,
    known_files: ?[]const KnownFile = null,
};

pub const Config = struct {
    /// chars / token_coefficient ≈ token count
    token_coefficient: f64 = 4.0,
    /// max bytes read per file for description extraction (default 12 KiB)
    max_content_size: u32 = 12 * 1024,
    /// directories with at most this many filtered files are inlined into parent indexes
    inline_max_files: u32 = 12,
    /// append supported .gitignore patterns to exclude/allow
    respect_gitignore: bool = true,
    /// gitignore-ish exclude patterns (union across all layers)
    exclude: []const []const u8 = &.{},
    /// gitignore-ish allow patterns overriding excludes (union across all layers)
    allow: []const []const u8 = &.{},
    /// directory names to skip in routing; children are promoted (union across all layers)
    transparent_dirs: []const []const u8 = &.{},
    /// known-file name→description; first-match wins (project > global > embedded)
    known_files: []const KnownFile = &.{},
};

/// Load configuration in three layers:
///   1. Embedded: built-in defaults from src/assets/default.toml
///   2. Global:   first existing path from the caller-provided candidate list
///   3. Project:  .zrouter/config.toml
/// Lists are extended (never replaced); scalars are overridden by later layers.
pub fn load(allocator: std.mem.Allocator, io: Io, global_paths: []const []const u8) Config {
    var cfg: Config = .{};

    applyRaw(&cfg, parseContent(allocator, @embedFile("assets/default.toml")), allocator);

    for (global_paths) |path| {
        if (readFile(allocator, io, path)) |content| {
            applyRaw(&cfg, parseContent(allocator, content), allocator);
            break;
        }
    }

    if (parseProjectFile(allocator, io)) |raw| {
        applyRaw(&cfg, raw, allocator);
    }

    if (cfg.respect_gitignore) {
        applyGitignore(&cfg, allocator, io);
    }

    return cfg;
}

fn applyRaw(cfg: *Config, raw: Raw, allocator: std.mem.Allocator) void {
    if (raw.token_coefficient) |v| cfg.token_coefficient = v;
    if (raw.max_content_size) |v| cfg.max_content_size = v;
    if (raw.inline_max_files) |v| cfg.inline_max_files = v;
    if (raw.respect_gitignore) |v| cfg.respect_gitignore = v;
    if (raw.exclude) |v| cfg.exclude = appendAll(cfg.exclude, v, allocator);
    if (raw.allow) |v| cfg.allow = appendAll(cfg.allow, v, allocator);
    if (raw.transparent_dirs) |v| cfg.transparent_dirs = appendTransparentDirs(cfg.transparent_dirs, v, allocator);
    if (raw.known_files) |v| {
        // Prepend: later layers have higher priority (first-match wins in lookup)
        var list: std.ArrayList(KnownFile) = .empty;
        list.appendSlice(allocator, v) catch {};
        list.appendSlice(allocator, cfg.known_files) catch {};
        cfg.known_files = list.items;
    }
}

fn appendAll(existing: []const []const u8, new: []const []const u8, allocator: std.mem.Allocator) []const []const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    list.appendSlice(allocator, existing) catch {};
    list.appendSlice(allocator, new) catch {};
    return list.items;
}

fn appendTransparentDirs(existing: []const []const u8, new: []const []const u8, allocator: std.mem.Allocator) []const []const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    list.appendSlice(allocator, existing) catch {};

    for (new) |entry| {
        if (std.mem.eql(u8, entry, "!*")) {
            list.clearRetainingCapacity();
        } else if (std.mem.startsWith(u8, entry, "!") and entry.len > 1) {
            const target = entry[1..];
            var i: usize = 0;
            while (i < list.items.len) {
                if (std.mem.eql(u8, list.items[i], target)) {
                    _ = list.orderedRemove(i);
                } else {
                    i += 1;
                }
            }
        } else {
            list.append(allocator, entry) catch {};
        }
    }

    return list.items;
}

fn parseContent(allocator: std.mem.Allocator, content: []const u8) Raw {
    var parser = toml.Parser(Raw).init(allocator);
    const result = parser.parseString(content) catch return Raw{};
    return result.value;
}

fn isUnsupportedGitignorePattern(line: []const u8) bool {
    return std.mem.indexOfScalar(u8, line, '\\') != null;
}

fn applyGitignore(cfg: *Config, allocator: std.mem.Allocator, io: Io) void {
    const content = readProjectFile(allocator, io, ".gitignore") orelse return;
    var exclude: std.ArrayList([]const u8) = .empty;
    var allow: std.ArrayList([]const u8) = .empty;

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |raw_line| {
        var line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or std.mem.startsWith(u8, line, "#")) continue;
        var negated = false;
        if (line[0] == '!') {
            negated = true;
            line = std.mem.trim(u8, line[1..], " \t\r");
            if (line.len == 0) continue;
        }
        if (isUnsupportedGitignorePattern(line)) continue;
        const copy = allocator.dupe(u8, line) catch continue;
        if (negated) {
            allow.append(allocator, copy) catch {};
        } else {
            exclude.append(allocator, copy) catch {};
        }
    }

    cfg.exclude = appendAll(cfg.exclude, exclude.items, allocator);
    cfg.allow = appendAll(cfg.allow, allow.items, allocator);
}

fn parseProjectFile(allocator: std.mem.Allocator, io: Io) ?Raw {
    var parser = toml.Parser(Raw).init(allocator);
    const result = parser.parseFile(io, ".zrouter/config.toml") catch return null;
    return result.value;
}

fn readProjectFile(allocator: std.mem.Allocator, io: Io, path: []const u8) ?[]const u8 {
    var f = Dir.cwd().openFile(io, path, .{}) catch return null;
    defer f.close(io);
    const len = f.length(io) catch return null;
    const max = @min(len, 64 * 1024);
    const buf = allocator.alloc(u8, max) catch return null;
    const n = f.readPositionalAll(io, buf, 0) catch return null;
    return buf[0..n];
}

fn readFile(allocator: std.mem.Allocator, io: Io, path: []const u8) ?[]const u8 {
    var f = Dir.openFileAbsolute(io, path, .{}) catch return null;
    defer f.close(io);
    const len = f.length(io) catch return null;
    const max = @min(len, 64 * 1024);
    const buf = allocator.alloc(u8, max) catch return null;
    const n = f.readPositionalAll(io, buf, 0) catch return null;
    return buf[0..n];
}
