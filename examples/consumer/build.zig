const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "numeral-consumer",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const numeral_dependency = b.dependency("z_numeral", .{ .target = target, .optimize = optimize });
    exe.root_module.addImport("numeral", numeral_dependency.module("numeral"));
    b.installArtifact(exe);
    b.step("run", "Run the consumer example").dependOn(&b.addRunArtifact(exe).step);
}
