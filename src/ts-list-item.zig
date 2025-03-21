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
    popover: *c.GtkPopoverMenu,

    fn classInit(class: *TsListItemClass) callconv(.C) void {
        g.G_OBJECT_CLASS(class).*.dispose = @ptrCast(&dispose);
        g.G_OBJECT_CLASS(class).*.finalize = @ptrCast(&finalize);
        c.gtk_widget_class_set_template_from_resource(
            g.GTK_WIDGET_CLASS(class),
            "/com/github/wosteimer/tiny/launcher/ui/ts-list-item.ui",
        );
        inline for (@typeInfo(Self).Struct.fields) |field| {
            const name = field.name;
            if (std.mem.eql(u8, name, "parent")) comptime continue;
            c.gtk_widget_class_bind_template_child_full(
                g.GTK_WIDGET_CLASS(class),
                name,
                0,
                @offsetOf(Self, name),
            );
        }
        inline for (@typeInfo(Self).Struct.decls) |decl| {
            const name = decl.name;
            if (!std.mem.startsWith(u8, name, "on")) comptime continue;
            if (!std.ascii.isUpper(name[2])) comptime continue;
            c.gtk_widget_class_bind_template_callback_full(
                g.GTK_WIDGET_CLASS(class),
                name,
                @ptrCast(&@field(Self, name)),
            );
        }
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

    pub fn onRightClick(
        self: *Self,
        _: *c.GtkGestureClick,
        _: i32,
        _: f64,
        _: f64,
        _: c.gpointer,
    ) callconv(.C) void {
        self.openMenu();
    }

    pub fn openMenu(self: *Self) void {
        c.gtk_popover_popup(g.GTK_POPOVER(self.popover));
    }

    pub fn new(desktop_app_info: *c.GDesktopAppInfo) callconv(.C) *Self {
        const self: *TsListItem = TS_LIST_ITEM(c.g_object_new(getType(), null));
        const app_info: *c.GAppInfo = g.G_APP_INFO(desktop_app_info);
        const app_name = c.g_app_info_get_name(app_info);
        const app_icon = c.g_app_info_get_icon(app_info);
        const display = c.gdk_display_get_default();
        const icon_theme = c.gtk_icon_theme_get_for_display(display);
        var icon: ?*c.GtkIconPaintable = undefined;
        if (app_icon != null) {
            icon = c.gtk_icon_theme_lookup_by_gicon(
                icon_theme,
                app_icon,
                32,
                1,
                c.GTK_TEXT_DIR_NONE,
                0,
            );
        } else {
            icon = c.gtk_icon_theme_lookup_icon(
                icon_theme,
                "image-missing",
                null,
                32,
                1,
                c.GTK_TEXT_DIR_NONE,
                0,
            );
        }
        defer c.g_object_unref(icon);
        c.gtk_label_set_label(self.name, app_name);
        c.gtk_widget_set_tooltip_text(g.GTK_WIDGET(self.name), app_name);
        c.gtk_image_set_from_paintable(self.icon, g.GDK_PAINTABLE(icon));
        const menu = createMenu(desktop_app_info) catch {
            @panic("error while trying to create a menu ");
        };
        c.gtk_popover_menu_set_menu_model(self.popover, menu);
        return self;
    }

    fn createMenu(app_info: *c.GDesktopAppInfo) !*c.GMenuModel {
        const menu = c.g_menu_new();
        const section_a = c.g_menu_new();
        const section_b = c.g_menu_new();
        const section_c = c.g_menu_new();
        const actions = c.g_desktop_app_info_list_actions(
            g.G_DESKTOP_APP_INFO(app_info),
        );
        var i: usize = 0;
        var buf = std.mem.zeroes([256:0]u8);
        const app_id = c.g_app_info_get_id(g.G_APP_INFO(app_info));
        while (actions[i] != null) {
            const label = c.g_desktop_app_info_get_action_name(
                g.G_DESKTOP_APP_INFO(app_info),
                actions[i],
            );
            defer c.g_free(label);
            _ = try std.fmt.bufPrintZ(
                &buf,
                "app.launch-action::{s}::{s}",
                .{ app_id, actions[i] },
            );
            c.g_menu_append(section_b, label, &buf);
            i += 1;
        }
        _ = try std.fmt.bufPrintZ(&buf, "app.launch::{s}", .{app_id});
        c.g_menu_append(section_a, "abrir", &buf);
        _ = try std.fmt.bufPrintZ(&buf, "app.hide::{s}", .{app_id});
        c.g_menu_append(section_c, "ocultar", &buf);
        c.g_menu_append_section(menu, null, g.G_MENU_MODEL(section_a));
        c.g_menu_append_section(menu, null, g.G_MENU_MODEL(section_b));
        c.g_menu_append_section(menu, null, g.G_MENU_MODEL(section_c));
        return g.G_MENU_MODEL(menu);
    }

    pub fn getType() c.GType {
        return g_type.getType();
    }
};
