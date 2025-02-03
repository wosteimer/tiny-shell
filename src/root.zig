const std = @import("std");

export fn hello() void {
    std.debug.print("hello\n", .{});
}
