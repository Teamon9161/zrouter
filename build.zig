const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const version = b.option([]const u8, "version", "Version string embedded in the binary") orelse "0.1.0";

    const toml_dep = b.dependency("toml", .{ .target = target, .optimize = optimize });
    const toml_mod = toml_dep.module("toml");

    const options = b.addOptions();
    options.addOption([]const u8, "version", version);
    options.addOption([]const u8, "install_sh", @embedFile("install.sh"));
    options.addOption([]const u8, "install_ps1", @embedFile("install.ps1"));

    const mod = b.addModule("zrouter", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });
    mod.addImport("toml", toml_mod);

    const exe_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zrouter", .module = mod },
        },
    });
    exe_module.addOptions("build_options", options);

    const exe = b.addExecutable(.{
        .name = "zrouter",
        .root_module = exe_module,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const mod_tests = b.addTest(.{ .root_module = mod });
    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&b.addRunArtifact(mod_tests).step);
    test_step.dependOn(&b.addRunArtifact(exe_tests).step);
}
