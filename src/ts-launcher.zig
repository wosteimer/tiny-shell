const std = @import("std");
const c = @import("c.zig");
const g = @import("g-utils.zig");
const TsLauncherWindow = @import("ts-launcher-window.zig").TsLauncherWindow;
const TS_LAUNCHER_WINDOW = @import("ts-launcher-window.zig").TS_LAUNCHER_WINDOW;

const VERSION = "0.1.0";
const APP_ID = "com.github.wosteimer.tiny.launcher";
const DBUS_OBJECT_PATH = "/com/github/wosteimer/tiny/launcher";

var interface_info: ?*c.GDBusNodeInfo = null;
const interface_vtable = c.GDBusInterfaceVTable{
    .method_call = @ptrCast(&onMethodCall),
};

const Args = enum {
    help,
    h,
    version,
    v,
    silent,
    s,
};

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
                if (isRunning()) {
                    return;
                }
                run(true);
                return;
            },
        }
    }
    if (isRunning()) {
        showWindow();
        return;
    }
    run(false);
}

fn run(is_silent: bool) void {
    const app = c.adw_application_new(
        APP_ID,
        c.G_APPLICATION_DEFAULT_FLAGS,
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

// TODO: Error handling for all funcions below

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
    const window: *c.GtkWindow = @ptrCast(TsLauncherWindow.new());
    c.gtk_window_set_application(window, app);
    c.gtk_layer_init_for_window(window);
    c.gtk_layer_set_layer(window, c.GTK_LAYER_SHELL_LAYER_TOP);
    c.gtk_layer_set_keyboard_mode(
        window,
        c.GTK_LAYER_SHELL_KEYBOARD_MODE_EXCLUSIVE,
    );
    if (!is_silent.*) {
        c.gtk_window_present(window);
    }
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
    const xml = (
        \\<node>
        \\  <interface name="{s}">
        \\      <method name="ShowWindow"/>
        \\  </interface>
        \\</node>
    );
    var buf = std.mem.zeroes([255]u8);
    _ = std.fmt.bufPrint(&buf, xml, .{APP_ID}) catch {
        @panic("error trying to generate dbus node info");
    };
    if (interface_info == null) {
        interface_info = c.g_dbus_node_info_new_for_xml(&buf, null);
    }
    _ = c.g_dbus_connection_register_object(
        connection,
        DBUS_OBJECT_PATH,
        interface_info.?.*.interfaces[0],
        &interface_vtable,
        user_data,
        null,
        null,
    );
}

fn onMethodCall(
    _: *c.GDBusConnection,
    _: [*:0]const u8,
    _: [*:0]const u8,
    _: [*:0]const u8,
    method_name: [*:0]const u8,
    _: *c.GVariant,
    invocation: ?*c.GDBusMethodInvocation,
    user_data: c.gpointer,
) callconv(.C) void {
    if (std.mem.eql(u8, std.mem.span(method_name), "ShowWindow")) {
        const window = TS_LAUNCHER_WINDOW(user_data);
        window.show();
    }
    c.g_dbus_method_invocation_return_value(invocation, null);
}

fn isRunning() bool {
    const bus = c.g_bus_get_sync(c.G_BUS_TYPE_SESSION, null, null);
    if (bus == null) return false;
    defer c.g_object_unref(g.G_OBJECT(bus));
    const result = c.g_dbus_connection_call_sync(
        bus,
        "org.freedesktop.DBus",
        "/org/freedesktop/DBus",
        "org.freedesktop.DBus",
        "NameHasOwner",
        c.g_variant_new("(s)", APP_ID),
        c.G_VARIANT_TYPE("(b)"),
        c.G_DBUS_CALL_FLAGS_NONE,
        -1,
        null,
        null,
    );
    if (result == null) return false;
    var is_running: i32 = 0;
    c.g_variant_get(result, "(b)", &is_running);
    defer c.g_variant_unref(result);
    return is_running != 0;
}

fn showWindow() void {
    const bus = c.g_bus_get_sync(c.G_BUS_TYPE_SESSION, null, null);
    if (bus == null) return;
    defer c.g_object_unref(g.G_OBJECT(bus));
    const result = c.g_dbus_connection_call_sync(
        bus,
        APP_ID,
        DBUS_OBJECT_PATH,
        APP_ID,
        "ShowWindow",
        null,
        null,
        c.G_DBUS_CALL_FLAGS_NONE,
        -1,
        null,
        null,
    );
    if (result == null) return;
    defer c.g_variant_unref(result);
}
