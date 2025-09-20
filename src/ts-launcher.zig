const std = @import("std");
const adw = @import("adw");
const gtk = @import("gtk");
const gdk = @import("gdk");
const glib = @import("glib");
const gio = @import("gio");
const g = @import("gobject");
const intl = @import("libintl");

const TsLauncherWindow = @import("ts-launcher-window.zig").TsLauncherWindow;
const GApplicationProvider = @import("g_application_provider.zig");
const TsModel = @import("ts-model.zig").TsModel;

const VERSION = "0.1.0";
const APP_ID = "com.github.wosteimer.tiny-shell";

const allocator = std.heap.page_allocator;

var window: ?*TsLauncherWindow = null;

pub fn main() !void {
    intl.setTextDomain(APP_ID);
    var env = try std.process.getEnvMap(allocator);
    if (env.get("TS_DEBUG_LOCALE_DIR")) |dir| {
        intl.bindTextDomain(APP_ID, @ptrCast(dir));
    }
    env.deinit();
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a_allocator = arena.allocator();
    var args = std.ArrayList([*:0]u8){};
    var iter = std.process.args();
    while (iter.next()) |arg| {
        try args.append(allocator, try a_allocator.dupeZ(u8, arg));
    }
    const app = adw.Application.new(APP_ID, .{ .handles_command_line = true });
    defer g.Object.unref(app.as(g.Object));
    _ = g.signalConnectData(app.as(g.Object), "activate", @ptrCast(&activate), null, null, .{});
    _ = g.signalConnectData(app.as(g.Object), "command-line", @ptrCast(&commandLine), null, null, .{});
    const options = [_]glib.OptionEntry{
        glib.OptionEntry{
            .f_long_name = "version",
            .f_short_name = 'v',
            .f_flags = 0,
            .f_arg = .none,
            .f_arg_data = null,
            .f_description = intl.gettext("Print program version"),
            .f_arg_description = null,
        },
        glib.OptionEntry{
            .f_long_name = "silent",
            .f_short_name = 's',
            .f_flags = 0,
            .f_arg = .none,
            .f_arg_data = null,
            .f_description = intl.gettext("Run the program in the background"),
            .f_arg_description = null,
        },
        std.mem.zeroes(glib.OptionEntry),
    };
    gio.Application.addMainOptionEntries(app.as(gio.Application), &options);
    _ = gio.Application.run(app.as(gio.Application), @intCast(args.items.len), @ptrCast(args.items.ptr));
}

fn onColorSchemeChanged(
    settings: *gtk.Settings,
    _: ?*g.ParamSpec,
    launcher: *TsLauncherWindow,
) callconv(.c) void {
    var value = std.mem.zeroes(g.Value);
    defer value.unset();
    g.Object.getProperty(settings.as(g.Object), "gtk-application-prefer-dark-theme", &value);
    const prefer_dark: bool = value.getBoolean() != 0;
    if (prefer_dark) {
        gtk.Widget.addCssClass(launcher.as(gtk.Widget), "dark-theme");
        return;
    }
    gtk.Widget.removeCssClass(launcher.as(gtk.Widget), "dark-theme");
}

fn activate(app: *gtk.Application, _: ?*anyopaque) callconv(.c) void {
    if (window == null) {
        window = TsLauncherWindow.new();
        gtk.Window.setApplication(window.?.as(gtk.Window), app);
        const css_provider = gtk.CssProvider.new();
        const display = gdk.Display.getDefault().?;
        const css: [*:0]const u8 = @embedFile("data/css/style.css");
        css_provider.loadFromString(css);
        gtk.StyleContext.addProviderForDisplay(
            display,
            @ptrCast(css_provider),
            gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        );
        const settings = gtk.Settings.getDefault();
        onColorSchemeChanged(settings.?, null, window.?);
        _ = g.signalConnectData(
            settings.?.as(g.Object),
            "notify::gtk-application-prefer-dark-theme",
            @ptrCast(&onColorSchemeChanged),
            @ptrCast(window),
            null,
            .{},
        );
    }
}

fn commandLine(app: *adw.Application, cmdline: *gio.ApplicationCommandLine) callconv(.c) i32 {
    const options = cmdline.getOptionsDict();
    const is_silent = options.contains("silent");
    const show_version = options.contains("version");
    if (show_version != 0) {
        const version = std.fmt.allocPrintSentinel(allocator, "tiny launcher {s} \n", .{VERSION}, 0) catch {
            unreachable;
        };
        defer allocator.free(version);
        cmdline.print(version);
        return 0;
    }
    gio.Application.activate(app.as(gio.Application));
    if (gtk.Widget.getVisible(window.?.as(gtk.Widget)) != 1 and is_silent == 0) {
        window.?.show();
    }
    return 0;
}
