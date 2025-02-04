const std = @import("std");
const c = @cImport({
    @cInclude("gtk/gtk.h");
});

pub const TsListItem = struct {
    parent: c.GtkListBoxRow,
    name: *c.GtkLabel,
    icon: *c.GtkImage,
    app_info: *c.GAppInfo,

    var g_type: c.GType = undefined;
    const Self = @This();

    fn classInit(class: *c.GtkWidgetClass) callconv(.C) void {
        @as(*c.GObjectClass, @alignCast(@ptrCast(class))).*.dispose = @ptrCast(&dispose);
        c.gtk_widget_class_set_template_from_resource(class, "/com/github/wosteimer/tiny-launcher/ts-list-item.ui");
        c.gtk_widget_class_bind_template_child_full(class, "name", 0, @offsetOf(TsListItem, "name"));
        c.gtk_widget_class_bind_template_child_full(class, "icon", 0, @offsetOf(TsListItem, "icon"));
    }

    fn dispose(self: *Self) callconv(.C) void {
        c.gtk_widget_dispose_template(@ptrCast(self), g_type);
        const parent_class = c.g_type_class_peek(c.gtk_list_box_row_get_type());
        if (@as(*c.GObjectClass, @alignCast(@ptrCast(parent_class))).*.dispose) |parent_dispose| {
            parent_dispose(@ptrCast(self));
        }
    }

    fn init(self: *Self) callconv(.C) void {
        c.gtk_widget_init_template(@ptrCast(self));
    }

    pub fn launch(self: *Self) callconv(.C) void {
        _ = c.g_app_info_launch(self.app_info, null, null, null);
    }

    pub fn new(app_info: *c.GAppInfo) callconv(.C) *Self {
        if (g_type == 0) {
            g_type = register();
        }
        const self: *TsListItem = @alignCast(@ptrCast(c.g_object_new(g_type, null)));
        self.app_info = app_info;
        const app_name = c.g_app_info_get_name(app_info);
        const app_icon = c.g_app_info_get_icon(app_info);
        const display = c.gdk_display_get_default();
        const icon_theme = c.gtk_icon_theme_get_for_display(display);
        const icon = c.gtk_icon_theme_lookup_by_gicon(
            icon_theme,
            app_icon,
            24,
            1,
            c.GTK_TEXT_DIR_NONE,
            0,
        );
        defer c.g_object_unref(icon);
        c.gtk_label_set_label(self.name, app_name);
        c.gtk_image_set_from_paintable(self.icon, @ptrCast(icon));
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
