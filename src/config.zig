const common = @import("common.zig");

const c = common.c;

const LogLevel = common.LogLevel;

pub const debug = true;
pub const enable_validation_layers = debug;
pub const validation_layers: []const []const u8 = &[_][]const u8{
    "VK_LAYER_KHRONOS_validation",
};
pub const device_extensions: []const []const u8 = &[_][]const u8{
    c.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
};
pub const max_frames_in_flight = 2;
pub const log_level_default = LogLevel.Warn;
pub const log_level = if (debug) LogLevel.Debug else log_level_default;

pub const app_name = "my-vulkan";
pub const w_width = 640;
pub const w_height = 480;
