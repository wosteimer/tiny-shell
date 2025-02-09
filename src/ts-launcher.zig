const std = @import("std");
const c = @import("c.zig");
const TsLauncherWindow = @import("ts-launcher-window.zig").TsLauncherWindow;
const TS_LAUNCHER_WINDOW = @import("ts-launcher-window.zig").TS_LAUNCHER_WINDOW;

const APP_ID = "com.github.wosteimer.tiny.launcher";
const DBUS_OBJECT_PATH = "/com/github/wosteimer/tiny/launcher";

pub fn main() !void {
    const app = c.adw_application_new(
        APP_ID,
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

fn activate(app: *c.GtkApplication, _: c.gpointer) callconv(.C) void {
    const css_provider = c.gtk_css_provider_new();
    const display = c.gdk_display_get_default();
    c.gtk_css_provider_load_from_resource(
        css_provider,
        "com/github/wosteimer/tiny/launcher/css/style.css",
    );
    c.gtk_style_context_add_provider_for_display(
        display,
        @ptrCast(css_provider),
        c.GTK_STYLE_PROVIDER_PRIORITY_APPLICATION,
    );
    const window: *c.GtkWindow = @ptrCast(TsLauncherWindow.new());
    c.gtk_window_set_application(window, app);
    c.gtk_layer_init_for_window(window);
    c.gtk_layer_set_layer(window, c.GTK_LAYER_SHELL_LAYER_TOP);
    c.gtk_layer_set_keyboard_mode(
        window,
        c.GTK_LAYER_SHELL_KEYBOARD_MODE_EXCLUSIVE,
    );
    //c.gtk_window_present(window);
    _ = c.g_bus_own_name(
        c.G_BUS_TYPE_SESSION,
        APP_ID,
        c.G_BUS_NAME_WATCHER_FLAGS_NONE,
        @ptrCast(&onBusAcquired),
        null,
        null,
        @ptrCast(window),
        null,
    );
}

fn onBusAcquired(
    connection: *c.GDBusConnection,
    _: [*:0]const u8,
    user_data: c.gpointer,
) callconv(.C) void {
    _ = c.g_dbus_connection_signal_subscribe(
        connection,
        null,
        APP_ID,
        "Show",
        DBUS_OBJECT_PATH,
        null,
        c.G_DBUS_SIGNAL_FLAGS_NONE,
        @ptrCast(&onShowSignal),
        user_data,
        null,
    );
}

fn onShowSignal(
    _: *c.GDBusConnection,
    _: [*:0]const u8,
    _: [*:0]const u8,
    _: [*:0]const u8,
    _: [*:0]const u8,
    _: *c.GVariant,
    user_data: c.gpointer,
) callconv(.C) void {
    const window = TS_LAUNCHER_WINDOW(user_data);
    window.show();
}
