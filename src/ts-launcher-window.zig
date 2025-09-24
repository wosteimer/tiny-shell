const std = @import("std");
const adw = @import("adw");
const g = @import("gobject");
const gio = @import("gio");
const glib = @import("glib");
const gtk = @import("gtk");
const gdk = @import("gdk");
const graphene = @import("graphene");

const layer = @import("gtk-layer-shell.zig");
const Application = @import("application_provider.zig").Application;
const ApplicationProvider = @import("application_provider.zig").ApplicationProvider;
const TsListItem = @import("ts-list-item.zig").TsListItem;
const TsModel = @import("ts-model.zig").TsModel;
const TsModelItem = @import("ts-model.zig").TsModelItem;

pub const MoveSelectionDirection = enum(i32) {
    previous = -1,
    next = 1,
};

pub const TsLauncherWindow = extern struct {
    parent: Parent,

    pub const Parent = adw.ApplicationWindow;

    const Self = @This();

    const Private = struct {
        model: *TsModel,
        allocator: std.mem.Allocator,
        application_provider: *ApplicationProvider,
        main: *gtk.Box,
        search_entry: *gtk.SearchEntry,
        list_box: *gtk.ListBox,
        scrolled_window: *gtk.ScrolledWindow,
        stack: *gtk.Stack,

        pub var offset: c_int = 0;
    };

    pub const Class = extern struct {
        parent_class: Parent.Class,

        pub const Instance = TsLauncherWindow;
        var parent: *Parent.Class = undefined;

        pub fn as(class: *Class, comptime T: type) *T {
            return g.ext.as(T, class);
        }

        fn init(class: *Class) callconv(.c) void {
            g.Object.virtual_methods.dispose.implement(class, &dispose);
            g.Object.virtual_methods.finalize.implement(class, &finalize);
            const template: []const u8 = @embedFile("data/ui/ts-launcher-window.ui");
            const bytes = glib.Bytes.new(template.ptr, template.len);
            defer glib.Bytes.unref(bytes);
            gtk.WidgetClass.setTemplate(class.as(gtk.WidgetClass), bytes);
            inline for (@typeInfo(Private).@"struct".fields) |field| {
                const name = field.name;
                comptime if (std.mem.eql(u8, name, "model")) continue;
                comptime if (std.mem.eql(u8, name, "allocator")) continue;
                comptime if (std.mem.eql(u8, name, "application_provider")) continue;
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
            gtk.ext.impl_helpers.bindTemplateChildPrivate(class, name, Private, Private.offset, options);
        }
    };

    pub const getGObjectType = g.ext.defineClass(TsLauncherWindow, .{
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
        self.private().model.unref();
        g.Object.virtual_methods.finalize.call(Class.parent, self.as(Parent));
    }

    fn init(self: *Self, _: *Class) callconv(.c) void {
        gtk.Widget.initTemplate(self.as(gtk.Widget));
        layer.initForWindow(self.as(gtk.Window));
        layer.setLayer(self.as(gtk.Window), .top);
        layer.setAnchor(self.as(gtk.Window), .top, true);
        layer.setAnchor(self.as(gtk.Window), .bottom, true);
        layer.setAnchor(self.as(gtk.Window), .left, true);
        layer.setAnchor(self.as(gtk.Window), .right, true);
        layer.setKeyboardMode(self.as(gtk.Window), .exclusive);
        const shortcut_controller = gtk.ShortcutController.new();
        const text = gtk.Editable.getDelegate(self.private().search_entry.as(gtk.Editable)).?;
        gtk.Widget.addController(text.as(gtk.Widget), shortcut_controller.as(gtk.EventController));
        const shortcuts = .{
            .{ "Escape", &closeShortcut },
            .{ "<Control>y", &confirmShortcut },
            .{ "<Control>n", &nextShortcut },
            .{ "<Control>p", &previousShortcut },
            .{ "<Control>w", &deleteWordShortcut },
        };
        inline for (shortcuts) |shortcut_data| {
            shortcut_controller.addShortcut(gtk.Shortcut.new(
                gtk.ShortcutTrigger.parseString(shortcut_data[0]),
                gtk.CallbackAction.new(@ptrCast(shortcut_data[1]), @ptrCast(self), null).as(gtk.ShortcutAction),
            ));
        }
        const launch = gio.SimpleAction.new("launch", glib.VariantType.new("s"));
        _ = g.signalConnectData(launch.as(g.Object), "activate", @ptrCast(&onLaunch), @ptrCast(self), null, .{});
        const launch_action = gio.SimpleAction.new("launch-action", glib.VariantType.new("s"));
        _ = g.signalConnectData(
            launch_action.as(g.Object),
            "activate",
            @ptrCast(&onLaunchAction),
            @ptrCast(self),
            null,
            .{},
        );
        gio.ActionMap.addAction(self.as(gio.ActionMap), launch.as(gio.Action));
        gio.ActionMap.addAction(self.as(gio.ActionMap), launch_action.as(gio.Action));
    }

    pub fn as(self: *Self, comptime T: type) *T {
        return g.ext.as(T, self);
    }

    fn private(self: *Self) *Private {
        return g.ext.impl_helpers.getPrivate(self, Private, Private.offset);
    }

    fn deleteWordShortcut(_: *gtk.Widget, _: *glib.Variant, window: *Self) callconv(.c) bool {
        const text = gtk.Editable.getDelegate(window.private().search_entry.as(gtk.Editable)).?;
        var start: c_int = 0;
        const end: c_int = text.getPosition();
        const buffer = text.getText();
        var i: i32 = @intCast(end - 1);
        while (i >= 0 and buffer[@intCast(i)] == ' ') {
            i -= 1;
        }
        while (i >= 0) {
            if (buffer[@intCast(i)] == ' ') {
                start = i;
                break;
            }
            i -= 1;
        }
        text.deleteText(start, end);
        return true;
    }

    fn confirmShortcut(widget: *gtk.Widget, _: *glib.Variant, window: *Self) callconv(.c) bool {
        _ = onActivated(window, widget.as(g.Object));
        return true;
    }

    fn closeShortcut(_: *gtk.Widget, _: *glib.Variant, window: *Self) callconv(.c) bool {
        window.hide();
        return true;
    }

    fn nextShortcut(_: *gtk.Widget, _: *glib.Variant, window: *Self) callconv(.c) bool {
        window.moveSelection(.next);
        return true;
    }

    fn previousShortcut(_: *gtk.Widget, _: *glib.Variant, window: *Self) callconv(.c) bool {
        window.moveSelection(.previous);
        return true;
    }

    pub fn moveSelection(self: *Self, direction: MoveSelectionDirection) void {
        const n_rows = gio.ListModel.getNItems(self.private().model.as(gio.ListModel));
        if (n_rows == 0) {
            return;
        }
        if (self.private().list_box.getSelectedRow()) |row| {
            const index = row.getIndex();
            const next = self.private().list_box.getRowAtIndex(
                wrap(index + @intFromEnum(direction), 0, @intCast(n_rows)),
            );
            self.private().list_box.selectRow(next);
            self.scrollToSelection();
        }
    }

    fn wrap(value: i32, min_value: i32, max_value: i32) i32 {
        const range_size = max_value - min_value;
        return @mod((value - min_value), range_size) + min_value;
    }

    pub fn scrollToSelection(self: *Self) void {
        if (self.private().list_box.getSelectedRow()) |row| {
            var rect = std.mem.zeroes(graphene.Rect);
            _ = gtk.Widget.computeBounds(
                row.as(gtk.Widget),
                self.private().scrolled_window.as(gtk.Widget),
                &rect,
            );
            const top = rect.f_origin.f_y;
            const bottom = top + rect.f_size.f_height;
            const adjustment = self.private().scrolled_window.getVadjustment();
            const page_size = adjustment.getPageSize();
            const current = adjustment.getValue();
            if (bottom > page_size) {
                adjustment.setValue(bottom - page_size + current);
            } else if (top < 0) {
                adjustment.setValue(current + top);
            }
        }
    }

    pub fn onActivated(self: *Self, _: *g.Object) callconv(.c) bool {
        if (self.private().list_box.getSelectedRow()) |row| {
            const pos = row.getIndex();
            const item: *TsModelItem = @ptrCast(@alignCast(gio.ListModel.getItem(
                self.private().model.as(gio.ListModel),
                @intCast(pos),
            ).?));
            defer item.unref();
            const id = self.private().allocator.dupeZ(u8, item.getApplication().id) catch unreachable;
            defer self.private().allocator.free(id);
            const variant = glib.Variant.newString(id);
            _ = gtk.Widget.activateActionVariant(self.as(gtk.Widget), "win.launch", variant);
        }
        return true;
    }

    pub fn onKeyPressed(
        self: *Self,
        _: u32,
        _: u32,
        _: gdk.ModifierType,
        controller: *gtk.EventControllerKey,
    ) callconv(.c) bool {
        const text = gtk.Editable.getDelegate(self.private().search_entry.as(gtk.Editable)).?;
        _ = gtk.Text.grabFocusWithoutSelecting(@ptrCast(@alignCast(text)));
        _ = controller.forward(text.as(gtk.Widget));
        return gdk.EVENT_STOP;
    }

    pub fn onSearchChanged(self: *Self, entry: *gtk.SearchEntry) callconv(.c) bool {
        const filter = std.mem.span(gtk.Editable.getText(entry.as(gtk.Editable)));
        self.private().model.setFilter(filter);
        if (gio.ListModel.getNItems(self.private().model.as(gio.ListModel)) == 0) {
            self.private().stack.setVisibleChildName("empty");
            return false;
        }
        self.private().stack.setVisibleChildName("list");
        const row = self.private().list_box.getRowAtIndex(0);
        self.private().list_box.selectRow(row);
        const adjustment = self.private().scrolled_window.getVadjustment();
        adjustment.setValue(0);
        return false;
    }

    pub fn onMouseReleased(self: *Self, _: i32, x: f64, y: f64, _: *gtk.GestureClick) callconv(.c) bool {
        var rect = std.mem.zeroes(graphene.Rect);
        _ = gtk.Widget.computeBounds(self.private().main.as(gtk.Widget), self.as(gtk.Widget), &rect);
        if (!rect.containsPoint(&graphene.Point{ .f_x = @floatCast(x), .f_y = @floatCast(y) })) {
            self.hide();
        }
        return false;
    }

    fn onLaunch(_: *gio.SimpleAction, parameter: *glib.Variant, window: *Self) callconv(.c) void {
        const app_id = parameter.getString(null);
        window.private().application_provider.launch(std.mem.span(app_id)) catch unreachable;
        window.hide();
    }

    fn onLaunchAction(_: *gio.SimpleAction, parameter: *glib.Variant, window: *Self) callconv(.c) void {
        const s_param = parameter.getString(null);
        var it = std.mem.splitSequence(u8, std.mem.span(s_param), "::");
        const app_id = it.next().?;
        const action = it.next().?;
        window.private().application_provider.launchAction(app_id, action) catch unreachable;
        window.hide();
    }

    pub fn new(allocator: std.mem.Allocator, application_provider: *ApplicationProvider) *Self {
        const self = g.ext.newInstance(Self, .{});
        self.private().allocator = allocator;
        self.private().application_provider = application_provider;
        self.private().model = TsModel.new(allocator, application_provider) catch {
            unreachable;
        };
        const gen = struct {
            fn createWidget(item: *TsModelItem, user_data: *std.mem.Allocator) callconv(.c) *TsListItem {
                return TsListItem.new(user_data.*, item) catch unreachable;
            }
        };
        self.private().list_box.bindModel(
            self.private().model.as(gio.ListModel),
            @ptrCast(&gen.createWidget),
            @ptrCast(&self.private().allocator),
            null,
        );
        self.reset();
        return self;
    }

    pub fn show(self: *Self) void {
        self.reset();
        gtk.Widget.setVisible(self.as(gtk.Widget), 1);
        gtk.Widget.removeCssClass(self.private().main.as(gtk.Widget), "hide");
        gtk.Widget.addCssClass(self.private().main.as(gtk.Widget), "show");
    }

    pub fn hide(self: *Self) void {
        const gen = struct {
            fn callback(widget: *gtk.Widget) callconv(.c) void {
                widget.hide();
            }
        };
        gtk.Widget.removeCssClass(self.private().main.as(gtk.Widget), "show");
        gtk.Widget.addCssClass(self.private().main.as(gtk.Widget), "hide");
        _ = glib.timeoutAddOnce(300, @ptrCast(&gen.callback), self);
    }

    pub fn reset(self: *Self) void {
        const text = gtk.Editable.getDelegate(self.private().search_entry.as(gtk.Editable)).?;
        text.setText("");
        const row = self.private().list_box.getRowAtIndex(0).?;
        self.private().list_box.selectRow(row);
        _ = gtk.Widget.grabFocus(text.as(gtk.Widget));
        self.scrollToSelection();
    }
};
