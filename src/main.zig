const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const Io = std.Io;
const Dir = Io.Dir;
const zrouter = @import("zrouter");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const global_config_paths = resolveGlobalConfigPaths(arena, init.minimal.environ);

    var stdout_buf: [4096]u8 = undefined;
    var stdout_fw: Io.File.Writer = .init(.stdout(), io, &stdout_buf);
    const stdout = &stdout_fw.interface;

    var stderr_buf: [1024]u8 = undefined;
    var stderr_fw: Io.File.Writer = .init(.stderr(), io, &stderr_buf);
    const stderr = &stderr_fw.interface;

    const args = try init.minimal.args.toSlice(arena);

    if (args.len < 2) {
        try usage(stdout);
        try stdout.flush();
        return;
    }

    const cmd = args[1];
    if (std.mem.eql(u8, cmd, "--version") or std.mem.eql(u8, cmd, "-V")) {
        try cmdVersion(stdout);
        try stdout.flush();
        return;
    }
    var pos_args: std.ArrayList([]const u8) = .empty;
    var json_flag = false;
    var recursive_flag = false;
    var create_flag = false;
    var delete_file_flag = false;

    for (args[2..]) |a| {
        if (std.mem.eql(u8, a, "--json")) {
            json_flag = true;
        } else if (std.mem.eql(u8, a, "-r") or std.mem.eql(u8, a, "--recursive")) {
            recursive_flag = true;
        } else if (std.mem.eql(u8, a, "--create")) {
            create_flag = true;
        } else if (std.mem.eql(u8, a, "--delete-file")) {
            delete_file_flag = true;
        } else {
            try pos_args.append(arena, a);
        }
    }

    if (std.mem.eql(u8, cmd, "version")) {
        try cmdVersion(stdout);
    } else if (std.mem.eql(u8, cmd, "update")) {
        try cmdUpdate(arena, io, init.minimal.environ);
    } else if (std.mem.eql(u8, cmd, "init")) {
        try cmdInit(arena, io, global_config_paths, stdout, json_flag);
    } else if (std.mem.eql(u8, cmd, "refresh")) {
        const dir = if (pos_args.items.len > 0) pos_args.items[0] else ".";
        try cmdRefresh(arena, io, global_config_paths, dir, stdout, json_flag, recursive_flag, create_flag);
    } else if (std.mem.eql(u8, cmd, "query")) {
        if (pos_args.items.len == 0) {
            try stderr.print("error: zrouter query requires a <path> argument\n", .{});
            try stderr.flush();
            return error.MissingArgument;
        }
        try cmdQuery(arena, io, global_config_paths, pos_args.items[0], stdout, stderr, json_flag);
    } else if (std.mem.eql(u8, cmd, "deinit")) {
        try cmdDeinit(arena, io, global_config_paths, stdout, stderr, recursive_flag, delete_file_flag);
    } else {
        try stderr.print("error: unknown command '{s}'\n\n", .{cmd});
        try usage(stderr);
        try stderr.flush();
        return error.UnknownCommand;
    }

    try stdout.flush();
    try stderr.flush();
}

fn resolveHome(allocator: std.mem.Allocator, environ: std.process.Environ) ?[]const u8 {
    if (environ.getAlloc(allocator, "HOME") catch null) |h| return h;
    if (environ.getAlloc(allocator, "USERPROFILE") catch null) |h| return h;
    const drive = environ.getAlloc(allocator, "HOMEDRIVE") catch null;
    const path = environ.getAlloc(allocator, "HOMEPATH") catch null;
    if (drive != null and path != null) {
        return std.fmt.allocPrint(allocator, "{s}{s}", .{ drive.?, path.? }) catch null;
    }
    return null;
}

fn appendGlobalConfigPath(allocator: std.mem.Allocator, paths: *std.ArrayList([]const u8), parts: []const []const u8) void {
    const path = std.fs.path.join(allocator, parts) catch return;
    for (paths.items) |existing| {
        if (std.mem.eql(u8, existing, path)) return;
    }
    paths.append(allocator, path) catch {};
}

fn resolveGlobalConfigPaths(allocator: std.mem.Allocator, environ: std.process.Environ) []const []const u8 {
    var paths: std.ArrayList([]const u8) = .empty;

    if (environ.getAlloc(allocator, "XDG_CONFIG_HOME") catch null) |xdg| {
        appendGlobalConfigPath(allocator, &paths, &.{ xdg, "zrouter", "config.toml" });
    }
    if (environ.getAlloc(allocator, "APPDATA") catch null) |appdata| {
        appendGlobalConfigPath(allocator, &paths, &.{ appdata, "zrouter", "config.toml" });
    }
    if (resolveHome(allocator, environ)) |home| {
        appendGlobalConfigPath(allocator, &paths, &.{ home, "Library", "Application Support", "zrouter", "config.toml" });
        appendGlobalConfigPath(allocator, &paths, &.{ home, ".config", "zrouter", "config.toml" });
    }

    return paths.items;
}

fn usage(w: *Io.Writer) !void {
    try w.print(
        \\Usage: zrouter <command> [args] [--json]
        \\
        \\Commands:
        \\  version           Print zrouter version
        \\  update            Update zrouter from the latest GitHub release
        \\  init              Create .zrouter/config.toml and .memory/ scaffolding
        \\  refresh [<dir>]   Update <!-- zr:files --> and <!-- zr:routing --> blocks
        \\    -r, --recursive Refresh every CLAUDE.md under <dir>
        \\    --create       With -r, create CLAUDE.md for useful subdirectories
        \\  deinit            Strip <!-- zr:files --> and <!-- zr:routing --> blocks from ./CLAUDE.md
        \\    -r, --recursive Also strip blocks from every subdirectory CLAUDE.md
        \\    --delete-file   Delete subdirectory CLAUDE.md files entirely instead of stripping
        \\  query <path>      Show a file summary or filtered directory index
        \\
        \\Global config: XDG_CONFIG_HOME/zrouter/config.toml, APPDATA/zrouter/config.toml, or ~/.config/zrouter/config.toml
        \\Project config: .zrouter/config.toml
        \\
    , .{});
}

// ── version/update ────────────────────────────────────────

fn cmdVersion(stdout: *Io.Writer) !void {
    try stdout.print("zrouter {s}\n", .{build_options.version});
}

fn cmdUpdate(arena: std.mem.Allocator, io: Io, environ: std.process.Environ) !void {
    const tmp_path = try tempScriptPath(arena, io, environ);
    defer Dir.deleteFileAbsolute(io, tmp_path) catch {};

    const script = if (builtin.os.tag == .windows) build_options.install_ps1 else build_options.install_sh;
    try Dir.writeFile(Dir.cwd(), io, .{ .sub_path = tmp_path, .data = script });

    if (builtin.os.tag == .windows) {
        try exec(arena, io, &.{
            "powershell.exe",  "-ExecutionPolicy",    "Bypass", "-NonInteractive", "-File", tmp_path,
            "-CurrentVersion", build_options.version,
        });
    } else {
        try exec(arena, io, &.{ "sh", tmp_path, build_options.version });
    }
}

fn tempScriptPath(arena: std.mem.Allocator, io: Io, environ: std.process.Environ) ![]const u8 {
    var random_bytes: [8]u8 = undefined;
    io.random(&random_bytes);
    const suffix = std.mem.readInt(u64, &random_bytes, .little);
    const filename = if (builtin.os.tag == .windows)
        try std.fmt.allocPrint(arena, "zrouter-self-update-{x}.ps1", .{suffix})
    else
        try std.fmt.allocPrint(arena, "zrouter-self-update-{x}.sh", .{suffix});

    if (builtin.os.tag == .windows) {
        const tmp_dir = environ.getAlloc(arena, "TEMP") catch |err| switch (err) {
            error.EnvironmentVariableMissing => return std.fs.path.join(arena, &.{ "C:\\Windows\\Temp", filename }),
            else => return err,
        };
        return std.fs.path.join(arena, &.{ tmp_dir, filename });
    }

    const tmp_dir = environ.getAlloc(arena, "TMPDIR") catch |err| switch (err) {
        error.EnvironmentVariableMissing => "/tmp",
        else => return err,
    };
    return std.fs.path.join(arena, &.{ tmp_dir, filename });
}

fn exec(arena: std.mem.Allocator, io: Io, argv: []const []const u8) !void {
    _ = arena;
    var child = try std.process.spawn(io, .{
        .argv = argv,
        .stdin = .ignore,
        .expand_arg0 = .expand,
    });
    const term = try child.wait(io);
    switch (term) {
        .exited => |code| if (code != 0) return error.SelfUpdateFailed,
        else => return error.SelfUpdateFailed,
    }
}

// ── init ─────────────────────────────────────────────────

fn cmdInit(arena: std.mem.Allocator, io: Io, global_config_paths: []const []const u8, stdout: *Io.Writer, json: bool) !void {
    var created: std.ArrayList([]const u8) = .empty;

    Dir.cwd().access(io, ".zrouter/config.toml", .{}) catch {
        try Dir.cwd().createDirPath(io, ".zrouter");
        try Dir.writeFile(Dir.cwd(), io, .{
            .sub_path = ".zrouter/config.toml",
            .data =
            \\# zrouter project configuration
            \\# Global defaults live in XDG_CONFIG_HOME/zrouter/config.toml, APPDATA/zrouter/config.toml, or ~/.config/zrouter/config.toml
            \\# Built-in defaults (exclude, allow, known_files) are in the embedded default.toml.
            \\# All list fields here are appended to the defaults, not replaced.
            \\
            \\# token_coefficient = 4.0      # chars / coefficient ≈ token count
            \\# max_content_size  = 12288    # max bytes read per file
            \\# inline_max_files  = 12       # inline dirs with <= N filtered subtree files into parent indexes
            \\# respect_gitignore = true     # append supported .gitignore rules to exclude/allow
            \\
            \\# exclude = ["generated/", "fixtures/", "*.dat"]  # gitignore-ish patterns
            \\# allow   = ["fixtures/keep.json", "schema.db"]    # patterns that override exclude
            \\# transparent_dirs = ["!src", "source"] # remove defaults with !name, clear with !*
            \\# known_files  = [{name = "schema.sql", desc = "Database schema"}]
            \\
            ,
        });
        try created.append(arena, ".zrouter/config.toml");
    };

    try ensureFile(arena, io, ".memory/decisions.md",
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
    try ensureFile(arena, io, ".memory/patterns.md",
        \\# Patterns
        \\
        \\Reusable patterns observed in this codebase.
        \\
    , &created);
    try ensureFile(arena, io, ".memory/inbox.md",
        \\# Inbox
        \\
        \\Open questions, guesses, and unresolved observations.
        \\
    , &created);

    const refresh_result = try doRefresh(arena, io, global_config_paths, ".");

    if (json) {
        try stdout.print("{f}\n", .{std.json.fmt(.{
            .dir = ".",
            .created = created.items,
            .files_count = refresh_result.files_count,
            .status = "ok",
        }, .{})});
    } else {
        for (created.items) |path| try stdout.print("created {s}\n", .{path});
        try stdout.print("refreshed ./CLAUDE.md ({d} files)\n", .{refresh_result.files_count});
    }
}

fn ensureFile(arena: std.mem.Allocator, io: Io, path: []const u8, content: []const u8, created: *std.ArrayList([]const u8)) !void {
    Dir.cwd().access(io, path, .{}) catch {
        const dir = std.fs.path.dirname(path) orelse ".";
        try Dir.cwd().createDirPath(io, dir);
        try Dir.writeFile(Dir.cwd(), io, .{ .sub_path = path, .data = content });
        try created.append(arena, path);
    };
}

// ── refresh ──────────────────────────────────────────────

const RefreshResult = struct { files_count: usize };

const RouteEntry = struct {
    path: []const u8,
    routed: bool,
};

const DirectoryIndex = struct {
    files: []const zrouter.claude_md.FileEntry,
    route_paths: []const []const u8,
    route_set: []const bool,
    routes: []const RouteEntry,
    inline_dirs: []const []const u8,
};

fn cmdRefresh(arena: std.mem.Allocator, io: Io, global_config_paths: []const []const u8, dir_path: []const u8, stdout: *Io.Writer, json: bool, recursive: bool, create: bool) !void {
    const cfg = zrouter.config.load(arena, io, global_config_paths);

    if (recursive) {
        if (create) {
            const candidates = try zrouter.walker.findDirsNeedingClaudeMd(arena, io, dir_path, cfg.exclude, cfg.allow, cfg.transparent_dirs, cfg.inline_max_files);
            for (candidates) |d| try createClaudeMd(arena, io, d);
        }

        const dirs = try zrouter.walker.findAllDirsWithClaudeMd(arena, io, dir_path, cfg.exclude, cfg.allow);
        var total_files: usize = 0;
        for (dirs) |d| {
            const result = try doRefreshWithConfig(arena, io, cfg, d);
            total_files += result.files_count;
        }

        if (json) {
            try stdout.print("{f}\n", .{std.json.fmt(.{
                .dir = dir_path,
                .dirs_count = dirs.len,
                .files_count = total_files,
                .updated = true,
            }, .{})});
        } else {
            try stdout.print("updated {d} CLAUDE.md files ({d} files)\n", .{ dirs.len, total_files });
        }
        return;
    }

    const result = doRefreshWithConfig(arena, io, cfg, dir_path) catch |err| switch (err) {
        error.NoCLAUDEMd => {
            if (!json) try stdout.print("no CLAUDE.md in {s}\n", .{dir_path});
            return;
        },
        else => return err,
    };
    if (json) {
        try stdout.print("{f}\n", .{std.json.fmt(.{
            .dir = dir_path,
            .files_count = result.files_count,
            .updated = true,
        }, .{})});
    } else {
        const claude_disp = try std.fs.path.join(arena, &.{ dir_path, "CLAUDE.md" });
        try stdout.print("updated {s} ({d} files)\n", .{ claude_disp, result.files_count });
    }
}

fn createClaudeMd(arena: std.mem.Allocator, io: Io, dir_path: []const u8) !void {
    const claude_path = try std.fs.path.join(arena, &.{ dir_path, "CLAUDE.md" });
    Dir.cwd().access(io, claude_path, .{}) catch {
        const name = std.fs.path.basename(dir_path);
        const content = try std.fmt.allocPrint(arena,
            \\# {s}
            \\
            \\<!-- zr:files -->
            \\<!-- /zr:files -->
            \\<!-- zr:routing -->
            \\<!-- /zr:routing -->
            \\
        , .{name});
        try Dir.writeFile(Dir.cwd(), io, .{ .sub_path = claude_path, .data = content });
    };
}

fn doRefresh(arena: std.mem.Allocator, io: Io, global_config_paths: []const []const u8, dir_path: []const u8) !RefreshResult {
    const cfg = zrouter.config.load(arena, io, global_config_paths);
    return doRefreshWithConfig(arena, io, cfg, dir_path);
}

fn buildDirectoryIndex(arena: std.mem.Allocator, io: Io, cfg: zrouter.config.Config, dir_path: []const u8) !DirectoryIndex {
    const routing = try zrouter.walker.findSubdirsWithClaudeMd(arena, io, dir_path, cfg.exclude, cfg.allow, cfg.transparent_dirs, cfg.inline_max_files);
    var routed_dirs: std.ArrayList([]const u8) = .empty;
    var routes: std.ArrayList(RouteEntry) = .empty;
    for (routing.paths, routing.route_set) |path, routed| {
        if (routed) try routed_dirs.append(arena, path);
        try routes.append(arena, .{ .path = path, .routed = routed });
    }

    const files = try zrouter.walker.listFilesForIndex(arena, io, dir_path, cfg.exclude, cfg.allow, routed_dirs.items, routing.inline_dirs);

    var entries: std.ArrayList(zrouter.claude_md.FileEntry) = .empty;
    for (files) |f| {
        const full = try std.fs.path.join(arena, &.{ dir_path, f.path });
        const content = readMax(arena, io, full, cfg.max_content_size) catch continue;
        const desc = try zrouter.desc.extract(f.path, content, arena, cfg.known_files) orelse "";
        const tokens = @as(usize, @intFromFloat(@as(f64, @floatFromInt(f.size)) / cfg.token_coefficient));
        try entries.append(arena, .{ .path = f.path, .desc = desc, .tokens = tokens });
    }

    return .{
        .files = entries.items,
        .route_paths = routing.paths,
        .route_set = routing.route_set,
        .routes = routes.items,
        .inline_dirs = routing.inline_dirs,
    };
}

fn doRefreshWithConfig(arena: std.mem.Allocator, io: Io, cfg: zrouter.config.Config, dir_path: []const u8) !RefreshResult {
    const claude_path = try std.fs.path.join(arena, &.{ dir_path, "CLAUDE.md" });
    const existing = readMax(arena, io, claude_path, 64 * 1024) catch |err| switch (err) {
        error.FileNotFound => return error.NoCLAUDEMd,
        else => return err,
    };

    const index = try buildDirectoryIndex(arena, io, cfg, dir_path);
    const files_block = try zrouter.claude_md.buildFilesBlock(index.files, arena);
    var content = try zrouter.claude_md.ensureBlock(existing, "zr:files", arena);
    content = try zrouter.claude_md.replaceBlock(content, "zr:files", files_block, arena);

    const routing_block = try zrouter.claude_md.buildRoutingBlock(index.route_paths, index.route_set, arena);
    content = try zrouter.claude_md.ensureBlock(content, "zr:routing", arena);
    content = try zrouter.claude_md.replaceBlock(content, "zr:routing", routing_block, arena);

    try Dir.writeFile(Dir.cwd(), io, .{ .sub_path = claude_path, .data = content });
    return .{ .files_count = index.files.len };
}

// ── deinit ───────────────────────────────────────────────

fn stripZrBlocks(arena: std.mem.Allocator, io: Io, claude_path: []const u8) !void {
    const existing = readMax(arena, io, claude_path, 64 * 1024) catch return;
    var content = try zrouter.claude_md.removeBlock(existing, "zr:files", arena);
    content = try zrouter.claude_md.removeBlock(content, "zr:routing", arena);
    try Dir.writeFile(Dir.cwd(), io, .{ .sub_path = claude_path, .data = content });
}

fn cmdDeinit(arena: std.mem.Allocator, io: Io, global_config_paths: []const []const u8, stdout: *Io.Writer, stderr: *Io.Writer, recursive: bool, delete_file: bool) !void {
    const cfg = zrouter.config.load(arena, io, global_config_paths);
    var stripped: std.ArrayList([]const u8) = .empty;
    var deleted: std.ArrayList([]const u8) = .empty;

    // Always strip the root CLAUDE.md
    stripZrBlocks(arena, io, "CLAUDE.md") catch {};
    try stripped.append(arena, "CLAUDE.md");

    if (recursive) {
        const dirs = try zrouter.walker.findAllDirsWithClaudeMd(arena, io, ".", cfg.exclude, cfg.allow);
        for (dirs) |d| {
            if (std.mem.eql(u8, d, ".")) continue; // already handled root
            const claude_path = try std.fs.path.join(arena, &.{ d, "CLAUDE.md" });
            if (delete_file) {
                Dir.cwd().deleteFile(io, claude_path) catch continue;
                try deleted.append(arena, claude_path);
            } else {
                stripZrBlocks(arena, io, claude_path) catch continue;
                try stripped.append(arena, claude_path);
            }
        }
    }

    for (stripped.items) |p| try stdout.print("stripped {s}\n", .{p});
    for (deleted.items) |p| try stdout.print("deleted {s}\n", .{p});
    if (stripped.items.len == 0 and deleted.items.len == 0) {
        try stderr.print("no CLAUDE.md found\n", .{});
        try stderr.flush();
    }
}

// ── query ────────────────────────────────────────────────

fn isDirectory(io: Io, path: []const u8) bool {
    var dir = Dir.cwd().openDir(io, path, .{ .iterate = true }) catch return false;
    dir.close(io);
    return true;
}

fn cmdQuery(arena: std.mem.Allocator, io: Io, global_config_paths: []const []const u8, path: []const u8, stdout: *Io.Writer, stderr: *Io.Writer, json: bool) !void {
    const cfg = zrouter.config.load(arena, io, global_config_paths);

    if (isDirectory(io, path)) {
        const index = try buildDirectoryIndex(arena, io, cfg, path);
        if (json) {
            try stdout.print("{f}\n", .{std.json.fmt(.{
                .path = path,
                .kind = "directory",
                .files = index.files,
                .routes = index.routes,
                .inline_dirs = index.inline_dirs,
            }, .{})});
        } else {
            try stdout.print("{s}/\n", .{path});
            if (index.routes.len > 0) {
                try stdout.print("routes:\n", .{});
                for (index.routes) |route| {
                    if (route.routed) {
                        try stdout.print("- [{s}/]({s}/CLAUDE.md)\n", .{ route.path, route.path });
                    } else {
                        try stdout.print("- `{s}/` — inlined below\n", .{route.path});
                    }
                }
            }
            if (index.inline_dirs.len > 0) {
                try stdout.print("inline dirs:\n", .{});
                for (index.inline_dirs) |d| try stdout.print("- `{s}/`\n", .{d});
            }
            if (index.files.len > 0) {
                try stdout.print("files:\n{s}", .{try zrouter.claude_md.buildFilesBlock(index.files, arena)});
            }
        }
        return;
    }

    const content = readMax(arena, io, path, cfg.max_content_size) catch |err| {
        try stderr.print("error reading {s}: {}\n", .{ path, err });
        try stderr.flush();
        return;
    };

    const desc = try zrouter.desc.extract(path, content, arena, cfg.known_files) orelse "";
    const tokens = @as(usize, @intFromFloat(@as(f64, @floatFromInt(content.len)) / cfg.token_coefficient));

    if (json) {
        try stdout.print("{f}\n", .{std.json.fmt(.{
            .path = path,
            .kind = "file",
            .description = desc,
            .tokens = tokens,
        }, .{})});
    } else {
        try stdout.print("{s} — {s} (~{d} tok)\n", .{ path, desc, tokens });
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
