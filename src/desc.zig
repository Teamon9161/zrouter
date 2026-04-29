const std = @import("std");
const config = @import("config.zig");

const common = @import("desc/common.zig");
const markdown = @import("desc/markdown.zig");
const ziglang = @import("desc/ziglang.zig");
const ts_js = @import("desc/ts_js.zig");
const python = @import("desc/python.zig");
const go = @import("desc/go.zig");
const rust = @import("desc/rust.zig");
const c_family = @import("desc/c_family.zig");
const java = @import("desc/java.zig");
const ruby = @import("desc/ruby.zig");
const shell = @import("desc/shell.zig");
const data = @import("desc/data.zig");
const outline = @import("desc/outline.zig");

pub const Mode = enum {
    summary,
    outline,
};

pub fn parseMode(text: []const u8) ?Mode {
    if (std.mem.eql(u8, text, "summary")) return .summary;
    if (std.mem.eql(u8, text, "outline")) return .outline;
    return null;
}

/// Extract a one-line summary from file content.
/// known_files is checked first (project > global > embedded defaults).
pub fn extract(filename: []const u8, content: []const u8, allocator: std.mem.Allocator, known_files: []const config.KnownFile) !?[]const u8 {
    return extractWithMode(filename, content, allocator, known_files, .summary);
}

/// Extract a description using the requested detail mode.
pub fn extractWithMode(filename: []const u8, content: []const u8, allocator: std.mem.Allocator, known_files: []const config.KnownFile, mode: Mode) !?[]const u8 {
    if (mode == .summary) {
        if (knownFile(filename, known_files)) |desc| return desc;
    }

    const ext = std.fs.path.extension(filename);
    const parsed = switch (mode) {
        .summary => try extractSummary(filename, ext, content, allocator),
        .outline => try extractOutline(filename, ext, content, allocator),
    };
    if (parsed) |desc| return desc;

    if (mode == .outline) {
        if (knownFile(filename, known_files)) |desc| return desc;
    }
    return null;
}

fn knownFile(filename: []const u8, known_files: []const config.KnownFile) ?[]const u8 {
    const base = std.fs.path.basename(filename);
    for (known_files) |k| {
        if (std.mem.eql(u8, base, k.name)) return k.desc;
    }
    return null;
}

fn extractSummary(filename: []const u8, ext: []const u8, content: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    if (std.mem.eql(u8, ext, ".md")) return markdown.extract(content);
    if (std.mem.eql(u8, ext, ".zig")) return ziglang.extract(content, allocator);
    if (isTsJsExt(ext)) return ts_js.extract(content, allocator);
    if (std.mem.eql(u8, ext, ".py") or std.mem.eql(u8, ext, ".pyi")) return python.extract(content, allocator);
    if (std.mem.eql(u8, ext, ".go")) return go.extract(content, allocator);
    if (std.mem.eql(u8, ext, ".rs")) return rust.extract(content, allocator);
    if (c_family.isExt(ext)) return c_family.extract(content, allocator);
    if (std.mem.eql(u8, ext, ".java")) return java.extract(content, allocator);
    if (std.mem.eql(u8, ext, ".rb")) return ruby.extract(content, allocator);
    if (shell.isExt(ext) or shell.isFilename(filename)) return shell.extract(content, allocator);
    if (data.isJsonExt(ext)) {
        if (common.extractHeaderComment(content)) |desc| return desc;
        return data.extractJson(content, allocator);
    }
    if (std.mem.eql(u8, ext, ".toml")) {
        if (common.extractHeaderComment(content)) |desc| return desc;
        return data.extractToml(content, allocator);
    }
    if (std.mem.eql(u8, ext, ".yaml") or std.mem.eql(u8, ext, ".yml")) {
        if (common.extractHeaderComment(content)) |desc| return desc;
        return data.extractYaml(content, allocator);
    }

    return common.extractHeaderComment(content);
}

fn extractOutline(filename: []const u8, ext: []const u8, content: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    const body = if (std.mem.eql(u8, ext, ".md"))
        markdown.extract(content)
    else if (std.mem.eql(u8, ext, ".zig"))
        try ziglang.outline(content, allocator)
    else if (isTsJsExt(ext))
        try ts_js.outline(content, allocator)
    else if (std.mem.eql(u8, ext, ".py") or std.mem.eql(u8, ext, ".pyi"))
        try python.outline(content, allocator)
    else if (std.mem.eql(u8, ext, ".go"))
        try go.outline(content, allocator)
    else if (std.mem.eql(u8, ext, ".rs"))
        try rust.outline(content, allocator)
    else if (c_family.isExt(ext))
        try c_family.outline(content, allocator)
    else if (std.mem.eql(u8, ext, ".java"))
        try java.outline(content, allocator)
    else if (std.mem.eql(u8, ext, ".rb"))
        try ruby.outline(content, allocator)
    else if (shell.isExt(ext) or shell.isFilename(filename))
        try shell.outline(content, allocator)
    else if (data.isJsonExt(ext))
        try data.extractJson(content, allocator)
    else if (std.mem.eql(u8, ext, ".toml"))
        try data.extractToml(content, allocator)
    else if (std.mem.eql(u8, ext, ".yaml") or std.mem.eql(u8, ext, ".yml"))
        try data.extractYaml(content, allocator)
    else
        null;

    const structure = body orelse return common.extractHeaderComment(content);
    return try outline.addHeaderComment(content, structure, allocator, outlineCommentPrefix(filename, ext));
}

fn isTsJsExt(ext: []const u8) bool {
    return std.mem.eql(u8, ext, ".ts") or std.mem.eql(u8, ext, ".tsx") or
        std.mem.eql(u8, ext, ".js") or std.mem.eql(u8, ext, ".jsx") or
        std.mem.eql(u8, ext, ".mjs") or std.mem.eql(u8, ext, ".mts");
}

fn outlineCommentPrefix(filename: []const u8, ext: []const u8) []const u8 {
    if (std.mem.eql(u8, ext, ".py") or std.mem.eql(u8, ext, ".pyi") or
        std.mem.eql(u8, ext, ".rb") or shell.isExt(ext) or shell.isFilename(filename) or
        std.mem.eql(u8, ext, ".toml") or std.mem.eql(u8, ext, ".yaml") or std.mem.eql(u8, ext, ".yml"))
    {
        return "#";
    }
    return "//";
}

test "extract c family summaries" {
    const summary = (try extract("src/math.c",
        \\#include <stdio.h>
        \\struct Vec2 { float x; float y; };
        \\int add(int a, int b) { return a + b; }
        \\static void helper(void);
    , std.testing.allocator, &.{})).?;
    try std.testing.expectEqualStrings("struct Vec2, fn add, helper", summary);
}

test "extract java summaries" {
    const summary = (try extract("src/App.java",
        \\package app;
        \\public class App {
        \\  public void run() {
        \\  }
        \\}
    , std.testing.allocator, &.{})).?;
    try std.testing.expectEqualStrings("class App, method run", summary);
}

test "extract ruby and shell summaries" {
    const ruby_summary = (try extract("lib/task.rb",
        \\module Jobs
        \\  class Worker
        \\    def perform!
        \\    end
        \\  end
        \\end
    , std.testing.allocator, &.{})).?;
    try std.testing.expectEqualStrings("module Jobs, class Worker, def perform!", ruby_summary);

    const shell_summary = (try extract("install.sh",
        \\#!/usr/bin/env bash
        \\main() {
        \\  echo ok
        \\}
        \\function cleanup {
        \\  :
        \\}
    , std.testing.allocator, &.{})).?;
    try std.testing.expectEqualStrings("sh fn main, cleanup", shell_summary);
}

test "extract data format summaries" {
    const json = (try extract("config.json",
        \\{
        \\  "name": "demo",
        \\  "scripts": {"test": "zig build test"},
        \\  "dependencies": {}
        \\}
    , std.testing.allocator, &.{})).?;
    try std.testing.expectEqualStrings("JSON keys name, scripts, dependencies", json);

    const toml = (try extract("settings.toml",
        \\title = "demo"
        \\[build]
        \\target = "native"
    , std.testing.allocator, &.{})).?;
    try std.testing.expectEqualStrings("TOML sections build", toml);

    const yaml = (try extract("workflow.yaml",
        \\name: ci
        \\on: push
        \\jobs:
        \\  test:
    , std.testing.allocator, &.{})).?;
    try std.testing.expectEqualStrings("YAML keys name, on, jobs", yaml);
}

test "rust outline uses code-like signatures" {
    const rust_outline = (try extractWithMode("src/lib.rs",
        \\pub struct Account {
        \\    balance: u64,
        \\}
        \\
        \\impl Account {
        \\    pub fn new(balance: u64) -> Self {
        \\        Self { balance }
        \\    }
        \\
        \\    pub fn balance(&self) -> u64 {
        \\        self.balance
        \\    }
        \\}
    , std.testing.allocator, &.{}, .outline)).?;

    try std.testing.expectEqualStrings(
        \\pub struct Account { ... }
        \\impl Account {
        \\    pub fn new(balance: u64) -> Self;
        \\    pub fn balance(&self) -> u64;
        \\}
    , rust_outline);
}

test "outline includes header comment and structure for non-rust" {
    const py_outline = (try extractWithMode("tools/build.py",
        \\# Build release artifacts.
        \\
        \\class Builder:
        \\    pass
        \\
        \\def main():
        \\    pass
    , std.testing.allocator, &.{}, .outline)).?;

    try std.testing.expectEqualStrings(
        \\# Build release artifacts.
        \\class Builder: ...
        \\def main(): ...
    , py_outline);

    const ts_outline = (try extractWithMode("src/api.ts",
        \\// Public API surface.
        \\export interface Request {
        \\  id: string
        \\}
        \\export function run(req: Request) {
        \\  return req.id
        \\}
    , std.testing.allocator, &.{}, .outline)).?;

    try std.testing.expectEqualStrings(
        \\// Public API surface.
        \\export interface Request { ... }
        \\export function run(req: Request);
    , ts_outline);
}
