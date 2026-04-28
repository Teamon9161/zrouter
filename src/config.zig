const std = @import("std");
const Io = std.Io;
const Dir = Io.Dir;

pub const Config = struct {
    exclude_patterns: []const []const u8 = &.{},
    token_coefficient: f64 = 4.0,
    version: u32 = 1,

    pub fn load(allocator: std.mem.Allocator, io: Io) Config {
        const max_size = 16 * 1024;
        const buf = allocator.alloc(u8, max_size) catch return Config{};
        const content = Dir.cwd().readFile(io, ".zrouter/config.json", buf) catch return Config{};

        const parsed = std.json.parseFromSlice(std.json.Value, allocator, content, .{}) catch return Config{};
        const root = parsed.value;
        if (root != .object) return Config{};

        var config = Config{};

        if (root.object.get("version")) |v| {
            if (v == .integer) config.version = @intCast(v.integer);
        }
        if (root.object.get("token_coefficient")) |c| {
            if (c == .float) config.token_coefficient = c.float;
        }
        if (root.object.get("exclude_patterns")) |patterns| {
            if (patterns == .array) {
                var list: std.ArrayList([]const u8) = .empty;
                for (patterns.array.items) |item| {
                    if (item == .string) list.append(allocator, item.string) catch {};
                }
                config.exclude_patterns = list.items;
            }
        }

        return config;
    }
};
