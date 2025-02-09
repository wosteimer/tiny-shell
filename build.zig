const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(
        .{ .preferred_optimize_mode = .ReleaseFast },
    );
    const gen_resources_header = b.addSystemCommand(&.{
        "glib-compile-resources",
        "--generate-header",
        "data.gresource.xml",
    });
    gen_resources_header.setCwd(b.path("data"));
    const gen_resources_source = b.addSystemCommand(&.{
        "glib-compile-resources",
        "--generate-source",
        "data.gresource.xml",
    });
    gen_resources_source.setCwd(b.path("data"));
    gen_resources_source.step.dependOn(&gen_resources_header.step);
    const ts_launcher = b.addExecutable(.{
        .name = "ts-launcher",
        .root_source_file = b.path("src/ts-launcher.zig"),
        .target = target,
        .optimize = optimize,
    });
    ts_launcher.addCSourceFile(.{ .file = b.path("data/data.c") });
    ts_launcher.addIncludePath(b.path("data"));
    ts_launcher.linkLibC();
    ts_launcher.linkSystemLibrary("libadwaita-1");
    ts_launcher.linkSystemLibrary("gtk4");
    ts_launcher.linkSystemLibrary("gtk4-layer-shell");
    ts_launcher.linkSystemLibrary("gio-unix-2.0");
    b.installArtifact(ts_launcher);
    const ts_launcher_cmd = b.addRunArtifact(ts_launcher);
    ts_launcher_cmd.step.dependOn(&gen_resources_source.step);
    if (b.args) |args| {
        ts_launcher_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&ts_launcher_cmd.step);
    const ts_model_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/ts-model.zig"),
        .target = target,
        .optimize = optimize,
    });
    ts_model_unit_tests.linkLibC();
    ts_model_unit_tests.linkSystemLibrary("libadwaita-1");
    ts_model_unit_tests.linkSystemLibrary("gtk4");
    ts_model_unit_tests.linkSystemLibrary("gtk4-layer-shell");
    ts_model_unit_tests.linkSystemLibrary("gio-unix-2.0");
    const run_ts_model_unit_tests = b.addRunArtifact(ts_model_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_ts_model_unit_tests.step);
}
