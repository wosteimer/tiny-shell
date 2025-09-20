const std = @import("std");
const Application = @import("application_provider.zig").Application;
const TsModelItem = @import("ts-model.zig").TsModelItem;
const gtk = @import("gtk");
const glib = @import("glib");
const gio = @import("gio");
const g = @import("gobject");
const gdk = @import("gdk");
const intl = @import("libintl");

pub const TsListItem = extern struct {
    parent: Parent,

    const Self = @This();
    pub const Parent = gtk.ListBoxRow;

    const Private = struct {
        name: *gtk.Label,
        icon: *gtk.Image,
        popover: *gtk.PopoverMenu,

        var offset: c_int = 0;
    };

    pub const Class = extern struct {
        parent_class: Parent.Class,

        pub const Instance = TsListItem;
        var parent: *Parent.Class = undefined;

        pub fn as(class: *Class, comptime T: type) *T {
            return g.ext.as(T, class);
        }

        pub fn init(class: *Class) callconv(.c) void {
            g.Object.virtual_methods.dispose.implement(class, &dispose);
            g.Object.virtual_methods.finalize.implement(class, &finalize);
            const template: []const u8 = @embedFile("data/ui/ts-list-item.ui");
            const bytes = glib.Bytes.new(template.ptr, template.len);
            defer glib.Bytes.unref(bytes);
            gtk.WidgetClass.setTemplate(
                class.as(gtk.WidgetClass),
                bytes,
            );
            inline for (@typeInfo(Private).@"struct".fields) |field| {
                const name = field.name;
                class.bindTemplateChildPrivate(name, .{});
            }
            inline for (@typeInfo(Self).@"struct".decls) |decl| {
                const name = decl.name;
                if (!std.mem.startsWith(u8, name, "on")) comptime continue;
                if (!std.ascii.isUpper(name[2])) comptime continue;
                gtk.WidgetClass.bindTemplateCallbackFull(
                    class.as(gtk.WidgetClass),
                    name,
                    @ptrCast(&@field(Self, name)),
                );
            }
        }

        fn bindTemplateChildPrivate(
            class: *Class,
            comptime name: [:0]const u8,
            comptime options: gtk.ext.BindTemplateChildOptions,
        ) void {
            gtk.ext.impl_helpers.bindTemplateChildPrivate(
                class,
                name,
                Private,
                Private.offset,
                options,
            );
        }
    };

    pub const getGObjectType = g.ext.defineClass(TsListItem, .{
        .classInit = &Class.init,
        .instanceInit = &init,
        .parent_class = &Class.parent,
        .private = .{ .Type = Private, .offset = &Private.offset },
    });

    fn dispose(self: *Self) callconv(.c) void {
        gtk.Widget.disposeTemplate(self.as(gtk.Widget), getGObjectType());
        g.Object.virtual_methods.dispose.call(Class.parent, self.as(Parent));
    }

    fn finalize(self: *Self) callconv(.c) void {
        g.Object.virtual_methods.finalize.call(Class.parent, self.as(Parent));
    }

    fn init(self: *Self, _: *Class) callconv(.c) void {
        gtk.Widget.initTemplate(self.as(gtk.Widget));
    }

    pub fn as(self: *Self, comptime T: type) *T {
        return g.ext.as(T, self);
    }

    fn private(self: *Self) *Private {
        return g.ext.impl_helpers.getPrivate(self, Private, Private.offset);
    }

    pub fn onRightClick(
        self: *Self,
        _: *gtk.GestureClick,
        _: i32,
        _: f64,
        _: f64,
        _: ?*anyopaque,
    ) callconv(.c) void {
        self.openMenu();
    }

    pub fn openMenu(self: *Self) void {
        gtk.Popover.popup(self.private().popover.as(gtk.Popover));
    }

    pub fn new(child_allocator: std.mem.Allocator, item: *TsModelItem) !*Self {
        var arena = std.heap.ArenaAllocator.init(child_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();
        const self = g.ext.newInstance(TsListItem, .{});
        const app = item.getApplication();
        const display = gdk.Display.getDefault().?;
        const icon_theme = gtk.IconTheme.getForDisplay(display);
        const icon = icon_theme.lookupIcon(
            try allocator.dupeZ(u8, app.icon orelse "image-missing"),
            null,
            32,
            1,
            .none,
            .{},
        );
        defer icon.unref();
        self.private().name.setLabel(try allocator.dupeZ(u8, app.display_name));
        gtk.Widget.setTooltipText(
            self.private().name.as(gtk.Widget),
            try allocator.dupeZ(u8, app.display_name),
        );
        self.private().icon.setFromPaintable(icon.as(gdk.Paintable));
        const menu = try createMenu(allocator, app);
        self.private().popover.setMenuModel(menu);
        return self;
    }

    fn createMenu(allocator: std.mem.Allocator, app: *Application) !*gio.MenuModel {
        const menu = gio.Menu.new();
        const section_a = gio.Menu.new();
        const section_b = gio.Menu.new();
        for (app.actions) |action| {
            const cmd = try std.fmt.allocPrintSentinel(
                allocator,
                "win.launch-action::{s}::{s}",
                .{ app.id, action.key },
                0,
            );
            section_b.append(try allocator.dupeZ(u8, action.name), cmd);
        }
        const cmd = try std.fmt.allocPrintSentinel(
            allocator,
            "win.launch::{s}",
            .{app.id},
            0,
        );
        section_a.append(intl.gettext("Open"), cmd);
        menu.appendSection(null, section_a.as(gio.MenuModel));
        menu.appendSection(null, section_b.as(gio.MenuModel));
        return menu.as(gio.MenuModel);
    }
};
