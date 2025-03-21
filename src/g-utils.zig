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

pub fn GType(
    comptime C: type,
    comptime T: type,
    classInit: *const fn (*C) callconv(.C) void,
    init: *const fn (*T) callconv(.C) void,
    getParentType: *const fn () c.GType,
) type {
    return struct {
        var buf = std.mem.zeroes([255]u8);
        var fba = std.heap.FixedBufferAllocator.init(&buf);
        const allocator = fba.allocator();
        var g_type: c.GType = 0;

        pub fn getType() c.GType {
            if (g_type != 0) return g_type;
            var iter = std.mem.splitSequence(u8, @typeName(T), ".");
            _ = iter.next();
            const name = allocator.dupeZ(u8, iter.next().?) catch {
                @panic("class name is too long");
            };
            g_type = c.g_type_register_static_simple(
                getParentType(),
                name,
                @sizeOf(C),
                @ptrCast(classInit),
                @sizeOf(T),
                @ptrCast(init),
                c.G_TYPE_FLAG_FINAL,
            );
            return g_type;
        }
    };
}

pub fn GTypeWithInterface(
    comptime C: type,
    comptime T: type,
    comptime I: type,
    classInit: *const fn (*C) callconv(.C) void,
    init: *const fn (*T) callconv(.C) void,
    interfaceInit: *const fn (*I) callconv(.C) void,
    getInterfaceType: *const fn () c.GType,
    getParentType: *const fn () c.GType,
) type {
    return struct {
        var buf = std.mem.zeroes([255]u8);
        var fba = std.heap.FixedBufferAllocator.init(&buf);
        const allocator = fba.allocator();

        var g_type: c.GType = 0;
        pub fn getType() c.GType {
            if (g_type != 0) return g_type;
            var iter = std.mem.splitSequence(u8, @typeName(T), ".");
            _ = iter.next();
            const name = allocator.dupeZ(u8, iter.next().?) catch {
                @panic("class name is too long");
            };

            g_type = c.g_type_register_static_simple(
                getParentType(),
                name,
                @sizeOf(C),
                @ptrCast(classInit),
                @sizeOf(T),
                @ptrCast(init),
                c.G_TYPE_FLAG_FINAL,
            );
            const interface_info = c.GInterfaceInfo{
                .interface_init = @ptrCast(interfaceInit),
                .interface_data = null,
                .interface_finalize = null,
            };
            c.g_type_add_interface_static(
                g_type,
                getInterfaceType(),
                &interface_info,
            );
            return g_type;
        }
    };
}

pub const G_APPLICATION = makeInstanceCaster(
    @ptrCast(&c.g_application_get_type),
    c.GApplication,
);

pub const G_LIST_MODEL = makeInstanceCaster(
    @ptrCast(&c.g_list_model_get_type),
    c.GListModel,
);

pub const G_APP_INFO = makeInstanceCaster(
    @ptrCast(&c.g_app_info_get_type),
    c.GAppInfo,
);

pub const G_DESKTOP_APP_INFO = makeInstanceCaster(
    @ptrCast(&c.g_desktop_app_info_get_type),
    c.GDesktopAppInfo,
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

pub const GTK_TEXT = makeInstanceCaster(
    @ptrCast(&c.gtk_text_get_type),
    c.GtkText,
);

pub const GTK_GESTURE_SINGLE = makeInstanceCaster(
    @ptrCast(&c.gtk_gesture_single_get_type),
    c.GtkGestureSingle,
);

pub const G_MENU_MODEL = makeInstanceCaster(
    @ptrCast(&c.g_menu_model_get_type),
    c.GMenuModel,
);

pub const GTK_POPOVER_MENU = makeInstanceCaster(
    @ptrCast(&c.gtk_popover_menu_get_type),
    c.GtkPopoverMenu,
);

pub const GTK_POPOVER = makeInstanceCaster(
    @ptrCast(&c.gtk_popover_get_type),
    c.GtkPopover,
);
