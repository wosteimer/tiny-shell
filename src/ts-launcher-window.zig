const std = @import("std");
const c = @import("c.zig");
const g = @import("g-utils.zig");

const TsListItem = @import("ts-list-item.zig").TsListItem;
const TsModel = @import("ts-model.zig").TsModel;

const allocator = std.heap.page_allocator;

pub const TS_LAUNCHER_WINDOW = g.makeInstanceCaster(
    TsLauncherWindow.getType,
    TsLauncherWindow,
);

pub const tsLauncherWindowParentClass = g.makeClassPeeker(
    @ptrCast(&c.adw_application_window_get_type),
    c.AdwApplicationWindowClass,
);

pub const MoveSelectionDirection = enum(i32) {
    previous = -1,
    next = 1,
};

pub const TsLauncherWindowClass = struct {
    parent_class: c.AdwApplicationWindowClass,
};

pub const TsLauncherWindow = struct {
    const g_type = g.GType(
        TsLauncherWindowClass,
        TsLauncherWindow,
        &classInit,
        &init,
        @ptrCast(&c.adw_application_window_get_type),
    );
    const Self = @This();
    parent: c.AdwApplicationWindow,
    model: *TsModel,
    main: *c.GtkBox,
    search_entry: *c.GtkSearchEntry,
    list_box: *c.GtkListBox,
    scrolled_window: *c.GtkScrolledWindow,
    stack: *c.GtkStack,

    fn classInit(class: *TsLauncherWindowClass) callconv(.C) void {
        g.G_OBJECT_CLASS(class).*.dispose = @ptrCast(&dispose);
        g.G_OBJECT_CLASS(class).*.finalize = @ptrCast(&finalize);
        c.gtk_widget_class_set_template_from_resource(
            g.GTK_WIDGET_CLASS(class),
            "/com/github/wosteimer/tiny/launcher/ui/ts-launcher-window.ui",
        );
        inline for (@typeInfo(Self).@"struct".fields) |field| {
            const name = field.name;
            if (std.mem.eql(u8, name, "parent")) comptime continue;
            if (std.mem.eql(u8, name, "model")) comptime continue;
            c.gtk_widget_class_bind_template_child_full(
                g.GTK_WIDGET_CLASS(class),
                name,
                0,
                @offsetOf(Self, name),
            );
        }
        inline for (@typeInfo(Self).@"struct".decls) |decl| {
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
        const self = TS_LAUNCHER_WINDOW(gobject);
        const parent_class = g.G_OBJECT_CLASS(tsLauncherWindowParentClass());
        c.gtk_widget_dispose_template(g.GTK_WIDGET(gobject), Self.getType());
        c.g_object_unref(g.G_OBJECT(self.model));
        if (parent_class.*.dispose) |parent_dispose| {
            parent_dispose(gobject);
        }
    }

    fn finalize(gobject: *c.GObject) callconv(.C) void {
        const parent_class = g.G_OBJECT_CLASS(tsLauncherWindowParentClass());
        if (parent_class.*.finalize) |parent_finalize| {
            parent_finalize(gobject);
        }
    }

    fn init(self: *Self) callconv(.C) void {
        c.gtk_widget_init_template(g.GTK_WIDGET(self));
        self.model = TsModel.new(allocator) catch @panic("out of memory");
        c.gtk_list_box_bind_model(
            self.list_box,
            @ptrCast(self.model),
            @ptrCast(&TsListItem.new),
            null,
            null,
        );
        const shortcut_controller = c.gtk_shortcut_controller_new();
        const text = c.gtk_editable_get_delegate(g.GTK_EDITABLE(self.search_entry));
        c.gtk_widget_add_controller(g.GTK_WIDGET(text), shortcut_controller);
        const shortcuts = .{
            .{ "Escape", &closeShortcut },
            .{ "<Control>y", &confirmShortcut },
            .{ "<Control>n", &nextShortcut },
            .{ "<Control>p", &previousShortcut },
        };
        inline for (shortcuts) |shortcut_data| {
            const shortcut = c.gtk_shortcut_new(
                c.gtk_shortcut_trigger_parse_string(shortcut_data[0]),
                c.gtk_callback_action_new(
                    @ptrCast(shortcut_data[1]),
                    @ptrCast(self),
                    null,
                ),
            );
            c.gtk_shortcut_controller_add_shortcut(
                @ptrCast(shortcut_controller),
                shortcut,
            );
        }
        self.reset();
    }

    fn confirmShortcut(
        widget: *c.GtkWidget,
        _: *c.GVariant,
        window: *Self,
    ) callconv(.C) bool {
        _ = onActivated(window, g.G_OBJECT(widget));
        return true;
    }

    fn closeShortcut(
        _: *c.GtkWidget,
        _: *c.GVariant,
        window: *Self,
    ) callconv(.C) bool {
        window.hide();
        return true;
    }

    fn nextShortcut(
        _: *c.GtkWidget,
        _: *c.GVariant,
        window: *Self,
    ) callconv(.C) bool {
        window.moveSelection(.next);
        return true;
    }

    fn previousShortcut(
        _: *c.GtkWidget,
        _: *c.GVariant,
        window: *Self,
    ) callconv(.C) bool {
        window.moveSelection(.previous);
        return true;
    }

    pub fn moveSelection(self: *Self, direction: MoveSelectionDirection) void {
        const n_rows = c.g_list_model_get_n_items(g.G_LIST_MODEL(self.model));
        if (n_rows == 0) {
            return;
        }
        const row = c.gtk_list_box_get_selected_row(self.list_box);
        const index = c.gtk_list_box_row_get_index(row);
        const next = c.gtk_list_box_get_row_at_index(
            self.list_box,
            wrap(index + @intFromEnum(direction), 0, @intCast(n_rows)),
        );
        c.gtk_list_box_select_row(self.list_box, next);
        self.scrollToSelection();
    }

    fn wrap(value: i32, min_value: i32, max_value: i32) i32 {
        const range_size = max_value - min_value;
        return @mod((value - min_value), range_size) + min_value;
    }

    pub fn scrollToSelection(self: *Self) void {
        const row = c.gtk_list_box_get_selected_row(self.list_box);
        var rect = c.graphene_rect_t{};
        _ = c.gtk_widget_compute_bounds(
            g.GTK_WIDGET(row),
            g.GTK_WIDGET(self.scrolled_window),
            &rect,
        );
        const top = rect.origin.y;
        const bottom = top + rect.size.height;
        const adjustment = c.gtk_scrolled_window_get_vadjustment(
            self.scrolled_window,
        );
        const page_size = c.gtk_adjustment_get_page_size(adjustment);
        const current = c.gtk_adjustment_get_value(adjustment);
        if (bottom > page_size) {
            c.gtk_adjustment_set_value(adjustment, bottom - page_size + current);
        } else if (top < 0) {
            c.gtk_adjustment_set_value(adjustment, current + top);
        }
    }

    pub fn onActivated(self: *Self, _: *c.GObject) callconv(.C) bool {
        if (c.gtk_list_box_get_selected_row(self.list_box)) |selected| {
            const pos: u32 = @intCast(c.gtk_list_box_row_get_index(selected));
            const app_info = g.G_APP_INFO(
                c.g_list_model_get_item(g.G_LIST_MODEL(self.model), pos),
            );
            defer c.g_object_unref(g.G_APP_INFO(app_info));
            _ = c.gtk_widget_activate_action_variant(
                g.GTK_WIDGET(self),
                "app.launch",
                c.g_variant_new_string(c.g_app_info_get_id(app_info)),
            );
        }
        return true;
    }

    pub fn onKeyPressed(
        self: *Self,
        _: u32,
        _: u32,
        _: c.GdkModifierType,
        controller: *c.GtkEventControllerKey,
    ) callconv(.C) bool {
        const text = c.gtk_editable_get_delegate(g.GTK_EDITABLE(self.search_entry));
        _ = c.gtk_widget_grab_focus(g.GTK_WIDGET(text));
        _ = c.gtk_event_controller_key_forward(
            controller,
            g.GTK_WIDGET(text),
        );
        return false;
    }

    pub fn onSearchChanged(
        self: *Self,
        entry: *c.GtkSearchEntry,
    ) callconv(.C) bool {
        const filter = std.mem.span(c.gtk_editable_get_text(g.GTK_EDITABLE(entry)));
        self.model.setFilter(filter);
        if (c.g_list_model_get_n_items(g.G_LIST_MODEL(self.model)) == 0) {
            c.gtk_stack_set_visible_child_name(self.stack, "empty");
            return false;
        }
        c.gtk_stack_set_visible_child_name(self.stack, "list");
        const row = c.gtk_list_box_get_row_at_index(self.list_box, 0);
        c.gtk_list_box_select_row(self.list_box, row);
        const adjustment = c.gtk_scrolled_window_get_vadjustment(
            self.scrolled_window,
        );
        c.gtk_adjustment_set_value(adjustment, 0);
        return false;
    }

    pub fn onMouseReleased(
        self: *Self,
        _: i32,
        x: f64,
        y: f64,
        _: *c.GtkGestureClick,
    ) callconv(.C) bool {
        var rect = c.graphene_rect_t{};
        _ = c.gtk_widget_compute_bounds(
            g.GTK_WIDGET(self.main),
            g.GTK_WIDGET(self),
            &rect,
        );
        if (!c.graphene_rect_contains_point(
            &rect,
            &c.graphene_point_t{ .x = @floatCast(x), .y = @floatCast(y) },
        )) {
            self.hide();
        }
        return false;
    }

    pub fn new() callconv(.C) *Self {
        return TS_LAUNCHER_WINDOW(c.g_object_new(Self.getType(), null));
    }

    pub fn getType() c.GType {
        return g_type.getType();
    }

    pub fn show(self: *Self) void {
        self.reset();
        c.gtk_widget_show(g.GTK_WIDGET(self));
        const display = c.gdk_display_get_default();
        const native = c.gtk_widget_get_native(g.GTK_WIDGET(self));
        const surface = c.gtk_native_get_surface(native);
        const monitor = c.gdk_display_get_monitor_at_surface(display, surface);
        var rect = c.GdkRectangle{};
        c.gdk_monitor_get_geometry(monitor, &rect);
        c.gtk_window_set_default_size(g.GTK_WINDOW(self), rect.width, rect.height);
        c.gtk_widget_remove_css_class(g.GTK_WIDGET(self.main), "hide");
        c.gtk_widget_add_css_class(g.GTK_WIDGET(self.main), "show");
    }

    pub fn hide(self: *Self) void {
        const gen = struct {
            fn callback(widget: c.gpointer) callconv(.C) void {
                c.gtk_widget_hide(g.GTK_WIDGET(widget));
            }
        };
        c.gtk_widget_remove_css_class(g.GTK_WIDGET(self.main), "show");
        c.gtk_widget_add_css_class(g.GTK_WIDGET(self.main), "hide");
        _ = c.g_timeout_add_once(300, &gen.callback, self);
    }

    pub fn reset(self: *Self) void {
        c.g_object_unref(self.model);
        self.model = TsModel.new(allocator) catch @panic("out of memory");
        c.gtk_list_box_bind_model(
            self.list_box,
            @ptrCast(self.model),
            @ptrCast(&TsListItem.new),
            null,
            null,
        );
        const text = c.gtk_editable_get_delegate(g.GTK_EDITABLE(self.search_entry));
        const buffer = c.gtk_text_get_buffer(g.GTK_TEXT(text));
        c.gtk_entry_buffer_set_text(buffer, "", 0);
        const row = c.gtk_list_box_get_row_at_index(self.list_box, 0);
        c.gtk_list_box_select_row(self.list_box, row);
        _ = c.gtk_widget_grab_focus(g.GTK_WIDGET(text));
        self.scrollToSelection();
    }
};
