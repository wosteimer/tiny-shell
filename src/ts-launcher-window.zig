const std = @import("std");
const c = @cImport({
    @cInclude("gtk/gtk.h");
    @cInclude("gio/gdesktopappinfo.h");
    @cInclude("adwaita.h");
});
const TsListItem = @import("ts-list-item.zig").TsListItem;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

pub const TsLauncherWindow = struct {
    parent: c.AdwApplicationWindow,
    search_entry: *c.GtkSearchEntry,
    list_box: *c.GtkListBox,
    model: ?*c.GListStore,

    var G_TYPE: c.GType = undefined;
    const Self = @This();

    fn classInit(class: *c.GtkWidgetClass) callconv(.C) void {
        @as(*c.GObjectClass, @alignCast(@ptrCast(class))).*.dispose = @ptrCast(&dispose);
        @as(*c.GObjectClass, @alignCast(@ptrCast(class))).*.finalize = @ptrCast(&finalize);
        c.gtk_widget_class_set_template_from_resource(
            class,
            "/com/github/wosteimer/tiny-launcher/ts-launcher-window.ui",
        );
        c.gtk_widget_class_bind_template_child_full(class, "search_entry", 0, @offsetOf(
            TsLauncherWindow,
            "search_entry",
        ));
        c.gtk_widget_class_bind_template_child_full(class, "list_box", 0, @offsetOf(
            TsLauncherWindow,
            "list_box",
        ));
        c.gtk_widget_class_bind_template_callback_full(
            class,
            "onKeyPressed",
            @ptrCast(&onKeyPressed),
        );
        c.gtk_widget_class_bind_template_callback_full(
            class,
            "onSearchChanged",
            @ptrCast(&onSearchChanged),
        );
    }

    fn getParentClass() *c.GObjectClass {
        return @as(*c.GObjectClass, @alignCast(@ptrCast(c.g_type_class_peek(c.gtk_application_window_get_type()))));
    }

    fn dispose(self: *Self) callconv(.C) void {
        c.gtk_widget_dispose_template(@ptrCast(self), G_TYPE);
        if (getParentClass().*.dispose) |parent_dispose| {
            parent_dispose(@ptrCast(self));
        }
        c.g_object_unref(self.model);
    }

    fn finalize(self: *Self) callconv(.C) void {
        if (getParentClass().*.finalize) |parent_finalize| {
            parent_finalize(@ptrCast(self));
        }
    }

    fn init(self: *Self) callconv(.C) void {
        c.gtk_widget_init_template(@ptrCast(self));
        self.model = c.g_list_store_new(c.g_app_info_get_type());
        c.gtk_list_box_bind_model(self.list_box, @ptrCast(self.model), @ptrCast(&TsListItem.new), null, null);
        self.showAllApps();
    }

    fn lessThan(_: void, first: ?*c.GAppInfo, second: ?*c.GAppInfo) bool {
        const first_name = std.mem.span(c.g_app_info_get_name(first));
        const second_name = std.mem.span(c.g_app_info_get_name(second));
        return std.mem.order(u8, first_name, second_name) == .lt;
    }

    fn showAllApps(self: *Self) void {
        var app_info = c.g_app_info_get_all();
        defer c.g_list_free_full(app_info, c.g_object_unref);
        var buf = std.ArrayList(?*c.GAppInfo).init(allocator);
        defer buf.deinit();
        while (app_info != null) : (app_info = app_info.*.next) {
            if (c.g_app_info_should_show(@ptrCast(app_info.*.data)) == 0) {
                continue;
            }
            buf.append(@ptrCast(app_info.*.data)) catch @panic("out of memory");
        }
        std.mem.sort(?*c.GAppInfo, buf.items, {}, lessThan);
        c.g_list_store_splice(
            self.model,
            0,
            c.g_list_model_get_n_items(@ptrCast(self.model)),
            @ptrCast(buf.items),
            @intCast(buf.items.len),
        );
    }

    fn onKeyPressed(
        self: *Self,
        keyval: u32,
        _: u32,
        _: c.GdkModifierType,
        _: *c.GtkEventControllerKey,
    ) callconv(.C) bool {
        if (keyval == c.GDK_KEY_Escape) {
            c.gtk_window_close(@ptrCast(self));
        }
        const editable: *c.GtkEditable = @ptrCast(self.search_entry);
        const char = c.gdk_keyval_to_unicode(keyval);
        var pos = c.gtk_editable_get_position(editable);
        if (keyval == c.GDK_KEY_BackSpace) {
            c.gtk_editable_delete_text(editable, @max(pos - 1, 0), pos);
        } else if (char != 0) {
            pos = c.gtk_editable_get_position(editable);
            c.gtk_editable_insert_text(editable, @ptrCast(&char), 1, &pos);
            c.gtk_editable_set_position(editable, pos);
        }
        _ = c.gtk_widget_grab_focus(@alignCast(@ptrCast(self.search_entry)));
        return false;
    }

    fn onSearchChanged(self: *Self, entry: *c.GtkSearchEntry) callconv(.C) void {
        const text: []const u8 = std.mem.span(c.gtk_editable_get_text(@ptrCast(entry)));
        if (text.len == 0) {
            self.showAllApps();
            return;
        }
        var buf = std.ArrayList(?*c.GDesktopAppInfo).init(allocator);
        defer buf.deinit();
        const result = c.g_desktop_app_info_search(@ptrCast(text));
        defer c.g_free(@ptrCast(result));
        var i: usize = 0;
        while (result[i] != null) : (i += 1) {
            var j: usize = 0;
            defer c.g_strfreev(result[i]);
            while (result[i][j] != null) : (j += 1) {
                const app_id = result[i][j];
                const app_info = c.g_desktop_app_info_new(app_id);
                if (c.g_app_info_should_show(@ptrCast(app_info)) == 0) continue;
                buf.append(app_info) catch @panic("out memory");
            }
        }
        c.g_strfreev(result[i]);
        c.g_list_store_splice(
            self.model,
            0,
            c.g_list_model_get_n_items(@ptrCast(self.model)),
            @ptrCast(buf.items),
            @intCast(buf.items.len),
        );
        c.gtk_list_box_select_row(
            @ptrCast(self.list_box),
            c.gtk_list_box_get_row_at_index(@ptrCast(self.list_box), 0),
        );
    }

    pub fn new() callconv(.C) *Self {
        if (G_TYPE == 0) {
            G_TYPE = register();
        }
        return @alignCast(@ptrCast(c.g_object_new(G_TYPE, null)));
    }

    fn register() c.GType {
        return c.g_type_register_static_simple(
            c.adw_application_window_get_type(),
            "TsLauncherWindow",
            @sizeOf(c.AdwApplicationWindowClass),
            @ptrCast(&classInit),
            @sizeOf(TsLauncherWindow),
            @ptrCast(&init),
            c.G_TYPE_FLAG_FINAL,
        );
    }
};
