const std = @import("std");
const c = @import("c.zig");
const g = @import("g-utils.zig");
const TsLauncherWindow = @import("ts-launcher-window.zig").TsLauncherWindow;
const TS_LAUNCHER_WINDOW = @import("ts-launcher-window.zig").TS_LAUNCHER_WINDOW;

const VERSION = "0.1.0";
const APP_ID = "com.github.wosteimer.tiny.launcher";

const Args = enum {
    help,
    h,
    version,
    v,
    silent,
    s,
};

var window: ?*c.GtkWindow = null;

pub fn main() !void {
    var args = std.process.args();
    _ = args.skip();
    if (args.next()) |arg| {
        var parsed: Args = .help;
        if (std.mem.startsWith(u8, arg, "--") and arg.len > 3) {
            if (std.meta.stringToEnum(Args, arg[2..])) |v| {
                parsed = v;
            } else {
                std.log.warn("invalid argument", .{});
            }
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len == 2) {
            if (std.meta.stringToEnum(Args, arg[1..])) |v| {
                parsed = v;
            } else {
                std.log.warn("invalid argument", .{});
            }
        } else {
            std.log.warn("invalid argument", .{});
        }
        const out = std.io.getStdOut().writer();
        switch (parsed) {
            .help, .h => {
                try out.print(
                    \\Usage: ts-launcher [Option]
                    \\Options:
                    \\    -h, --help      Print this message
                    \\    -v, --version   Print version
                    \\    -s, --silent    run the program in the background 
                    \\
                , .{});
                return;
            },
            .version, .v => {
                try out.print("tiny launcher v{s}\n", .{VERSION});
                return;
            },
            .silent, .s => {
                run(true);
                return;
            },
        }
    }
    run(false);
}

fn run(is_silent: bool) void {
    const app = c.adw_application_new(
        APP_ID,
        c.G_APPLICATION_FLAGS_NONE,
    );
    defer c.g_object_unref(app);
    var _is_silent = is_silent;
    _ = c.g_signal_connect_data(
        @ptrCast(app),
        "activate",
        @ptrCast(&activate),
        @ptrCast(&_is_silent),
        null,
        c.G_TYPE_FLAG_FINAL,
    );
    _ = c.g_application_run(@ptrCast(app), 0, null);
}

fn activate(app: *c.GtkApplication, is_silent: *bool) callconv(.C) void {
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
    if (window == null) {
        window = @ptrCast(TsLauncherWindow.new());
        c.gtk_window_set_application(window, app);
        c.gtk_layer_init_for_window(window);
        c.gtk_layer_set_layer(window, c.GTK_LAYER_SHELL_LAYER_TOP);
        c.gtk_layer_set_keyboard_mode(
            window,
            c.GTK_LAYER_SHELL_KEYBOARD_MODE_EXCLUSIVE,
        );
    } else {
        TS_LAUNCHER_WINDOW(window).reset();
    }
    if (!is_silent.*) {
        c.gtk_window_present(window);
    }
}
