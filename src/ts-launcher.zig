const std = @import("std");
const c = @cImport({
    @cInclude("gtk/gtk.h");
    @cInclude("gtk4-layer-shell/gtk4-layer-shell.h");
    @cInclude("adwaita.h");
});
const TsLauncherWindow = @import("ts-launcher-window.zig").TsLauncherWindow;

fn activate(app: *c.GtkApplication, _: c.gpointer) callconv(.C) void {
    const css_provider = c.gtk_css_provider_new();
    const display = c.gdk_display_get_default();
    c.gtk_css_provider_load_from_resource(css_provider, "com/github/wosteimer/tiny/launcher/css/style.css");
    c.gtk_style_context_add_provider_for_display(
        display,
        @ptrCast(css_provider),
        c.GTK_STYLE_PROVIDER_PRIORITY_APPLICATION,
    );
    const window: *c.GtkWindow = @ptrCast(TsLauncherWindow.new());
    c.gtk_window_set_application(window, app);
    c.gtk_layer_init_for_window(window);
    c.gtk_layer_set_layer(window, c.GTK_LAYER_SHELL_LAYER_TOP);
    c.gtk_layer_set_keyboard_mode(window, c.GTK_LAYER_SHELL_KEYBOARD_MODE_ON_DEMAND);
    c.gtk_window_present(window);
}

pub fn main() !void {
    const app = c.adw_application_new(
        "com.github.wosteimer.tiny-launcher",
        c.G_APPLICATION_DEFAULT_FLAGS,
    );

    defer c.g_object_unref(app);

    _ = c.g_signal_connect_data(
        @ptrCast(app),
        "activate",
        @ptrCast(&activate),
        null,
        null,
        c.G_TYPE_FLAG_FINAL,
    );
    _ = c.g_application_run(@ptrCast(app), 0, null);
}
