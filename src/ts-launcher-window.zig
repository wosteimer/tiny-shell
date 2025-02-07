const std = @import("std");
const c = @cImport({
    @cInclude("gtk/gtk.h");
    @cInclude("gio/gdesktopappinfo.h");
    @cInclude("adwaita.h");
});
const TsListItem = @import("ts-list-item.zig").TsListItem;
const TsModel = @import("ts-model.zig").TsModel;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

pub const TsLauncherWindowClass = struct {
    parent_class: c.AdwApplicationWindowClass,
};

pub const TsLauncherWindow = struct {
    parent: c.AdwApplicationWindow,
    search_entry: *c.GtkSearchEntry,
    list_box: *c.GtkListBox,
    scrolled_window: *c.GtkScrolledWindow,
    model: *TsModel,

    var G_TYPE: c.GType = undefined;
    const Self = @This();

    fn classInit(class: *TsLauncherWindowClass) callconv(.C) void {
        toObjectClass(class).*.dispose = @ptrCast(&dispose);
        toObjectClass(class).*.finalize = @ptrCast(&finalize);
        c.gtk_widget_class_set_template_from_resource(
            toGtkWindgetClass(class),
            "/com/github/wosteimer/tiny/launcher/ui/ts-launcher-window.ui",
        );
        c.gtk_widget_class_bind_template_child_full(
            toGtkWindgetClass(class),
            "search_entry",
            0,
            @offsetOf(TsLauncherWindow, "search_entry"),
        );
        c.gtk_widget_class_bind_template_child_full(
            toGtkWindgetClass(class),
            "list_box",
            0,
            @offsetOf(TsLauncherWindow, "list_box"),
        );
        c.gtk_widget_class_bind_template_child_full(
            toGtkWindgetClass(class),
            "scrolled_window",
            0,
            @offsetOf(TsLauncherWindow, "scrolled_window"),
        );
        c.gtk_widget_class_bind_template_callback_full(
            toGtkWindgetClass(class),
            "onKeyPressed",
            @ptrCast(&onKeyPressed),
        );
        c.gtk_widget_class_bind_template_callback_full(
            toGtkWindgetClass(class),
            "onSearchChanged",
            @ptrCast(&onSearchChanged),
        );
        c.gtk_widget_class_bind_template_callback_full(
            toGtkWindgetClass(class),
            "onActivated",
            @ptrCast(&onActivated),
        );
    }

    fn getParentClass() *c.AdwApplicationWindowClass {
        return @as(
            *c.AdwApplicationWindowClass,
            @alignCast(
                @ptrCast(
                    c.g_type_class_peek(
                        c.adw_application_window_get_type(),
                    ),
                ),
            ),
        );
    }

    fn toObjectClass(class: *anyopaque) *c.GObjectClass {
        return @as(*c.GObjectClass, @alignCast(@ptrCast(class)));
    }

    fn toGtkWindgetClass(class: *anyopaque) *c.GtkWidgetClass {
        return @as(*c.GtkWidgetClass, @alignCast(@ptrCast(class)));
    }

    fn dispose(self: *Self) callconv(.C) void {
        c.gtk_widget_dispose_template(@ptrCast(self), G_TYPE);
        if (toObjectClass(getParentClass()).*.dispose) |parent_dispose| {
            parent_dispose(@ptrCast(self));
        }
        c.g_object_unref(self.model);
    }

    fn finalize(self: *Self) callconv(.C) void {
        if (toObjectClass(getParentClass()).*.finalize) |parent_finalize| {
            parent_finalize(@ptrCast(self));
        }
    }

    fn init(self: *Self) callconv(.C) void {
        c.gtk_widget_init_template(@ptrCast(self));
        self.model = TsModel.new(allocator) catch @panic("out of memory");
        c.gtk_list_box_bind_model(
            self.list_box,
            @ptrCast(self.model),
            @ptrCast(&TsListItem.new),
            null,
            null,
        );
        const shortcut_controller = c.gtk_shortcut_controller_new();
        const text = c.gtk_editable_get_delegate(@ptrCast(self.search_entry));
        c.gtk_widget_add_controller(@alignCast(@ptrCast(text)), shortcut_controller);
        const close_shortcut = c.gtk_shortcut_new(
            c.gtk_shortcut_trigger_parse_string("Escape"),
            c.gtk_callback_action_new(@ptrCast(&closeShortcut), @ptrCast(self), null),
        );
        c.gtk_shortcut_controller_add_shortcut(@ptrCast(shortcut_controller), close_shortcut);
        const confirm_shortcut = c.gtk_shortcut_new(
            c.gtk_shortcut_trigger_parse_string("<Control>y"),
            c.gtk_callback_action_new(@ptrCast(&confirmShortcut), @ptrCast(self), null),
        );
        c.gtk_shortcut_controller_add_shortcut(@ptrCast(shortcut_controller), confirm_shortcut);
        const next_shortcut = c.gtk_shortcut_new(
            c.gtk_shortcut_trigger_parse_string("<Control>n"),
            c.gtk_callback_action_new(@ptrCast(&nextShortcut), @ptrCast(self), null),
        );
        c.gtk_shortcut_controller_add_shortcut(@ptrCast(shortcut_controller), next_shortcut);
        const previous_shortcut = c.gtk_shortcut_new(
            c.gtk_shortcut_trigger_parse_string("<Control>p"),
            c.gtk_callback_action_new(@ptrCast(&previousShortcut), @ptrCast(self), null),
        );
        c.gtk_shortcut_controller_add_shortcut(@ptrCast(shortcut_controller), previous_shortcut);
        const row = c.gtk_list_box_get_row_at_index(@ptrCast(self.list_box), 0);
        c.gtk_list_box_select_row(@ptrCast(self.list_box), row);
        _ = c.gtk_widget_grab_focus(@alignCast(@ptrCast(text)));
    }

    fn confirmShortcut(widget: *c.GtkWidget, _: *c.GVariant, window: *Self) callconv(.C) bool {
        _ = onActivated(window, @ptrCast(widget));
        return true;
    }

    fn closeShortcut(_: *c.GtkWidget, _: *c.GVariant, window: *Self) callconv(.C) bool {
        c.gtk_window_close(@ptrCast(window));
        return true;
    }

    fn wrap(value: i32, min_value: i32, max_value: i32) i32 {
        const range_size = max_value - min_value;
        return @mod((value - min_value), range_size) + min_value;
    }

    fn ajustScroll(self: *Self) void {
        const row = c.gtk_list_box_get_selected_row(@ptrCast(self.list_box));
        var rect = c.graphene_rect_t{};
        _ = c.gtk_widget_compute_bounds(@ptrCast(row), @alignCast(@ptrCast(self.scrolled_window)), &rect);
        const top = rect.origin.y;
        const bottom = top + rect.size.height;
        const adjustment = c.gtk_scrolled_window_get_vadjustment(self.scrolled_window);
        const page_size = c.gtk_adjustment_get_page_size(adjustment);
        const current = c.gtk_adjustment_get_value(adjustment);
        if (bottom > page_size) {
            c.gtk_adjustment_set_value(adjustment, bottom - page_size + current);
        } else if (top < 0) {
            c.gtk_adjustment_set_value(adjustment, current + top);
        }
    }

    fn nextShortcut(_: *c.GtkWidget, _: *c.GVariant, window: *Self) callconv(.C) bool {
        const row = c.gtk_list_box_get_selected_row(@ptrCast(window.list_box));
        const index = c.gtk_list_box_row_get_index(row);
        const n_rows = c.g_list_model_get_n_items(@ptrCast(window.model));
        const next = c.gtk_list_box_get_row_at_index(
            window.list_box,
            wrap(index + 1, 0, @intCast(n_rows)),
        );
        c.gtk_list_box_select_row(window.list_box, next);
        window.ajustScroll();
        return true;
    }

    fn previousShortcut(_: *c.GtkWidget, _: *c.GVariant, window: *Self) callconv(.C) bool {
        const row = c.gtk_list_box_get_selected_row(@ptrCast(window.list_box));
        const index = c.gtk_list_box_row_get_index(row);
        const n_rows = c.g_list_model_get_n_items(@ptrCast(window.model));
        const next = c.gtk_list_box_get_row_at_index(
            window.list_box,
            wrap(index - 1, 0, @intCast(n_rows)),
        );
        c.gtk_list_box_select_row(window.list_box, next);
        window.ajustScroll();
        return true;
    }

    fn onActivated(self: *Self, _: *c.GObject) callconv(.C) bool {
        if (c.gtk_list_box_get_selected_row(self.list_box)) |selected| {
            const pos: u32 = @intCast(c.gtk_list_box_row_get_index(selected));
            const app_info: *c.GAppInfo = @ptrCast(c.g_list_model_get_item(@ptrCast(self.model), pos));
            defer c.g_object_unref(@ptrCast(app_info));
            _ = c.g_app_info_launch(app_info, null, null, null);
            c.gtk_window_close(@ptrCast(self));
        }
        return true;
    }

    fn onKeyPressed(
        self: *Self,
        _: u32,
        _: u32,
        _: c.GdkModifierType,
        controller: *c.GtkEventControllerKey,
    ) callconv(.C) bool {
        const text = c.gtk_editable_get_delegate(@ptrCast(self.search_entry));
        _ = c.gtk_widget_grab_focus(@alignCast(@ptrCast(text)));
        _ = c.gtk_event_controller_key_forward(
            @ptrCast(controller),
            @alignCast(@ptrCast(text)),
        );
        return false;
    }

    fn onSearchChanged(self: *Self, entry: *c.GtkSearchEntry) callconv(.C) bool {
        const filter: []const u8 = std.mem.span(c.gtk_editable_get_text(@ptrCast(entry)));
        self.model.setFilter(filter) catch @panic("out of memory");
        const row = c.gtk_list_box_get_row_at_index(@ptrCast(self.list_box), 0);
        c.gtk_list_box_select_row(@ptrCast(self.list_box), row);
        const adjustment = c.gtk_scrolled_window_get_vadjustment(self.scrolled_window);
        c.gtk_adjustment_set_value(adjustment, 0);
        return false;
    }

    pub fn new() callconv(.C) *Self {
        register();
        return @alignCast(@ptrCast(c.g_object_new(G_TYPE, null)));
    }

    fn register() void {
        if (G_TYPE != 0) return;
        G_TYPE = c.g_type_register_static_simple(
            c.adw_application_window_get_type(),
            "TsLauncherWindow",
            @sizeOf(TsLauncherWindowClass),
            @ptrCast(&classInit),
            @sizeOf(TsLauncherWindow),
            @ptrCast(&init),
            c.G_TYPE_FLAG_FINAL,
        );
    }
};
