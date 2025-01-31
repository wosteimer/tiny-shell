const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "tiny-shell",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(lib);

    const tiny_launcher = b.addExecutable(.{
        .name = "tiny-launcher",
        .root_source_file = b.path("src/tiny_launcher.zig"),
        .target = target,
        .optimize = optimize,
    });
    tiny_launcher.linkLibC();
    tiny_launcher.linkSystemLibrary("gtk4");
    tiny_launcher.linkSystemLibrary("gtk4-layer-shell");
    b.installArtifact(tiny_launcher);

    const tiny_launcher_cmd = b.addRunArtifact(tiny_launcher);

    tiny_launcher_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        tiny_launcher_cmd.addArgs(args);
    }

    const run_step = b.step("run-launcher", "Run the app");
    run_step.dependOn(&tiny_launcher_cmd.step);

    // const lib_unit_tests = b.addTest(.{
    //     .root_source_file = b.path("src/root.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });
    //
    // const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    //
    // const exe_unit_tests = b.addTest(.{
    //     .root_source_file = b.path("src/main.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });
    //
    // const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    //
    // const test_step = b.step("test", "Run unit tests");
    // test_step.dependOn(&run_lib_unit_tests.step);
    // test_step.dependOn(&run_exe_unit_tests.step);
}
