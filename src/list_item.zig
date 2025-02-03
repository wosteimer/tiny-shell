const std = @import("std");
const c = @cImport({
    @cInclude("gtk/gtk.h");
    @cInclude("gtk4-layer-shell/gtk4-layer-shell.h");
    @cInclude("gio/gdesktopappinfo.h");
    @cInclude("gobject/gobject.h");
});

pub const TsListItem = struct {
    parent: c.GtkListBoxRow,
    name: *c.GtkLabel,
    icon: *c.GtkImage,

    var g_type: c.GType = undefined;
    const Self = @This();

    fn classInit(class: *c.GtkWidgetClass) callconv(.C) void {
        @as(*c.GObjectClass, @alignCast(@ptrCast(class))).*.dispose = @ptrCast(&dispose);
        c.gtk_widget_class_set_template_from_resource(class, "/com/github/wosteimer/tiny-launcher/list_item.ui");
        c.gtk_widget_class_bind_template_child_full(class, "name", 0, @offsetOf(TsListItem, "name"));
        c.gtk_widget_class_bind_template_child_full(class, "icon", 0, @offsetOf(TsListItem, "icon"));
    }

    fn dispose(self: *Self) callconv(.C) void {
        c.gtk_widget_dispose_template(@ptrCast(self), g_type);
        if (c.g_type_class_peek(c.gtk_list_box_row_get_type())) |parent_class| {
            const parent_g_object_class: *c.GObjectClass = @alignCast(@ptrCast(parent_class));
            if (parent_g_object_class.dispose) |parent_dispose| {
                parent_dispose(@ptrCast(self));
            }
        }
    }

    fn init(self: *Self) callconv(.C) void {
        c.gtk_widget_init_template(@ptrCast(self));
    }

    fn onActivate(_: *Self, app_info: *c.GAppInfo) callconv(.C) void {
        _ = c.g_app_info_launch(app_info, null, null, null);
    }

    pub fn new(app_info: *c.GAppInfo) callconv(.C) *Self {
        if (g_type == 0) {
            g_type = register();
        }
        const self: *TsListItem = @alignCast(@ptrCast(c.g_object_new(g_type, null)));
        const app_name = c.g_app_info_get_name(app_info);
        const app_icon = c.g_app_info_get_icon(app_info);
        c.gtk_label_set_label(self.name, app_name);
        c.gtk_image_set_from_gicon(self.icon, app_icon);
        _ = c.g_signal_connect_data(
            @ptrCast(self),
            "activate",
            @ptrCast(&onActivate),
            @ptrCast(app_info),
            null,
            0,
        );
        return self;
    }

    fn register() c.GType {
        return c.g_type_register_static_simple(
            c.gtk_list_box_row_get_type(),
            "TsListItem",
            @sizeOf(c.GtkListBoxRowClass),
            @ptrCast(&classInit),
            @sizeOf(TsListItem),
            @ptrCast(&init),
            0,
        );
    }
};
