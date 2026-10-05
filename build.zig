const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const mod = b.addModule("numeral", .{ .root_source_file = b.path("src/root.zig"), .target = target, .optimize = optimize });
    const tests = b.addTest(.{ .root_module = mod });
    b.step("test", "Run unit and numbro compatibility tests").dependOn(&b.addRunArtifact(tests).step);
    const example = b.addExecutable(.{ .name = "numeral-example", .root_module = b.createModule(.{ .root_source_file = b.path("examples/basic.zig"), .target = target, .optimize = optimize, .imports = &.{.{ .name = "numeral", .module = mod }} }) });
    b.step("examples", "Compile examples").dependOn(&example.step);
    b.step("run", "Run examples").dependOn(&b.addRunArtifact(example).step);
    b.getInstallStep().dependOn(&example.step);
    const docs_object = b.addObject(.{ .name = "numeral-docs", .root_module = mod });
    const docs_install = b.addInstallDirectory(.{ .source_dir = docs_object.getEmittedDocs(), .install_dir = .prefix, .install_subdir = "docs" });
    b.step("docs", "Generate Zig API documentation in zig-out/docs").dependOn(&docs_install.step);
    const check = b.step("check", "Compile tests and examples without running (also for cross targets)");
    check.dependOn(&tests.step);
    check.dependOn(&example.step);
}
