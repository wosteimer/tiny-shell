const std = @import("std");
const gio = @import("gio");
const giounix = @import("giounix");
const g = @import("gobject");
const glib = @import("glib");

const ApplicationProvider = @import("application_provider.zig");
const Error = ApplicationProvider.Error;
const Result = ApplicationProvider.Result;
const Application = ApplicationProvider.Application;
const Action = ApplicationProvider.Action;

pub const GApplicationProvider = @This();

const Self = @This();

allocator: std.mem.Allocator,
interface: ApplicationProvider = .{
    .vtable = &ApplicationProvider.VTable{
        .get = &get,
        .getAll = &getAll,
        .search = &search,
        .launch = &launch,
        .launchAction = &launchAction,
    },
},

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .allocator = allocator,
    };
}

pub fn get(provider: *ApplicationProvider, id: []const u8) Error!Result(Application) {
    const self: *Self = @alignCast(@fieldParentPtr("interface", provider));
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    const allocator = arena.allocator();
    const id_z = try self.allocator.dupeZ(u8, id);
    defer self.allocator.free(id_z);
    if (giounix.DesktopAppInfo.new(id_z)) |app_info| {
        return .{
            .arena = arena,
            .data = try self.createApplication(allocator, app_info),
        };
    }
    return Error.InvalidId;
}

pub fn getAll(provider: *ApplicationProvider, only_visible: bool) Error!Result([]Application) {
    const self: *Self = @alignCast(@fieldParentPtr("interface", provider));
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    const allocator = arena.allocator();
    const infos = gio.AppInfo.getAll();
    defer infos.freeFull(@ptrCast(&g.Object.unref));
    var applications = std.ArrayList(Application){};
    defer applications.deinit(self.allocator);
    var current: ?*glib.List = infos;
    while (current != null) : (current = current.?.f_next) {
        const app_info: *giounix.DesktopAppInfo = @ptrCast(@alignCast(current.?.f_data));
        const should_show: bool = gio.AppInfo.shouldShow(app_info.as(gio.AppInfo)) != 0;
        if (only_visible and !should_show) continue;
        try applications.append(self.allocator, try self.createApplication(
            allocator,
            app_info,
        ));
    }
    std.mem.sort(Application, applications.items, .{}, lessThan);
    return .{
        .arena = arena,
        .data = try allocator.dupe(Application, applications.items),
    };
}

fn lessThan(_: @TypeOf(.{}), first: Application, second: Application) bool {
    return std.mem.order(u8, first.display_name, second.display_name) == .lt;
}

pub fn search(
    provider: *ApplicationProvider,
    search_text: []const u8,
    only_visible: bool,
) Error!Result([]Application) {
    const self: *Self = @alignCast(@fieldParentPtr("interface", provider));
    var arena = std.heap.ArenaAllocator.init(self.allocator);
    const allocator = arena.allocator();
    const search_text_z = try self.allocator.dupeZ(u8, search_text);
    defer self.allocator.free(search_text_z);
    const ids = giounix.DesktopAppInfo.search(search_text_z);
    defer glib.free(@ptrCast(ids));
    var i: usize = 0;
    var applications = std.ArrayList(Application){};
    defer applications.deinit(self.allocator);
    i = 0;
    var pos: usize = 0;
    while (@intFromPtr(ids[i]) != 0) : (i += 1) {
        var j: usize = 0;
        defer glib.strfreev(@ptrCast(ids[i]));
        while (@intFromPtr(ids[i][j]) != 0) : (j += 1) {
            const id = ids[i][j];
            if (giounix.DesktopAppInfo.new(id)) |app_info| {
                defer app_info.unref();
                const should_show = gio.AppInfo.shouldShow(app_info.as(gio.AppInfo)) != 0;
                if (only_visible and !should_show) continue;
                try applications.append(self.allocator, try self.createApplication(
                    allocator,
                    app_info,
                ));
            }
            pos += 1;
        }
    }
    glib.strfreev(@ptrCast(ids[i]));
    return .{
        .arena = arena,
        .data = try allocator.dupe(Application, applications.items),
    };
}

pub fn launch(provider: *ApplicationProvider, id: []const u8) Error!void {
    const self: *Self = @alignCast(@fieldParentPtr("interface", provider));
    const id_z = try self.allocator.dupeZ(u8, id);
    defer self.allocator.free(id_z);
    if (giounix.DesktopAppInfo.new(id_z)) |app_info| {
        defer app_info.unref();
        _ = gio.AppInfo.launch(app_info.as(gio.AppInfo), null, null, null);
        return;
    }
    return error.InvalidId;
}

pub fn launchAction(provider: *ApplicationProvider, id: []const u8, action: []const u8) Error!void {
    const self: *Self = @alignCast(@fieldParentPtr("interface", provider));
    const id_z = try self.allocator.dupeZ(u8, id);
    defer self.allocator.free(id_z);
    const action_z = try self.allocator.dupeZ(u8, action);
    defer self.allocator.free(action_z);
    if (giounix.DesktopAppInfo.new(id_z)) |app_info| {
        defer app_info.unref();
        app_info.launchAction(action_z, null);
        return;
    }
    return error.InvalidId;
}

fn createApplication(
    self: Self,
    allocator: std.mem.Allocator,
    app_info: *giounix.DesktopAppInfo,
) Error!Application {
    var icon: ?[]const u8 = null;
    if (gio.AppInfo.getIcon(app_info.as(gio.AppInfo))) |capture| {
        if (capture.toString()) |c_icon| {
            defer glib.free(@ptrCast(c_icon));
            icon = try allocator.dupeZ(u8, std.mem.span(c_icon));
        }
    }
    var description: ?[]const u8 = null;
    if (gio.AppInfo.getDescription(app_info.as(gio.AppInfo))) |capture| {
        description = try allocator.dupeZ(u8, std.mem.span(capture));
    }
    var commandline: ?[]const u8 = null;
    if (gio.AppInfo.getCommandline(app_info.as(gio.AppInfo))) |capture| {
        commandline = try allocator.dupeZ(u8, std.mem.span(capture));
    }
    const keys = app_info.listActions();
    var actions = std.ArrayList(Action){};
    defer actions.deinit(self.allocator);
    var i: usize = 0;
    while (@intFromPtr(keys[i]) != 0) : (i += 1) {
        const key = keys[i];
        const name = app_info.getActionName(key);
        defer glib.free(@ptrCast(name));
        try actions.append(
            self.allocator,
            .{
                .key = try allocator.dupeZ(u8, std.mem.span(key)),
                .name = try allocator.dupeZ(u8, std.mem.span(name)),
            },
        );
    }
    return .{
        .id = try allocator.dupeZ(
            u8,
            std.mem.span(gio.AppInfo.getId(app_info.as(gio.AppInfo)) orelse ""),
        ),
        .name = try allocator.dupeZ(
            u8,
            std.mem.span(gio.AppInfo.getName(app_info.as(gio.AppInfo))),
        ),
        .display_name = try allocator.dupeZ(u8, std.mem.span(
            gio.AppInfo.getDisplayName(app_info.as(gio.AppInfo)),
        )),
        .description = description,
        .commandline = commandline,
        .icon = icon,
        .actions = try allocator.dupe(Action, actions.items),
        .should_show = gio.AppInfo.shouldShow(app_info.as(gio.AppInfo)) != 0,
    };
}
