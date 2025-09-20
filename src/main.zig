const std = @import("std");
const gio = @import("gio");
const intl = @import("libintl");

const GApplicationProvider = @import("g_application_provider.zig");
const TsApplication = @import("ts-application.zig").TsApplication;

const VERSION = "0.1.0";
const APP_ID = "com.github.wosteimer.tiny-shell";

const allocator = std.heap.page_allocator;

pub fn main() !void {
    intl.setTextDomain(APP_ID);
    var env = try std.process.getEnvMap(allocator);
    if (env.get("TS_DEBUG_LOCALE_DIR")) |dir| {
        intl.bindTextDomain(APP_ID, @ptrCast(dir));
    }
    env.deinit();
    var application_provider = GApplicationProvider.init(allocator);
    const app = TsApplication.new(allocator, &application_provider.interface, APP_ID, VERSION);
    _ = gio.Application.run(app.as(gio.Application), @intCast(std.os.argv.len), std.os.argv.ptr);
}
