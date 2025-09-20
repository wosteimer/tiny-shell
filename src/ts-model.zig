const std = @import("std");
const g = @import("gobject");
const gio = @import("gio");
const glib = @import("glib");

const ApplicationProvider = @import("application_provider.zig");
const Application = @import("application_provider.zig").Application;
const Action = @import("application_provider.zig").Action;

pub const TsModelItem = extern struct {
    parent: Parent,

    const Self = @This();
    pub const Parent = g.Object;

    const Private = struct {
        arena: std.heap.ArenaAllocator,
        application: Application,

        var offset: c_int = 0;
    };

    pub const Class = extern struct {
        parent_class: Parent.Class,

        pub const Instance = TsModelItem;
        var parent: *Parent.Class = undefined;

        pub fn as(class: *Class, comptime T: type) *T {
            return g.ext.as(T, class);
        }

        pub fn init(class: *Class) callconv(.c) void {
            g.Object.virtual_methods.dispose.implement(class, &dispose);
            g.Object.virtual_methods.finalize.implement(class, &finalize);
        }
    };

    pub const getGObjectType = g.ext.defineClass(TsModelItem, .{
        .classInit = &Class.init,
        .parent_class = &Class.parent,
        .private = .{ .Type = Private, .offset = &Private.offset },
    });

    fn dispose(self: *Self) callconv(.c) void {
        g.Object.virtual_methods.dispose.call(Class.parent, self.as(g.Object));
    }

    fn finalize(self: *Self) callconv(.c) void {
        self.private().arena.deinit();
        g.Object.virtual_methods.finalize.call(Class.parent, self.as(g.Object));
    }

    fn private(self: *Self) *Private {
        return g.ext.impl_helpers.getPrivate(self, Private, Private.offset);
    }

    pub fn as(self: *Self, comptime T: type) *T {
        return g.ext.as(T, self);
    }

    pub fn new(allocator: std.mem.Allocator, app: Application) *Self {
        const self = g.ext.newInstance(TsModelItem, .{});
        self.private().arena = std.heap.ArenaAllocator.init(allocator);
        self.private().application = copy(self.private().arena.allocator(), app);
        return self;
    }

    fn copy(allocator: std.mem.Allocator, app: Application) Application {
        const actions = allocator.alloc(Action, app.actions.len) catch unreachable;
        for (0..actions.len) |i| {
            actions[i] = .{
                .key = allocator.dupeZ(u8, app.actions[i].key) catch unreachable,
                .name = allocator.dupeZ(u8, app.actions[i].name) catch unreachable,
            };
        }
        var description: ?[]u8 = null;
        if (app.description) |capture| {
            description = allocator.dupeZ(u8, capture) catch unreachable;
        }
        var commandline: ?[]u8 = null;
        if (app.commandline) |capture| {
            commandline = allocator.dupeZ(u8, capture) catch unreachable;
        }
        var icon: ?[]u8 = null;
        if (app.icon) |capture| {
            icon = allocator.dupeZ(u8, capture) catch unreachable;
        }
        return Application{
            .id = allocator.dupeZ(u8, app.id) catch unreachable,
            .name = allocator.dupeZ(u8, app.name) catch unreachable,
            .display_name = allocator.dupeZ(u8, app.display_name) catch unreachable,
            .description = description,
            .commandline = commandline,
            .icon = icon,
            .actions = actions,
            .should_show = app.should_show,
        };
    }

    pub fn ref(self: *Self) *TsModelItem {
        return g.Object.ref(self.as(g.Object)).as(TsModelItem);
    }

    pub fn unref(self: *Self) void {
        g.Object.unref(self.as(g.Object));
    }

    pub fn getApplication(self: *Self) Application {
        return self.private().application;
    }
};

pub const TsModel = extern struct {
    parent: Parent,

    const Self = @This();
    pub const Parent = g.Object;
    pub const Implements = [_]type{
        gio.ListModel,
    };

    const Private = struct {
        allocator: std.mem.Allocator,
        filter: []u8,
        provider: *ApplicationProvider,
        apps: ApplicationProvider.Result([]ApplicationProvider.Application),

        var offset: c_int = 0;
    };

    pub const Class = extern struct {
        parent_class: Parent.Class,

        pub const Instance = TsModel;
        var parent: *Parent.Class = undefined;

        pub fn as(class: *Class, comptime T: type) *T {
            return g.ext.as(T, class);
        }

        pub fn init(class: *Class) callconv(.c) void {
            g.Object.virtual_methods.dispose.implement(class, &dispose);
            g.Object.virtual_methods.finalize.implement(class, &finalize);
            g.Object.virtual_methods.get_property.implement(class, &getProperty);
            g.Object.virtual_methods.set_property.implement(class, &setProperty);
            const flags = g.ParamFlags{
                .readable = true,
                .writable = true,
                .static_name = true,
                .static_nick = true,
                .static_blurb = true,
            };
            properties[@intFromEnum(Prop.filter)] = g.paramSpecString(
                "filter",
                null,
                null,
                "",
                flags,
            );
            g.ObjectClass.installProperties(
                class.as(g.ObjectClass),
                @intCast(@intFromEnum(Prop.n_properties)),
                @ptrCast(&properties),
            );
        }
    };

    pub const getGObjectType = g.ext.defineClass(TsModel, .{
        .classInit = &Class.init,
        .parent_class = &Class.parent,
        .implements = &.{
            g.ext.implement(gio.ListModel, .{ .init = &interfaceInit }),
        },
        .private = .{ .Type = Private, .offset = &Private.offset },
    });

    const Prop = enum(usize) {
        filter = 1,
        n_properties,
    };
    var properties = std.mem.zeroes([@intFromEnum(Prop.n_properties)]?*g.ParamSpec);

    fn interfaceInit(interface: *gio.ListModelInterface) callconv(.c) void {
        interface.*.f_get_item = @ptrCast(&getItem);
        interface.*.f_get_item_type = @ptrCast(&getItemType);
        interface.*.f_get_n_items = @ptrCast(&getNItems);
    }

    fn getProperty(
        self: *Self,
        property_id: u32,
        value: *g.Value,
        _: *g.ParamSpec,
    ) callconv(.c) void {
        switch (@as(Prop, @enumFromInt(property_id))) {
            .filter => {
                const filter = self.private().allocator.dupeZ(u8, self.getFilter()) catch unreachable;
                defer self.private().allocator.free(filter);
                value.setString(filter);
            },
            else => @panic("invalid property id"),
        }
    }

    fn setProperty(self: *Self, property_id: u32, value: *const g.Value, _: *g.ParamSpec) callconv(.c) void {
        switch (@as(Prop, @enumFromInt(property_id))) {
            .filter => self.setFilter(std.mem.span(value.getString() orelse "")),
            else => @panic("invalid property id"),
        }
    }

    fn dispose(self: *Self) callconv(.c) void {
        g.Object.virtual_methods.dispose.call(Class.parent, self.as(Parent));
    }

    fn finalize(self: *Self) callconv(.c) void {
        self.private().apps.deinit();
        self.private().allocator.free(self.private().filter);
        g.Object.virtual_methods.finalize.call(Class.parent, self.as(Parent));
    }

    fn getItem(self: *Self, pos: usize) callconv(.c) *TsModelItem {
        return TsModelItem.new(
            self.private().allocator,
            self.private().apps.data[pos],
        );
    }

    fn getItemType(_: *Self) callconv(.c) usize {
        return TsModelItem.getGObjectType();
    }

    fn getNItems(self: *Self) callconv(.c) usize {
        return self.private().apps.data.len;
    }

    fn private(self: *Self) *Private {
        return g.ext.impl_helpers.getPrivate(self, Private, Private.offset);
    }

    pub fn as(self: *Self, comptime T: type) *T {
        return g.ext.as(T, self);
    }

    pub fn new(allocator: std.mem.Allocator, provider: *ApplicationProvider) !*Self {
        const self = g.ext.newInstance(TsModel, .{});
        self.private().allocator = allocator;
        self.private().provider = provider;
        self.private().filter = try allocator.dupeZ(u8, "");
        self.private().apps = try provider.getAll(true);
        return self;
    }

    pub fn ref(self: *Self) *TsModel {
        return g.Object.ref(self.as(g.Object)).as(TsModel);
    }

    pub fn unref(self: *Self) void {
        g.Object.unref(self.as(g.Object));
    }

    pub fn getFilter(self: *Self) []const u8 {
        return @ptrCast(self.private().filter);
    }

    pub fn setFilter(self: *Self, filter: []const u8) void {
        const removed = self.private().apps.data.len;
        self.private().allocator.free(self.private().filter);
        self.private().apps.deinit();
        self.private().filter = self.private().allocator.dupeZ(u8, filter) catch {
            @panic("ops");
        };
        if (std.mem.eql(u8, filter, "")) {
            self.private().apps = self.private().provider.getAll(true) catch {
                @panic("ops");
            };
            gio.ListModel.itemsChanged(
                self.as(gio.ListModel),
                0,
                @intCast(removed),
                @intCast(self.private().apps.data.len),
            );
            return;
        }
        self.private().apps = self.private().provider.search(filter, true) catch {
            @panic("ops");
        };
        gio.ListModel.itemsChanged(
            self.as(gio.ListModel),
            0,
            @intCast(removed),
            @intCast(self.private().apps.data.len),
        );
    }
};
