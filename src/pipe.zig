const std = @import("std");
const Io = std.Io;
const toml = @import("toml");

const FilterDef = struct {
    description: ?[]const u8 = null,
    match_command: []const u8 = "",
    strip_lines_matching: ?[]const []const u8 = null,
};

const FiltersFile = struct {
    schema_version: ?u32 = null,
    filters: ?[]const FilterDef = null,
};

const BUILTIN = @embedFile("assets/filters.toml");

pub fn run(
    arena: std.mem.Allocator,
    io: Io,
    stdout: *Io.Writer,
    cmd_str: ?[]const u8,
) !void {
    const input = try readAllStdin(arena, io);

    const output = if (cmd_str) |cmd| blk: {
        const filters = parseFilters(arena, BUILTIN);
        for (filters) |f| {
            if (matchCommand(cmd, f.match_command)) {
                break :blk try applyFilter(arena, input, f);
            }
        }
        break :blk input;
    } else input;

    try stdout.writeAll(output);
}

fn parseFilters(arena: std.mem.Allocator, content: []const u8) []const FilterDef {
    var parser = toml.Parser(FiltersFile).init(arena);
    const result = parser.parseString(content) catch return &.{};
    return result.value.filters orelse &.{};
}

fn matchCommand(cmd: []const u8, pattern: []const u8) bool {
    if (pattern.len == 0) return false;
    return std.mem.indexOf(u8, cmd, pattern) != null;
}

fn matchLine(line: []const u8, pattern: []const u8) bool {
    if (pattern.len == 0) return false;
    if (pattern[0] == '^') return std.mem.startsWith(u8, line, pattern[1..]);
    return std.mem.indexOf(u8, line, pattern) != null;
}

fn applyFilter(arena: std.mem.Allocator, input: []const u8, filter: FilterDef) ![]u8 {
    const patterns = filter.strip_lines_matching orelse return try arena.dupe(u8, input);
    if (patterns.len == 0) return try arena.dupe(u8, input);

    var out: std.ArrayList(u8) = .empty;
    const trailing_newline = input.len > 0 and input[input.len - 1] == '\n';
    var lines = std.mem.splitScalar(u8, input, '\n');
    var first_out = true;
    while (lines.next()) |raw| {
        // Strip \r for CRLF inputs
        const line = if (raw.len > 0 and raw[raw.len - 1] == '\r') raw[0 .. raw.len - 1] else raw;
        var strip = false;
        for (patterns) |pat| {
            if (matchLine(line, pat)) {
                strip = true;
                break;
            }
        }
        if (!strip) {
            if (!first_out) try out.append(arena, '\n');
            try out.appendSlice(arena, line);
            first_out = false;
        }
    }
    if (trailing_newline and out.items.len > 0) try out.append(arena, '\n');
    return out.items;
}

fn readAllStdin(arena: std.mem.Allocator, io: Io) ![]u8 {
    var rbuf: [8192]u8 = undefined;
    var stdin_fr: Io.File.Reader = .initStreaming(.stdin(), io, &rbuf);
    var content: std.ArrayList(u8) = .empty;
    stdin_fr.interface.appendRemainingUnlimited(arena, &content) catch |err| switch (err) {
        error.ReadFailed => {},
        else => return err,
    };
    return content.items;
}
