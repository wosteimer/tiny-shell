const g = @import("gobject");
const std = @import("std");
const gio = @import("gio");
const adw = @import("adw");
const gtk = @import("gtk");
const gdk = @import("gdk");
const glib = @import("glib");
const intl = @import("libintl");

const TsLauncherWindow = @import("ts-launcher-window.zig").TsLauncherWindow;
const ApplicationProvider = @import("application_provider.zig");

pub const TsApplication = extern struct {
    parent: Parent,

    const Self = @This();
    pub const Parent = adw.Application;

    const Private = struct {
        activated: bool = false,
        allocator: std.mem.Allocator,
        application_provider: *ApplicationProvider,
        launcher: *TsLauncherWindow,
        css: *gtk.CssProvider,

        var offset: c_int = 0;
    };

    pub const Class = extern struct {
        parent_class: Parent.Class,

        pub const Instance = TsApplication;
        var parent: *Parent.Class = undefined;

        pub fn as(class: *Class, comptime T: type) *T {
            return g.ext.as(T, class);
        }

        pub fn init(class: *Class) callconv(.c) void {
            g.Object.virtual_methods.dispose.implement(class, &dispose);
            g.Object.virtual_methods.finalize.implement(class, &finalize);
            gio.Application.virtual_methods.activate.implement(class, &onActivate);
            gio.Application.virtual_methods.command_line.implement(class, &onCommandLine);
        }
    };

    pub const getGObjectType = g.ext.defineClass(TsApplication, .{
        .classInit = &Class.init,
        .instanceInit = &init,
        .parent_class = &Class.parent,
        .private = .{ .Type = Private, .offset = &Private.offset },
    });

    fn init(self: *Self, _: *Class) callconv(.c) void {
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
        gio.Application.addMainOptionEntries(self.as(gio.Application), &options);
    }

    fn dispose(self: *Self) callconv(.c) void {
        g.Object.virtual_methods.dispose.call(Class.parent, self.as(Parent));
    }

    fn finalize(self: *Self) callconv(.c) void {
        g.Object.unref(self.private().launcher.as(g.Object));
        g.Object.virtual_methods.finalize.call(Class.parent, self.as(Parent));
    }

    fn onColorSchemeChanged(
        self: *Self,
        _: ?*g.ParamSpec,
        settings: *gtk.Settings,
    ) callconv(.c) void {
        var value = std.mem.zeroes(g.Value);
        defer value.unset();
        g.Object.getProperty(settings.as(g.Object), "gtk-application-prefer-dark-theme", &value);
        const prefer_dark: bool = value.getBoolean() != 0;
        var theme = std.mem.zeroes(g.Value);
        _ = g.Value.init(&theme, g.ext.types.@"enum");
        if (prefer_dark) {
            theme.setEnum(@intFromEnum(gtk.InterfaceColorScheme.dark));
        } else {
            theme.setEnum(@intFromEnum(gtk.InterfaceColorScheme.light));
        }
        g.Object.setProperty(self.private().css.as(g.Object), "prefers-color-scheme", &theme);
    }

    fn onActivate(self: *Self) callconv(.c) void {
        self.private().launcher = TsLauncherWindow.new(
            self.private().allocator,
            self.private().application_provider,
        );
        gtk.Window.setApplication(self.private().launcher.as(gtk.Window), self.as(gtk.Application));
        const css_provider = gtk.CssProvider.new();
        self.private().css = css_provider;
        const display = gtk.Widget.getDisplay(self.private().launcher.as(gtk.Widget));
        const css: [*:0]const u8 = @embedFile("data/css/style.css");
        css_provider.loadFromString(css);
        gtk.StyleContext.addProviderForDisplay(
            display,
            @ptrCast(css_provider),
            gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        );
        const settings = gtk.Settings.getDefault();
        self.onColorSchemeChanged(null, settings.?);
        _ = g.signalConnectData(
            settings.?.as(g.Object),
            "notify::gtk-application-prefer-dark-theme",
            @ptrCast(&onColorSchemeChanged),
            @ptrCast(self),
            null,
            .{ .swapped = true },
        );
        self.private().activated = true;
    }

    fn onCommandLine(self: *Self, cmdline: *gio.ApplicationCommandLine) callconv(.c) i32 {
        const options = cmdline.getOptionsDict();
        const is_silent = options.contains("silent");
        const show_version = options.contains("version");
        if (show_version != 0) {
            const version = std.fmt.allocPrintSentinel(
                self.private().allocator,
                "tiny shell {s} \n",
                .{gio.Application.getVersion(self.as(gio.Application)) orelse ""},
                0,
            ) catch unreachable;
            defer self.private().allocator.free(version);
            cmdline.print(version);
            return 0;
        }
        if (!self.private().activated) {
            gio.Application.activate(self.as(gio.Application));
        }
        if (gtk.Widget.getVisible(self.private().launcher.as(gtk.Widget)) != 1 and is_silent == 0) {
            self.private().launcher.show();
        }
        return 0;
    }

    fn private(self: *Self) *Private {
        return g.ext.impl_helpers.getPrivate(self, Private, Private.offset);
    }

    pub fn as(self: *Self, comptime T: type) *T {
        return g.ext.as(T, self);
    }

    pub fn new(
        allocator: std.mem.Allocator,
        application_provider: *ApplicationProvider,
        application_id: [:0]const u8,
        version: [:0]const u8,
    ) *Self {
        const self = g.ext.newInstance(Self, .{
            .application_id = application_id,
            .flags = gio.ApplicationFlags{ .handles_command_line = true },
        });
        gio.Application.setVersion(self.as(gio.Application), version);
        self.private().allocator = allocator;
        self.private().application_provider = application_provider;
        return self;
    }

    pub fn ref(self: *Self) *Self {
        return g.Object.ref(self.as(g.Object)).as(Self);
    }

    pub fn unref(self: *Self) void {
        g.Object.unref(self.as(g.Object));
    }
};
