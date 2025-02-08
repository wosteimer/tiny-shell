const std = @import("std");
const c = @import("c.zig");

pub fn makeInstanceCaster(getGType: *const fn () c.GType, T: type) fn (anytype) *T {
    return struct {
        fn f(instance: anytype) *T {
            return @as(
                *T,
                @ptrCast(
                    c.g_type_check_instance_cast(
                        @alignCast(@ptrCast(instance)),
                        getGType(),
                    ),
                ),
            );
        }
    }.f;
}

pub fn makeClassCaster(getGType: *const fn () c.GType, T: type) fn (anytype) *T {
    return struct {
        fn f(class: anytype) *T {
            return @as(
                *T,
                @ptrCast(
                    c.g_type_check_class_cast(
                        @alignCast(@ptrCast(class)),
                        getGType(),
                    ),
                ),
            );
        }
    }.f;
}

pub fn makeClassPeeker(getGType: *const fn () c.GType, T: type) fn () *T {
    return struct {
        fn f() *T {
            return @as(
                *T,
                @alignCast(
                    @ptrCast(
                        c.g_type_class_peek(getGType()),
                    ),
                ),
            );
        }
    }.f;
}

pub const G_LIST_MODEL = makeInstanceCaster(
    @ptrCast(&c.g_list_model_get_type),
    c.GListModel,
);

pub const G_APP_INFO = makeInstanceCaster(
    @ptrCast(&c.g_app_info_get_type),
    c.GAppInfo,
);

pub const G_OBJECT = makeInstanceCaster(
    @ptrCast(&c.g_object_get_type),
    c.GObject,
);
pub const G_OBJECT_CLASS = makeClassCaster(
    @ptrCast(&c.g_object_get_type),
    c.GObjectClass,
);

pub const GTK_WIDGET = makeInstanceCaster(
    @ptrCast(&c.gtk_widget_get_type),
    c.GtkWidget,
);
pub const GTK_WIDGET_CLASS = makeClassCaster(
    @ptrCast(&c.gtk_widget_get_type),
    c.GtkWidgetClass,
);

pub const GTK_WINDOW = makeInstanceCaster(
    @ptrCast(&c.gtk_window_get_type),
    c.GtkWindow,
);

pub const GTK_EDITABLE = makeInstanceCaster(
    @ptrCast(&c.gtk_editable_get_type),
    c.GtkEditable,
);

pub const GDK_PAINTABLE = makeInstanceCaster(
    @ptrCast(&c.gdk_paintable_get_type),
    c.GdkPaintable,
);
