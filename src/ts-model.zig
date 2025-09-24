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
        application: *Application,

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
        g.Object.virtual_methods.finalize.call(Class.parent, self.as(g.Object));
    }

    fn private(self: *Self) *Private {
        return g.ext.impl_helpers.getPrivate(self, Private, Private.offset);
    }

    pub fn as(self: *Self, comptime T: type) *T {
        return g.ext.as(T, self);
    }

    pub fn new(app: *Application) *Self {
        const self = g.ext.newInstance(TsModelItem, .{});
        self.private().application = app;
        return self;
    }

    pub fn ref(self: *Self) *TsModelItem {
        return g.Object.ref(self.as(g.Object)).as(TsModelItem);
    }

    pub fn unref(self: *Self) void {
        g.Object.unref(self.as(g.Object));
    }

    pub fn getApplication(self: *Self) *Application {
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
        filter: [:0]const u8,
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
                value.setString(self.getFilter());
            },
            else => @panic("invalid property id"),
        }
    }

    fn setProperty(self: *Self, property_id: u32, value: *const g.Value, _: *g.ParamSpec) callconv(.c) void {
        switch (@as(Prop, @enumFromInt(property_id))) {
            .filter => self.setFilter(value.getString() orelse ""),
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
            &self.private().apps.data[pos],
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

    pub fn getFilter(self: *Self) [*:0]const u8 {
        return self.private().filter;
    }

    pub fn setFilter(self: *Self, filter: [*:0]const u8) void {
        const removed = self.private().apps.data.len;
        self.private().allocator.free(self.private().filter);
        self.private().apps.deinit();
        self.private().filter = self.private().allocator.dupeZ(u8, std.mem.span(filter)) catch unreachable;
        if (std.mem.eql(u8, std.mem.span(filter), "")) {
            self.private().apps = self.private().provider.getAll(true) catch unreachable;
            gio.ListModel.itemsChanged(
                self.as(gio.ListModel),
                0,
                @intCast(removed),
                @intCast(self.private().apps.data.len),
            );
            return;
        }
        self.private().apps = self.private().provider.search(std.mem.span(filter), true) catch unreachable;
        gio.ListModel.itemsChanged(
            self.as(gio.ListModel),
            0,
            @intCast(removed),
            @intCast(self.private().apps.data.len),
        );
    }
};
