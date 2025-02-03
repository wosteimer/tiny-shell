const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // const lib = b.addSharedLibrary(.{
    //     .name = "tiny-shell",
    //     .root_source_file = b.path("src/root.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });
    // lib.linkLibC();
    // lib.linkSystemLibrary("gmodule-export-2.0");
    // b.installArtifact(lib);

    const gen_resources_header = b.addSystemCommand(&.{
        "glib-compile-resources",
        "--generate-header",
        "resources.gresource.xml",
    });
    gen_resources_header.setCwd(b.path("src/resources")); // Define o diretório de trabalho

    const gen_resources_source = b.addSystemCommand(&.{
        "glib-compile-resources",
        "--generate-source",
        "resources.gresource.xml",
    });
    gen_resources_source.setCwd(b.path("src/resources"));
    gen_resources_source.step.dependOn(&gen_resources_header.step);

    const tiny_launcher = b.addExecutable(.{
        .name = "tiny-launcher",
        .root_source_file = b.path("src/tiny_launcher.zig"),
        .target = target,
        .optimize = optimize,
    });
    tiny_launcher.addCSourceFile(.{ .file = b.path("src/resources/resources.c") });
    tiny_launcher.addIncludePath(b.path("src/resources"));
    // tiny_launcher.linkLibrary(lib);
    tiny_launcher.linkLibC();
    tiny_launcher.linkSystemLibrary("gtk4");
    tiny_launcher.linkSystemLibrary("gtk4-layer-shell");
    tiny_launcher.linkSystemLibrary("gio-unix-2.0");
    b.installArtifact(tiny_launcher);

    const tiny_launcher_cmd = b.addRunArtifact(tiny_launcher);

    tiny_launcher_cmd.step.dependOn(&gen_resources_source.step);

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
