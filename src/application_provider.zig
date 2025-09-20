const std = @import("std");

pub const Error = error{
    InvalidId,
} || std.mem.Allocator.Error;

pub const ApplicationProvider = @This();
const Self = ApplicationProvider;

pub const Action = struct {
    key: []const u8,
    name: []const u8,
};

pub const Application = struct {
    id: []const u8,
    name: []const u8,
    display_name: []const u8,
    description: ?[]const u8,
    commandline: ?[]const u8,
    icon: ?[]const u8,
    actions: []Action,
    should_show: bool,
};

pub fn Result(T: type) type {
    return struct {
        arena: std.heap.ArenaAllocator,
        data: T,

        pub fn deinit(self: *@This()) void {
            self.arena.deinit();
        }
    };
}

pub const VTable = struct {
    get: *const fn (*Self, []const u8) Error!Result(Application),
    getAll: *const fn (*Self, bool) Error!Result([]Application),
    search: *const fn (*Self, []const u8, bool) Error!Result([]Application),
    launch: *const fn (*Self, []const u8) Error!void,
    launchAction: *const fn (*Self, []const u8, []const u8) Error!void,
};

vtable: *const VTable,

pub fn get(self: *Self, id: []const u8) Error!Result(Application) {
    return self.vtable.get(self, id);
}

pub fn getAll(self: *Self, only_visible: bool) Error!Result([]Application) {
    return self.vtable.getAll(self, only_visible);
}

pub fn search(
    self: *Self,
    search_text: []const u8,
    only_visible: bool,
) Error!Result([]Application) {
    return self.vtable.search(self, search_text, only_visible);
}

pub fn launch(self: *Self, id: []const u8) Error!void {
    return self.vtable.launch(self, id);
}

pub fn launchAction(
    self: *Self,
    id: []const u8,
    action: []const u8,
) Error!void {
    return self.vtable.launchAction(self, id, action);
}
