const std = @import("std");
const c = @cImport({
    @cInclude("gio/gio.h");
    @cInclude("gio/gdesktopappinfo.h");
});

pub const TsModelClass = struct { parent_class: c.GObjectClass };

pub const TsModel = struct {
    const Self = @This();
    var G_TYPE: u64 = undefined;

    parent: c.GObject,
    infos: std.StringHashMap(*c.GAppInfo),
    allocator: std.mem.Allocator,
    current: std.ArrayList([]const u8),
    default: std.ArrayList([]const u8),

    fn toGObjectClass(class: ?*anyopaque) *c.GObjectClass {
        return @as(*c.GObjectClass, @alignCast(@ptrCast(class)));
    }

    fn getParentClass() *c.GObjectClass {
        return @as(*c.GObjectClass, @alignCast(@ptrCast(c.g_type_class_peek(c.g_object_get_type()))));
    }

    fn interfaceInit(interface: *c.GListModelInterface) callconv(.C) void {
        interface.*.get_item = @ptrCast(&getItem);
        interface.*.get_item_type = @ptrCast(&getItemType);
        interface.*.get_n_items = @ptrCast(&getNItems);
    }

    fn classInit(class: *TsModelClass) callconv(.C) void {
        toGObjectClass(class).*.dispose = @ptrCast(&dispose);
        toGObjectClass(class).*.finalize = @ptrCast(&finalize);
    }

    fn dispose(self: *Self) callconv(.C) void {
        if (getParentClass().*.dispose) |parent_dispose| {
            parent_dispose(@ptrCast(self));
        }
    }

    fn finalize(self: *Self) callconv(.C) void {
        for (self.current.items) |app_id| {
            self.allocator.free(app_id);
        }
        var iter = self.infos.iterator();
        while (iter.next()) |app_info| {
            c.g_object_unref(@ptrCast(app_info.value_ptr.*));
        }
        self.infos.deinit();
        self.default.deinit();
        self.current.deinit();
        if (getParentClass().*.finalize) |parent_finalize| {
            parent_finalize(@ptrCast(self));
        }
    }

    fn init(_: *Self) callconv(.C) void {}

    fn getItem(self: *Self, pos: u64) callconv(.C) *c.GAppInfo {
        const app_id = self.current.items[pos];
        const app_info = self.infos.get(app_id) orelse @panic("invalid app_id");
        return @ptrCast(c.g_object_ref(@ptrCast(app_info)));
    }

    fn getItemType(_: *Self) callconv(.C) c.GType {
        return c.g_app_info_get_type();
    }

    fn getNItems(self: *Self) callconv(.C) usize {
        return self.current.items.len;
    }

    pub fn new(allocator: std.mem.Allocator) !*Self {
        register();
        const self: *Self = @alignCast(@ptrCast(c.g_object_new(G_TYPE, null)));
        self.allocator = allocator;
        try initData(self, allocator);
        return self;
    }

    fn lessThan(_: void, first: []const u8, second: []const u8) bool {
        const first_app_info = c.g_desktop_app_info_new(@ptrCast(first));
        defer c.g_object_unref(@ptrCast(first_app_info));
        const second_app_info = c.g_desktop_app_info_new(@ptrCast(second));
        defer c.g_object_unref(@ptrCast(second_app_info));
        const first_name = std.mem.span(c.g_app_info_get_name(@ptrCast(first_app_info)));
        const second_name = std.mem.span(c.g_app_info_get_name(@ptrCast(second_app_info)));
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
        try self.setFilter("");
    }

    fn register() void {
        if (G_TYPE != 0) return;
        G_TYPE = c.g_type_register_static_simple(
            c.g_object_get_type(),
            "TsModel",
            @sizeOf(TsModelClass),
            @ptrCast(&classInit),
            @sizeOf(Self),
            @ptrCast(&init),
            c.G_TYPE_FLAG_FINAL,
        );
        const interface_info = c.GInterfaceInfo{
            .interface_init = @ptrCast(&interfaceInit),
            .interface_data = null,
            .interface_finalize = null,
        };
        c.g_type_add_interface_static(G_TYPE, c.g_list_model_get_type(), &interface_info);
    }

    pub fn setFilter(self: *Self, filter: []const u8) !void {
        const removed: u32 = @intCast(self.current.items.len);
        for (self.current.items) |app_id| {
            self.allocator.free(app_id);
        }
        self.current.clearRetainingCapacity();
        if (filter.len == 0) {
            for (self.default.items) |default_app_id| {
                const app_id = try self.allocator.alloc(u8, default_app_id.len);
                @memcpy(app_id, default_app_id.ptr);
                try self.current.append(app_id);
            }
            const added: u32 = @intCast(self.current.items.len);
            c.g_list_model_items_changed(@ptrCast(self), 0, removed, added);
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
                defer c.g_object_unref(@ptrCast(app_info));
                if (c.g_app_info_should_show(@ptrCast(app_info)) == 0) continue;
                const app_id = try self.allocator.alloc(u8, len);
                @memcpy(app_id, std.mem.span(buf));
                try self.current.append(app_id);
            }
        }
        c.g_strfreev(result[i]);
        const added: u32 = @intCast(self.current.items.len);
        c.g_list_model_items_changed(@ptrCast(self), 0, removed, added);
    }
};

test "must not have leak memory" {
    const model = try TsModel.new(std.testing.allocator);
    defer c.g_object_unref(@ptrCast(model));
    try model.setFilter("d");
    try model.setFilter("a");
}
