const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(
        .{ .preferred_optimize_mode = .Debug },
    );

    const gobject = b.dependency("gobject", .{
        .target = target,
        .optimize = optimize,
    });

    const libintl = b.dependency("libintl", .{
        .target = target,
        .optimize = optimize,
    });

    const main = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    main.linkSystemLibrary("gtk4", .{});
    main.linkSystemLibrary("gtk4-layer-shell", .{});

    const exe = b.addExecutable(.{
        .name = "ts-shell",
        .root_module = main,
    });
    exe.root_module.addImport("gtk", gobject.module("gtk4"));
    exe.root_module.addImport("adw", gobject.module("adw1"));
    exe.root_module.addImport("gio", gobject.module("gio2"));
    exe.root_module.addImport("giounix", gobject.module("giounix2"));
    exe.root_module.addImport("gobject", gobject.module("gobject2"));
    exe.root_module.addImport("glib", gobject.module("glib2"));
    exe.root_module.addImport("gdk", gobject.module("gdk4"));
    exe.root_module.addImport("libintl", libintl.module("libintl"));
    exe.root_module.addImport("graphene", gobject.module("graphene1"));
    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_exe.step);
}
