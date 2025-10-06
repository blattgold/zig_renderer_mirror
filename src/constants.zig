const common = @import("common.zig");

const LogLevel = common.LogLevel;

pub const DEBUG = true;
pub const ENABLE_VALIDATION_LAYERS = DEBUG;
pub const VALIDATION_LAYERS: []const []const u8 = &[_][]const u8{
    "VK_LAYER_KHRONOS_validation",
};
pub const LOG_LEVEL_DEFAULT = LogLevel.Warn;
pub const LOG_LEVEL = if (DEBUG) LogLevel.Debug else LOG_LEVEL_DEFAULT;

pub const APP_NAME = "my-vulkan";
pub const W_WIDTH = 640;
pub const W_HEIGHT = 480;
