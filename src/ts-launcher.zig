const std = @import("std");
const c = @import("c.zig");
const g = @import("g-utils.zig");
const TsLauncherWindow = @import("ts-launcher-window.zig").TsLauncherWindow;
const TS_LAUNCHER_WINDOW = @import("ts-launcher-window.zig").TS_LAUNCHER_WINDOW;

const VERSION = "0.1.0";
const APP_ID = "com.github.wosteimer.tiny.launcher";

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

var window: ?*c.GtkWindow = null;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a_allocator = arena.allocator();
    var args = std.ArrayList([*:0]u8).init(a_allocator);
    var iter = std.process.args();
    while (iter.next()) |arg| {
        try args.append(try a_allocator.dupeZ(u8, arg));
    }
    const app = c.adw_application_new(
        APP_ID,
        c.G_APPLICATION_HANDLES_COMMAND_LINE,
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
    _ = c.g_signal_connect_data(
        @ptrCast(app),
        "command-line",
        @ptrCast(&commandLine),
        null,
        null,
        c.G_TYPE_FLAG_FINAL,
    );
    const options = [3]c.GOptionEntry{
        c.GOptionEntry{
            .long_name = "version",
            .short_name = 'v',
            .flags = c.G_OPTION_FLAG_NONE,
            .arg = c.G_OPTION_ARG_NONE,
            .arg_data = null,
            .description = "Print version",
            .arg_description = "",
        },
        c.GOptionEntry{
            .long_name = "silent",
            .short_name = 's',
            .flags = c.G_OPTION_FLAG_NONE,
            .arg = c.G_OPTION_ARG_NONE,
            .arg_data = null,
            .description = "Run the program in the background",
            .arg_description = "",
        },
        undefined,
    };
    c.g_application_add_main_option_entries(
        g.G_APPLICATION(app),
        &options,
    );
    _ = c.g_application_run(
        g.G_APPLICATION(app),
        @intCast(args.items.len),
        @ptrCast(args.items.ptr),
    );
}

fn activate(app: *c.GtkApplication, _: *c.gpointer) callconv(.C) void {
    if (window == null) {
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
        window = @ptrCast(TsLauncherWindow.new());
        c.gtk_window_set_application(window, app);
        c.gtk_layer_init_for_window(window);
        c.gtk_layer_set_layer(window, c.GTK_LAYER_SHELL_LAYER_TOP);
        c.gtk_layer_set_keyboard_mode(
            window,
            c.GTK_LAYER_SHELL_KEYBOARD_MODE_EXCLUSIVE,
        );
    }
}

fn commandLine(
    app: *c.GApplication,
    cmdline: *c.GApplicationCommandLine,
) callconv(.C) i32 {
    const options = c.g_application_command_line_get_options_dict(cmdline);
    const is_silent = c.g_variant_dict_contains(options, "silent") != 0;
    const show_version = c.g_variant_dict_contains(options, "version") != 0;
    if (show_version) {
        c.g_application_command_line_print(
            cmdline,
            "tiny launcher " ++ VERSION ++ "\n",
        );
        return 0;
    }
    c.g_application_activate(app);
    const is_visible = c.gtk_widget_is_visible(g.GTK_WIDGET(window)) == 0;
    if (is_visible and !is_silent) {
        TS_LAUNCHER_WINDOW(window).show();
    }
    return 0;
}
