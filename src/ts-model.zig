const std = @import("std");
const c = @import("c.zig");
const g = @import("g-utils.zig");

pub const TS_MODEL = g.makeInstanceCaster(&TsModel.getType, TsModel);

pub const tsModelParentClass = g.makeClassPeeker(
    @ptrCast(&c.g_object_get_type),
    c.GObjectClass,
);

pub const TsModelClass = struct { parent_class: c.GObjectClass };

pub const TsModel = struct {
    const Self = @This();
    const g_type = g.GTypeWithInterce(
        TsModelClass,
        TsModel,
        c.GListModelInterface,
        &classInit,
        &init,
        &interfaceInit,
        @ptrCast(&c.g_list_model_get_type),
        @ptrCast(&c.g_object_get_type),
    );

    const Prop = enum(usize) {
        filter = 1,
        n_properties,
    };
    var properties = std.mem.zeroes(
        [@intFromEnum(Prop.n_properties)]?*c.GParamSpec,
    );

    parent: c.GObject,
    infos: std.StringHashMap(*c.GAppInfo),
    allocator: std.mem.Allocator,
    current: std.ArrayList([]const u8),
    default: std.ArrayList([]const u8),
    filter: [*:0]const u8,

    fn interfaceInit(interface: *c.GListModelInterface) callconv(.C) void {
        interface.*.get_item = @ptrCast(&getItem);
        interface.*.get_item_type = @ptrCast(&getItemType);
        interface.*.get_n_items = @ptrCast(&getNItems);
    }

    fn classInit(class: *TsModelClass) callconv(.C) void {
        g.G_OBJECT_CLASS(class).*.dispose = @ptrCast(&dispose);
        g.G_OBJECT_CLASS(class).*.finalize = @ptrCast(&finalize);
        g.G_OBJECT_CLASS(class).*.get_property = @ptrCast(&getProperty);
        g.G_OBJECT_CLASS(class).*.set_property = @ptrCast(&setProperty);
        const flags = c.G_PARAM_READWRITE |
            c.G_PARAM_STATIC_STRINGS |
            c.G_PARAM_EXPLICIT_NOTIFY;
        properties[@intFromEnum(Prop.filter)] = c.g_param_spec_string(
            "filter",
            null,
            null,
            "",
            flags,
        );
        c.g_object_class_install_properties(
            g.G_OBJECT_CLASS(class),
            @intFromEnum(Prop.n_properties),
            @ptrCast(&properties),
        );
    }

    fn getProperty(
        gobject: *c.GObject,
        property_id: Prop,
        value: *c.GValue,
        _: *c.GParamSpec,
    ) void {
        const self = TS_MODEL(gobject);
        switch (property_id) {
            .filter => c.g_value_set_string(value, self.getFilter()),
            else => @panic("invalid property id"),
        }
    }

    fn setProperty(
        gobject: *c.GObject,
        property_id: Prop,
        value: *c.GValue,
        _: *c.GParamSpec,
    ) void {
        const self = TS_MODEL(gobject);
        switch (property_id) {
            .filter => self.setFilter(c.g_value_get_string(value)),
            else => @panic("invalid property id"),
        }
    }

    fn dispose(gobject: *c.GObject) callconv(.C) void {
        const parent_class = g.G_OBJECT_CLASS(tsModelParentClass());
        if (parent_class.*.dispose) |parent_dispose| {
            parent_dispose(gobject);
        }
    }

    fn finalize(gobject: *c.GObject) callconv(.C) void {
        const parent_class = g.G_OBJECT_CLASS(tsModelParentClass());
        const self = TS_MODEL(gobject);
        for (self.current.items) |app_id| {
            self.allocator.free(app_id);
        }
        var iter = self.infos.iterator();
        while (iter.next()) |app_info| {
            c.g_object_unref(g.G_APP_INFO(app_info.value_ptr.*));
        }
        self.infos.deinit();
        self.default.deinit();
        self.current.deinit();
        if (parent_class.*.finalize) |parent_finalize| {
            parent_finalize(gobject);
        }
    }

    fn init(_: *Self) callconv(.C) void {}

    fn getItem(self: *Self, pos: u64) callconv(.C) *c.GAppInfo {
        const app_id = self.current.items[pos];
        const app_info = self.infos.get(app_id) orelse @panic("invalid app_id");
        return g.G_APP_INFO(c.g_object_ref(g.G_OBJECT(app_info)));
    }

    fn getItemType(_: *Self) callconv(.C) c.GType {
        return c.g_app_info_get_type();
    }

    fn getNItems(self: *Self) callconv(.C) usize {
        return self.current.items.len;
    }

    pub fn new(allocator: std.mem.Allocator) !*Self {
        const self: *Self = TS_MODEL(c.g_object_new(getType(), null));
        self.allocator = allocator;
        try initData(self, allocator);
        return self;
    }

    fn lessThan(_: void, first: []const u8, second: []const u8) bool {
        const first_app_info = c.g_desktop_app_info_new(@ptrCast(first));
        defer c.g_object_unref(@ptrCast(first_app_info));
        const second_app_info = c.g_desktop_app_info_new(@ptrCast(second));
        defer c.g_object_unref(@ptrCast(second_app_info));
        const first_name = std.mem.span(
            c.g_app_info_get_name(@ptrCast(first_app_info)),
        );
        const second_name = std.mem.span(
            c.g_app_info_get_name(@ptrCast(second_app_info)),
        );
        return std.mem.order(u8, first_name, second_name) == .lt;
    }

    fn initData(self: *Self, allocator: std.mem.Allocator) !void {
        self.infos = std.StringHashMap(*c.GAppInfo).init(allocator);
        self.default = std.ArrayList([]const u8).init(allocator);
        self.current = std.ArrayList([]const u8).init(allocator);
        var data = c.g_app_info_get_all();
        defer c.g_list_free_full(data, c.g_object_unref);
        while (data != null) : (data = data.*.next) {
            const app_info: *c.GAppInfo = @ptrCast(data.*.data);
            if (c.g_app_info_should_show(app_info) == 0) {
                continue;
            }
            const app_id = c.g_app_info_get_id(app_info);
            try self.infos.put(std.mem.span(app_id), @ptrCast(app_info));
            try self.default.append(std.mem.span(app_id));
        }
        std.mem.sort([]const u8, self.default.items, {}, lessThan);
        self.setFilter("");
    }

    pub fn getType() c.GType {
        return g_type.getType();
    }
    pub fn getFilter(self: *Self) callconv(.C) [*:0]const u8 {
        return self.filter;
    }

    pub fn setFilter(self: *Self, filter: [*:0]const u8) callconv(.C) void {
        self.filter = filter;
        const filter_len = std.mem.len(filter);
        const removed: u32 = @intCast(self.current.items.len);
        for (self.current.items) |app_id| {
            self.allocator.free(app_id);
        }
        self.current.clearRetainingCapacity();
        if (filter_len == 0) {
            for (self.default.items) |default_app_id| {
                const app_id = self.allocator.alloc(u8, default_app_id.len) catch {
                    @panic("out of memory");
                };
                @memcpy(app_id, default_app_id.ptr);
                self.current.append(app_id) catch {
                    @panic("out of memory");
                };
            }
            const added: u32 = @intCast(self.current.items.len);
            c.g_list_model_items_changed(g.G_LIST_MODEL(self), 0, removed, added);
            return;
        }
        const result = c.g_desktop_app_info_search(@ptrCast(filter));
        defer c.g_free(@ptrCast(result));
        var i: usize = 0;
        while (result[i] != null) : (i += 1) {
            var j: usize = 0;
            defer c.g_strfreev(result[i]);
            while (result[i][j] != null) : (j += 1) {
                const buf = result[i][j];
                const len = std.mem.len(buf);
                const app_info = c.g_desktop_app_info_new(buf);
                defer c.g_object_unref(g.G_OBJECT(app_info));
                if (c.g_app_info_should_show(g.G_APP_INFO(app_info)) == 0) continue;
                const app_id = self.allocator.alloc(u8, len) catch {
                    @panic("out of memory");
                };
                @memcpy(app_id, std.mem.span(buf));
                self.current.append(app_id) catch {
                    @panic("out of memory");
                };
            }
        }
        c.g_strfreev(result[i]);
        const added: u32 = @intCast(self.current.items.len);
        c.g_list_model_items_changed(g.G_LIST_MODEL(self), 0, removed, added);
        c.g_object_notify_by_pspec(
            g.G_OBJECT(self),
            properties[@intFromEnum(Prop.filter)],
        );
    }
};

// NOTE: This is a bad test case as it depends on the apps that are installed on the
//       machine running it.
test "must not have leak memory" {
    const model = try TsModel.new(std.testing.allocator);
    defer c.g_object_unref(@ptrCast(model));
    model.setFilter("d");
    model.setFilter("a");
}
