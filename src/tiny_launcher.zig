const std = @import("std");
const c = @cImport({
    @cInclude("gtk/gtk.h");
    @cInclude("gtk4-layer-shell/gtk4-layer-shell.h");
    @cInclude("gio/gdesktopappinfo.h");
    @cInclude("adwaita.h");
});
const TsLauncherWindow = @import("ts-launcher-window.zig").TsLauncherWindow;
const list_item = @import("ts-list-item.zig");

fn onSearchChanged(search_entry: *c.GtkSearchEntry, builder: *c.GtkBuilder) callconv(.C) void {
    const text = c.gtk_editable_get_text(@ptrCast(search_entry));
    const result = c.g_desktop_app_info_search(text);
    defer c.g_free(@ptrCast(result));
    const model = c.g_list_store_new(c.g_app_info_get_type());
    defer c.g_object_unref(@ptrCast(model));
    var i: usize = 0;
    while (result[i] != null) : (i += 1) {
        var j: usize = 0;
        defer c.g_strfreev(result[i]);
        while (result[i][j] != null) : (j += 1) {
            const app_id = result[i][j];
            const app_info = c.g_desktop_app_info_new(app_id);
            defer c.g_object_unref(@ptrCast(app_info));
            c.g_list_store_append(model, app_info);
        }
    }
    c.g_strfreev(result[i]);
    const list_box = c.gtk_builder_get_object(builder, "list_box");
    c.gtk_list_box_bind_model(@ptrCast(list_box), @ptrCast(model), @ptrCast(&list_item.TsListItem.new), builder, null);
    c.gtk_list_box_select_row(@ptrCast(list_box), c.gtk_list_box_get_row_at_index(@ptrCast(list_box), 0));
}

pub fn onActivate(_: *c.GtkListBox, list_row: *list_item.TsListItem, _: c.gpointer) callconv(.C) void {
    list_row.launch();
}

fn activate(app: *c.GtkApplication, data: c.gpointer) callconv(.C) void {
    _ = data;
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
        0,
    );
    _ = c.g_application_run(@ptrCast(app), 0, null);
}
