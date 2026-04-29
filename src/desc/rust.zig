const std = @import("std");
const common = @import("common.zig");

pub fn extract(content: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    var pub_names: std.ArrayList([]const u8) = .empty;
    var impl_types: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, content, '\n');

    while (lines.next()) |line| {
        if (pub_names.items.len >= common.max_names) break;
        const t = std.mem.trim(u8, line, " \t\r");
        if (std.mem.startsWith(u8, t, "#[")) continue;

        if (impl_types.items.len < common.max_names and isImplLine(t)) {
            const name = implTargetName(t);
            if (name.len > 0 and !contains(impl_types.items, name)) try impl_types.append(allocator, name);
            continue;
        }

        var rest = afterPubVisibility(t) orelse continue;

        if (std.mem.startsWith(u8, rest, "use ")) {
            const name = useName(rest["use ".len..]);
            if (name.len > 0) try pub_names.append(allocator, name);
            continue;
        }

        rest = skipPubQualifiers(rest);
        const keywords = [_][]const u8{ "fn ", "struct ", "enum ", "trait ", "type ", "union " };
        for (&keywords) |kw| {
            if (std.mem.startsWith(u8, rest, kw)) {
                const name = common.extractIdent(rest[kw.len..]);
                if (name.len > 0) try pub_names.append(allocator, name);
                break;
            }
        }
    }

    if (pub_names.items.len > 0) {
        return try std.fmt.allocPrint(allocator, "pub {s}", .{try common.joinNames(pub_names.items, allocator)});
    }
    if (impl_types.items.len > 0) {
        return try std.fmt.allocPrint(allocator, "impl {s}", .{try common.joinNames(impl_types.items, allocator)});
    }
    return common.extractHeaderComment(content);
}

pub fn outline(content: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var lines = std.mem.splitScalar(u8, content, '\n');
    var in_impl = false;
    var impl_depth: i32 = 0;
    var impl_has_methods = false;

    while (lines.next()) |line| {
        const t = std.mem.trim(u8, line, " \t\r");
        if (t.len == 0 or std.mem.startsWith(u8, t, "#[")) continue;

        if (in_impl) {
            if (isVisibleFnLine(t)) {
                const sig = try renderFnSignature(t, allocator);
                try out.appendSlice(allocator, "    ");
                try out.appendSlice(allocator, sig);
                try out.append(allocator, '\n');
                impl_has_methods = true;
            }

            impl_depth += braceDelta(t);
            if (impl_depth <= 0) {
                if (!impl_has_methods and out.items.len > 0 and out.items[out.items.len - 1] == '{') {
                    try out.appendSlice(allocator, " }\n");
                } else {
                    try out.appendSlice(allocator, "}\n");
                }
                in_impl = false;
            }
            continue;
        }

        if (isVisibleUseLine(t)) {
            try appendLine(allocator, &out, t);
            continue;
        }

        if (afterPubVisibility(t) != null) {
            if (renderPubItem(t, allocator)) |item| {
                try appendLine(allocator, &out, item);
                continue;
            }
        }

        if (isImplLine(t)) {
            const header = implHeader(t, allocator) catch null;
            if (header) |h| {
                try out.appendSlice(allocator, h);
                try out.appendSlice(allocator, " {\n");
                in_impl = true;
                impl_depth = braceDelta(t);
                if (impl_depth <= 0) impl_depth = 1;
                impl_has_methods = false;
            }
        }
    }

    if (in_impl) try out.appendSlice(allocator, "}\n");
    if (out.items.len == 0) return extract(content, allocator);
    return std.mem.trimEnd(u8, out.items, "\n");
}

fn appendLine(allocator: std.mem.Allocator, out: *std.ArrayList(u8), line: []const u8) !void {
    try out.appendSlice(allocator, line);
    try out.append(allocator, '\n');
}

fn renderPubItem(t: []const u8, allocator: std.mem.Allocator) ?[]const u8 {
    const rest = skipPubQualifiers(afterPubVisibility(t) orelse return null);
    const vis = visibilityPrefix(t);
    const specs = [_]struct { kw: []const u8, render: []const u8 }{
        .{ .kw = "struct ", .render = "struct" },
        .{ .kw = "enum ", .render = "enum" },
        .{ .kw = "trait ", .render = "trait" },
        .{ .kw = "union ", .render = "union" },
    };

    for (&specs) |spec| {
        if (std.mem.startsWith(u8, rest, spec.kw)) {
            const name = common.extractIdent(rest[spec.kw.len..]);
            if (name.len == 0) return null;
            return std.fmt.allocPrint(allocator, "{s} {s} {s} {{ ... }}", .{ vis, spec.render, name }) catch null;
        }
    }

    if (std.mem.startsWith(u8, rest, "type ")) {
        const semi = std.mem.indexOfScalar(u8, rest, ';') orelse rest.len;
        return std.fmt.allocPrint(allocator, "pub {s};", .{std.mem.trim(u8, rest[0..semi], " \t\r;")}) catch null;
    }

    if (std.mem.startsWith(u8, rest, "fn ")) {
        return renderFnSignature(t, allocator) catch null;
    }

    return null;
}

fn afterPubVisibility(t: []const u8) ?[]const u8 {
    if (std.mem.startsWith(u8, t, "pub ")) return t["pub ".len..];
    if (!std.mem.startsWith(u8, t, "pub(")) return null;
    const close = std.mem.indexOfScalar(u8, t, ')') orelse return null;
    return std.mem.trimStart(u8, t[close + 1 ..], " \t");
}

fn visibilityPrefix(t: []const u8) []const u8 {
    if (std.mem.startsWith(u8, t, "pub(")) {
        const close = std.mem.indexOfScalar(u8, t, ')') orelse return "pub";
        return t[0 .. close + 1];
    }
    return "pub";
}

fn isVisibleUseLine(t: []const u8) bool {
    const rest = afterPubVisibility(t) orelse return false;
    return std.mem.startsWith(u8, rest, "use ");
}

fn isVisibleFnLine(t: []const u8) bool {
    const rest = skipPubQualifiers(afterPubVisibility(t) orelse return false);
    return std.mem.startsWith(u8, rest, "fn ") or
        std.mem.startsWith(u8, rest, "async fn ") or
        std.mem.startsWith(u8, rest, "const fn ") or
        std.mem.startsWith(u8, rest, "unsafe fn ");
}

fn renderFnSignature(t: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    const body = if (std.mem.indexOfScalar(u8, t, '{')) |idx| t[0..idx] else t;
    const trimmed = std.mem.trim(u8, body, " \t\r;");
    return try std.fmt.allocPrint(allocator, "{s};", .{trimmed});
}

fn isImplLine(t: []const u8) bool {
    return std.mem.startsWith(u8, t, "impl ") or std.mem.startsWith(u8, t, "impl<");
}

fn implTargetName(t: []const u8) []const u8 {
    const rest = common.skipGenericParams(std.mem.trimStart(u8, t["impl".len..], " \t"));
    if (std.mem.indexOf(u8, rest, " for ")) |for_idx| {
        const after = common.skipGenericParams(std.mem.trimStart(u8, rest[for_idx + " for ".len ..], " \t"));
        return common.extractIdent(after);
    }
    return common.extractIdent(rest);
}

fn implHeader(t: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    const open = std.mem.indexOfScalar(u8, t, '{') orelse t.len;
    const header = std.mem.trim(u8, t[0..open], " \t\r");
    if (!isImplLine(header)) return null;
    return try allocator.dupe(u8, header);
}

fn useName(text: []const u8) []const u8 {
    const use_rest = std.mem.trim(u8, text, "; \t\r");
    if (std.mem.lastIndexOf(u8, use_rest, " as ")) |as_idx| {
        return common.extractIdent(std.mem.trimStart(u8, use_rest[as_idx + " as ".len ..], " \t"));
    }
    if (std.mem.lastIndexOfScalar(u8, use_rest, ':')) |colon| {
        return common.extractIdent(use_rest[colon + 1 ..]);
    }
    return common.extractIdent(use_rest);
}

fn skipPubQualifiers(s: []const u8) []const u8 {
    var rest = s;
    while (true) {
        rest = std.mem.trimStart(u8, rest, " ");
        if (std.mem.startsWith(u8, rest, "unsafe ")) {
            rest = rest["unsafe ".len..];
        } else if (std.mem.startsWith(u8, rest, "default ")) {
            rest = rest["default ".len..];
        } else if (std.mem.startsWith(u8, rest, "extern ")) {
            rest = rest["extern ".len..];
            if (rest.len > 0 and rest[0] == '"') {
                const close = std.mem.indexOfScalar(u8, rest[1..], '"') orelse break;
                rest = rest[1 + close + 1 ..];
            }
        } else {
            break;
        }
    }
    return rest;
}

fn braceDelta(t: []const u8) i32 {
    var delta: i32 = 0;
    for (t) |c| {
        if (c == '{') delta += 1 else if (c == '}') delta -= 1;
    }
    return delta;
}

fn contains(items: []const []const u8, name: []const u8) bool {
    for (items) |item| if (std.mem.eql(u8, item, name)) return true;
    return false;
}
