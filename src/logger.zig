const std = @import("std");
const common = @import("common.zig");
const constants = @import("./constants.zig");

const LogLevel = common.LogLevel;

pub fn log(comptime level: LogLevel, comptime msg: []const u8, args: anytype) void {
    if (comptime @intFromEnum(level) >= @intFromEnum(constants.LOG_LEVEL)) {
        std.debug.print("[{s}]: ", .{switch (level) {
            .Debug => "DEBUG",
            .Info => "INFO",
            .Warn => "WARN",
            .Error => "ERROR",
        }});
        std.debug.print(msg, args);
        std.debug.print("\n", .{});
    }
}
