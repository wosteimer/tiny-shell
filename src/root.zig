const std = @import("std");
const c = @cImport({
    @cInclude("gtk/gtk.h");
    @cInclude("gtk4-layer-shell/gtk4-layer-shell.h");
    @cInclude("gio/gdesktopappinfo.h");
});

pub const TinyLauncher = struct {
    application: *c.GObject,
    builder: *c.GtkBuilder,
    model: *c.GListStore,

    const Self = @This();
    pub fn init() Self {
        return struct {};
    }
    pub fn run(self: Self) void {}
    fn activate() callconv(.C) void {}
};
