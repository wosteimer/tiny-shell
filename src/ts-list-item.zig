const std = @import("std");
const c = @import("c.zig");
const g = @import("g-utils.zig");

pub const tsListItemParentClass = g.makeClassPeeker(
    @ptrCast(&c.gtk_list_box_row_get_type),
    c.GtkListBoxRow,
);

pub const TS_LIST_ITEM = g.makeInstanceCaster(
    @ptrCast(&TsListItem.getType),
    TsListItem,
);

pub const TsListItemClass = struct { parent: c.GtkListBoxRowClass };

pub const TsListItem = struct {
    const Self = @This();
    const g_type = g.GType(
        TsListItemClass,
        TsListItem,
        &classInit,
        &init,
        @ptrCast(&c.gtk_list_box_row_get_type),
    );

    parent: c.GtkListBoxRow,
    name: *c.GtkLabel,
    icon: *c.GtkImage,
    app_info: *c.GAppInfo,

    fn classInit(class: *TsListItemClass) callconv(.C) void {
        g.G_OBJECT_CLASS(class).*.dispose = @ptrCast(&dispose);
        g.G_OBJECT_CLASS(class).*.finalize = @ptrCast(&finalize);
        c.gtk_widget_class_set_template_from_resource(
            g.GTK_WIDGET_CLASS(class),
            "/com/github/wosteimer/tiny/launcher/ui/ts-list-item.ui",
        );
        c.gtk_widget_class_bind_template_child_full(
            g.GTK_WIDGET_CLASS(class),
            "name",
            0,
            @offsetOf(TsListItem, "name"),
        );
        c.gtk_widget_class_bind_template_child_full(
            g.GTK_WIDGET_CLASS(class),
            "icon",
            0,
            @offsetOf(TsListItem, "icon"),
        );
    }

    fn dispose(gobject: *c.GObject) callconv(.C) void {
        c.gtk_widget_dispose_template(g.GTK_WIDGET(gobject), getType());
        const parent_class = g.G_OBJECT_CLASS(tsListItemParentClass());
        if (parent_class.*.dispose) |parent_dispose| {
            parent_dispose(gobject);
        }
    }

    fn finalize(gobject: *c.GObject) callconv(.C) void {
        const parent_class = g.G_OBJECT_CLASS(tsListItemParentClass());
        if (parent_class.*.finalize) |parent_finalize| {
            parent_finalize(gobject);
        }
    }

    fn init(self: *Self) callconv(.C) void {
        c.gtk_widget_init_template(g.GTK_WIDGET(self));
    }

    pub fn launch(self: *Self) callconv(.C) void {
        _ = c.g_app_info_launch(self.app_info, null, null, null);
    }

    pub fn new(app_info: *c.GAppInfo) callconv(.C) *Self {
        const self: *TsListItem = TS_LIST_ITEM(c.g_object_new(getType(), null));
        self.app_info = app_info;
        const app_name = c.g_app_info_get_name(app_info);
        const app_icon = c.g_app_info_get_icon(app_info);
        const display = c.gdk_display_get_default();
        const icon_theme = c.gtk_icon_theme_get_for_display(display);
        const icon = c.gtk_icon_theme_lookup_by_gicon(
            icon_theme,
            app_icon,
            32,
            1,
            c.GTK_TEXT_DIR_NONE,
            0,
        );
        defer c.g_object_unref(icon);
        c.gtk_label_set_label(self.name, app_name);
        c.gtk_widget_set_tooltip_text(g.GTK_WIDGET(self.name), app_name);
        c.gtk_image_set_from_paintable(self.icon, g.GDK_PAINTABLE(icon));
        return self;
    }

    pub fn getType() c.GType {
        return g_type.getType();
    }
};
