const std = @import("std");
const c = @cImport({
    @cInclude("gtk/gtk.h");
});

pub const TsListItemClass = struct { parent: c.GtkListBoxRowClass };

pub const TsListItem = struct {
    const Self = @This();
    var G_TYPE: c.GType = undefined;

    parent: c.GtkListBoxRow,
    name: *c.GtkLabel,
    icon: *c.GtkImage,
    app_info: *c.GAppInfo,

    fn classInit(class: *TsListItemClass) callconv(.C) void {
        toGObjectClass(class).*.dispose = @ptrCast(&dispose);
        toGObjectClass(class).*.finalize = @ptrCast(&finalize);
        c.gtk_widget_class_set_template_from_resource(@ptrCast(class), "/com/github/wosteimer/tiny-launcher/ts-list-item.ui");
        c.gtk_widget_class_bind_template_child_full(@ptrCast(class), "name", 0, @offsetOf(TsListItem, "name"));
        c.gtk_widget_class_bind_template_child_full(@ptrCast(class), "icon", 0, @offsetOf(TsListItem, "icon"));
    }

    fn toGObjectClass(class: *anyopaque) *c.GObjectClass {
        return @as(*c.GObjectClass, @alignCast(@ptrCast(class)));
    }

    fn getParentClass() *c.GtkListBoxRowClass {
        return @alignCast(@ptrCast(c.g_type_class_peek(c.gtk_list_box_row_get_type())));
    }

    fn dispose(self: *Self) callconv(.C) void {
        c.gtk_widget_dispose_template(@ptrCast(self), G_TYPE);
        if (toGObjectClass(getParentClass()).*.dispose) |parent_dispose| {
            parent_dispose(@ptrCast(self));
        }
    }

    fn finalize(self: *Self) callconv(.C) void {
        if (toGObjectClass(getParentClass()).*.finalize) |parent_finalize| {
            parent_finalize(@ptrCast(self));
        }
    }

    fn init(self: *Self) callconv(.C) void {
        c.gtk_widget_init_template(@ptrCast(self));
    }

    pub fn launch(self: *Self) callconv(.C) void {
        _ = c.g_app_info_launch(self.app_info, null, null, null);
    }

    pub fn new(app_info: *c.GAppInfo) callconv(.C) *Self {
        register();
        const self: *TsListItem = @alignCast(@ptrCast(c.g_object_new(G_TYPE, null)));
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

    fn register() void {
        if (G_TYPE != 0) return;
        G_TYPE = c.g_type_register_static_simple(
            c.gtk_list_box_row_get_type(),
            "TsListItem",
            @sizeOf(TsListItemClass),
            @ptrCast(&classInit),
            @sizeOf(TsListItem),
            @ptrCast(&init),
            c.G_TYPE_FLAG_FINAL,
        );
    }
};
