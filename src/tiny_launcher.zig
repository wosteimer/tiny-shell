const std = @import("std");
const c = @cImport({
    @cInclude("gtk/gtk.h");
    @cInclude("gtk4-layer-shell/gtk4-layer-shell.h");
});

pub fn activate(a: *c.GtkApplication, data: c.gpointer) callconv(.C) void {
    std.debug.assert(c.gtk_layer_is_supported() != 0);
    _ = data;
    const window: *c.GtkWindow = @ptrCast(c.gtk_application_window_new(a));
    c.gtk_layer_init_for_window(window);
    c.gtk_layer_set_layer(window, c.GTK_LAYER_SHELL_LAYER_TOP);
    c.gtk_window_set_title(window, "tiny launcher");
    c.gtk_window_set_child(window, c.gtk_label_new("Hello Window"));
    c.gtk_window_set_default_size(window, 400, 400);
    c.gtk_window_present(window);
}

pub fn main() !void {
    const app = c.gtk_application_new(
        "com.github.wosteimer.tiny-launcher",
        c.G_APPLICATION_DEFAULT_FLAGS,
    ) orelse @panic("null app :(");
    defer c.g_object_unref(app);
    _ = c.g_signal_connect_data(
        @ptrCast(app),
        "activate",
        @ptrCast(&activate),
        null,
        null,
        0,
    );
    _ = c.g_application_run(@ptrCast(app), 0, null);
}
