const std = @import("std");
const Io = std.Io;
const Dir = Io.Dir;
const File = Io.File;
const zrouter = @import("zrouter");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;

    var stdout_buf: [4096]u8 = undefined;
    var stdout_fw: Io.File.Writer = .init(.stdout(), io, &stdout_buf);
    const stdout = &stdout_fw.interface;

    var stderr_buf: [1024]u8 = undefined;
    var stderr_fw: Io.File.Writer = .init(.stderr(), io, &stderr_buf);
    const stderr = &stderr_fw.interface;

    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 2) {
        try usage(stderr);
        try stdout.flush();
        try stderr.flush();
        return;
    }

    const cmd = args[1];
    var pos_args: std.ArrayList([]const u8) = .empty;
    var json_flag = false;

    for (args[2..]) |a| {
        if (std.mem.eql(u8, a, "--json")) {
            json_flag = true;
        } else {
            try pos_args.append(arena, a);
        }
    }

    if (std.mem.eql(u8, cmd, "init")) {
        try cmdInit(arena, io, stdout, json_flag);
    } else if (std.mem.eql(u8, cmd, "refresh")) {
        const dir = if (pos_args.items.len > 0) pos_args.items[0] else ".";
        try cmdRefresh(arena, io, dir, stdout, json_flag);
    } else if (std.mem.eql(u8, cmd, "query")) {
        if (pos_args.items.len == 0) {
            try stderr.print("Usage: zrouter query <file> [--json]\n", .{});
            try stdout.flush();
            try stderr.flush();
            return error.MissingArgument;
        }
        try cmdQuery(arena, io, pos_args.items[0], stdout, stderr, json_flag);
    } else {
        try stderr.print("Unknown command: {s}\n\n", .{cmd});
        try usage(stderr);
    }

    try stdout.flush();
    try stderr.flush();
}

fn usage(w: *Io.Writer) !void {
    try w.print(
        \\Usage: zrouter <command> [args] [--json]
        \\
        \\Commands:
        \\  init              Initialize .zrouter/config.json and refresh
        \\  refresh [<dir>]   Update <!-- zr:files --> and <!-- zr:routing --> blocks
        \\  query <file>      Describe a single file with token estimate
        \\
    , .{});
}

// ── init ─────────────────────────────────────────────────

fn cmdInit(arena: std.mem.Allocator, io: Io, stdout: *Io.Writer, json: bool) !void {
    var created: std.ArrayList([]const u8) = .empty;

    if (Dir.cwd().openFile(io, ".zrouter/config.json", .{})) |_| {} else |_| {
        try Dir.cwd().createDirPath(io, ".zrouter");
        try Dir.writeFile(Dir.cwd(), io, .{
            .sub_path = ".zrouter/config.json",
            .data =
            \\{
            \\  "version": 1,
            \\  "exclude_patterns": [],
            \\  "token_coefficient": 4.0
            \\}
            \\
            ,
        });
        try created.append(arena, ".zrouter/config.json");
    }

    try ensureMemoryFile(arena, io, "decisions.md",
        \\# Decisions
        \\
        \\### ADR format
        \\- Status: [proposed|accepted|rejected|superseded]
        \\- Context: why this decision was needed
        \\- Decision: what was decided
        \\- Alternatives: what was considered
        \\
        \\### Anti-patterns (Do-Not-Repeat)
        \\
    , &created);
    try ensureMemoryFile(arena, io, "patterns.md",
        \\# Patterns
        \\
        \\Reusable patterns observed in this codebase.
        \\
    , &created);
    try ensureMemoryFile(arena, io, "inbox.md",
        \\# Inbox
        \\
        \\Open questions, guesses, and unresolved observations.
        \\
    , &created);

    try cmdRefresh(arena, io, ".", stdout, json);

    if (json) {
        try stdout.print("{f}\n", .{std.json.fmt(.{
            .dir = ".",
            .created = created.items,
            .status = "ok",
        }, .{})});
    } else {
        try stdout.print("Initialized {d} files\n", .{created.items.len});
    }
}

fn ensureMemoryFile(arena: std.mem.Allocator, io: Io, name: []const u8, content: []const u8, created: *std.ArrayList([]const u8)) !void {
    const path = try std.fs.path.join(arena, &.{ ".memory", name });
    if (Dir.cwd().openFile(io, path, .{})) |_| {} else |_| {
        try Dir.cwd().createDirPath(io, ".memory");
        try Dir.writeFile(Dir.cwd(), io, .{ .sub_path = path, .data = content });
        try created.append(arena, path);
    }
}

// ── refresh ──────────────────────────────────────────────

fn cmdRefresh(arena: std.mem.Allocator, io: Io, dir_path: []const u8, stdout: *Io.Writer, json: bool) !void {
    const cfg = zrouter.config.Config.load(arena, io);

    const claude_path = try std.fs.path.join(arena, &.{ dir_path, "CLAUDE.md" });

    const existing = readMax(arena, io, claude_path, 64 * 1024) catch |err| switch (err) {
        error.FileNotFound => {
            if (!json) try stdout.print("No CLAUDE.md in {s}\n", .{dir_path});
            return;
        },
        else => return err,
    };

    // ── Files block ──
    const files = try zrouter.walker.listFiles(arena, io, dir_path, cfg.exclude_patterns);

    var file_entries: std.ArrayList(zrouter.claude_md.FileEntry) = .empty;
    for (files) |f| {
        const full = try std.fs.path.join(arena, &.{ dir_path, f.path });
        const content = readMax(arena, io, full, max_content_size) catch continue;
        const desc = try zrouter.desc.extract(f.path, content, arena) orelse "";
        const tokens = @as(usize, @intFromFloat(@as(f64, @floatFromInt(f.size)) / cfg.token_coefficient));
        try file_entries.append(arena, .{ .path = f.path, .desc = desc, .tokens = tokens });
    }

    const files_block = try zrouter.claude_md.buildFilesBlock(file_entries.items, arena);

    var content = try zrouter.claude_md.ensureBlock(existing, "zr:files", arena);
    content = try zrouter.claude_md.replaceBlock(content, "zr:files", files_block, arena);

    // ── Routing block (root only) ──
    const is_root = std.mem.eql(u8, dir_path, ".");
    if (is_root) {
        const subdirs = try zrouter.walker.findSubdirsWithClaudeMd(arena, io, dir_path, cfg.exclude_patterns);
        const routing_block = try zrouter.claude_md.buildRoutingBlock(subdirs, arena);
        content = try zrouter.claude_md.ensureBlock(content, "zr:routing", arena);
        content = try zrouter.claude_md.replaceBlock(content, "zr:routing", routing_block, arena);
    }

    try Dir.writeFile(Dir.cwd(), io, .{ .sub_path = claude_path, .data = content });

    if (json) {
        try stdout.print("{f}\n", .{std.json.fmt(.{
            .dir = dir_path,
            .files_count = file_entries.items.len,
            .updated = true,
        }, .{})});
    } else {
        try stdout.print("Updated {s}/CLAUDE.md ({d} files)\n", .{ dir_path, file_entries.items.len });
    }
}

const max_content_size = 12 * 1024;

// ── query ────────────────────────────────────────────────

fn cmdQuery(arena: std.mem.Allocator, io: Io, file_path: []const u8, stdout: *Io.Writer, stderr: *Io.Writer, json: bool) !void {
    const content = readMax(arena, io, file_path, max_content_size) catch |err| {
        try stderr.print("Error reading {s}: {}\n", .{ file_path, err });
        try stdout.flush();
        try stderr.flush();
        return;
    };

    const desc = try zrouter.desc.extract(file_path, content, arena) orelse "";
    const tokens = content.len / 4;

    if (json) {
        try stdout.print("{f}\n", .{std.json.fmt(.{
            .path = file_path,
            .description = desc,
            .tokens = tokens,
        }, .{})});
    } else {
        try stdout.print("{s} — {s} (~{d} tok)\n", .{ file_path, desc, tokens });
    }
}

// ── utilities ────────────────────────────────────────────

fn readMax(allocator: std.mem.Allocator, io: Io, path: []const u8, max_size: usize) ![]u8 {
    var file = try Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    const file_len = try file.length(io);
    const read_size = @min(file_len, max_size);
    const buf = try allocator.alloc(u8, read_size);
    const n = try file.readPositionalAll(io, buf, 0);
    return buf[0..n];
}
