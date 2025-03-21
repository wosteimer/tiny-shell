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
    makeActions(@ptrCast(app));
    defer c.g_object_unref(app);
    _ = c.g_signal_connect_data(
        @ptrCast(app),
        "activate",
        @ptrCast(&activate),
        null,
        null,
        c.G_CONNECT_DEFAULT,
    );
    _ = c.g_signal_connect_data(
        @ptrCast(app),
        "command-line",
        @ptrCast(&commandLine),
        null,
        null,
        c.G_CONNECT_DEFAULT,
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

fn makeActions(app: *c.GApplication) void {
    const launch = c.g_simple_action_new("launch", c.G_VARIANT_TYPE("s"));
    _ = c.g_signal_connect_data(
        g.G_OBJECT(launch),
        "activate",
        @ptrCast(&onLaunch),
        null,
        null,
        c.G_CONNECT_DEFAULT,
    );
    const launch_action = c.g_simple_action_new("launch-action", c.G_VARIANT_TYPE("s"));
    _ = c.g_signal_connect_data(
        g.G_OBJECT(launch_action),
        "activate",
        @ptrCast(&onLaunchAction),
        null,
        null,
        c.G_CONNECT_DEFAULT,
    );
    const hide = c.g_simple_action_new("hide", c.G_VARIANT_TYPE("s"));
    _ = c.g_signal_connect_data(
        g.G_OBJECT(hide),
        "activate",
        @ptrCast(&onHide),
        null,
        null,
        c.G_CONNECT_DEFAULT,
    );
    c.g_action_map_add_action(@ptrCast(app), @ptrCast(launch));
    c.g_action_map_add_action(@ptrCast(app), @ptrCast(launch_action));
    c.g_action_map_add_action(@ptrCast(app), @ptrCast(hide));
}

fn onLaunch(_: *c.GSimpleAction, parameter: *c.GVariant, _: c.gpointer) void {
    const app_id = c.g_variant_get_string(parameter, null);
    const desktop_app_info = c.g_desktop_app_info_new(app_id);
    const app_info = g.G_APP_INFO(desktop_app_info);
    defer c.g_object_unref(@ptrCast(desktop_app_info));
    _ = c.g_app_info_launch(app_info, null, null, null);
    c.gtk_widget_hide(g.GTK_WIDGET(window));
}

fn onLaunchAction(_: *c.GSimpleAction, parameter: *c.GVariant, _: c.gpointer) void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a_allocator = arena.allocator();
    const s_param = c.g_variant_get_string(parameter, null);
    var it = std.mem.split(u8, std.mem.span(s_param), "::");
    const app_id = a_allocator.dupeZ(u8, it.next().?) catch {
        @panic("out of memory");
    };
    const action = a_allocator.dupeZ(u8, it.next().?) catch {
        @panic("out of memory");
    };
    const app_info = c.g_desktop_app_info_new(app_id);
    defer c.g_object_unref(app_info);
    c.g_desktop_app_info_launch_action(
        app_info,
        a_allocator.dupeZ(u8, action) catch {
            @panic("out of memory");
        },
        null,
    );
    c.gtk_widget_hide(g.GTK_WIDGET(window));
}

fn onHide(_: *c.GSimpleAction, parameter: *c.GVariant, _: c.gpointer) void {
    const s_param = c.g_variant_get_string(parameter, null);
    std.debug.print("hide: {s}\n", .{s_param});
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
