const gtk = @import("gtk");
const c = @cImport({
    @cInclude("gtk-layer-shell/gtk-layer-shell.h");
});

pub const Layer = enum(u32) {
    background = c.GTK_LAYER_SHELL_LAYER_BACKGROUND,
    bottom = c.GTK_LAYER_SHELL_LAYER_BOTTOM,
    top = c.GTK_LAYER_SHELL_LAYER_TOP,
    overlay = c.GTK_LAYER_SHELL_LAYER_OVERLAY,
};

pub const Edge = enum(u32) {
    left = c.GTK_LAYER_SHELL_EDGE_LEFT,
    right = c.GTK_LAYER_SHELL_EDGE_RIGHT,
    top = c.GTK_LAYER_SHELL_EDGE_TOP,
    bottom = c.GTK_LAYER_SHELL_EDGE_BOTTOM,
};

pub const KeyboardMode = enum(u32) {
    none = c.GTK_LAYER_SHELL_KEYBOARD_MODE_NONE,
    exclusive = c.GTK_LAYER_SHELL_KEYBOARD_MODE_EXCLUSIVE,
    on_demand = c.GTK_LAYER_SHELL_KEYBOARD_MODE_ON_DEMAND,
};

extern fn gtk_layer_init_for_window(window: *gtk.Window) void;
pub const initForWindow = gtk_layer_init_for_window;

extern fn gtk_layer_set_layer(window: *gtk.Window, layer: Layer) void;
pub const setLayer = gtk_layer_set_layer;

extern fn gtk_layer_set_anchor(
    window: *gtk.Window,
    edge: Edge,
    ancher_to_edge: bool,
) void;
pub const setAnchor = gtk_layer_set_anchor;

extern fn gtk_layer_set_keyboard_mode(window: *gtk.Window, mode: KeyboardMode) void;
pub const setKeyboardMode = gtk_layer_set_keyboard_mode;
