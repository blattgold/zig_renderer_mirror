const std = @import("std");

const config = @import("config.zig");
const logger = @import("logger.zig");
const common = @import("common.zig");
const p_device = @import("p_device.zig");
const v_layers = @import("v_layers.zig");
const instance_mod = @import("instance.zig");
const device_mod = @import("device.zig");

const c = common.c;

const VulkanError = common.VulkanError;
const ArrayList = std.ArrayList;

/// allocates memory, on you to free it
fn get_required_extensions(allocator: std.mem.Allocator) ![][*c]const u8 {
    var extension_count_sdl: u32 = undefined;
    const extensions_sdl = c.SDL_Vulkan_GetInstanceExtensions(&extension_count_sdl);

    var extensions: ArrayList([*c]const u8) = .{};
    try extensions.appendSlice(allocator, extensions_sdl[0..extension_count_sdl]);

    if (config.enable_validation_layers)
        try extensions.append(allocator, c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME);

    return try extensions.toOwnedSlice(allocator);
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    _ = c.SDL_Init(c.SDL_INIT_VIDEO);
    _ = c.SDL_Vulkan_LoadLibrary(null);
    defer c.SDL_Quit();
    //const window: ?*c.SDL_Window = c.SDL_CreateWindow(APP_NAME, W_WIDTH, W_HEIGHT, c.SDL_WINDOW_VULKAN);

    const extensions = try get_required_extensions(allocator);
    const instance = try instance_mod.create_instance(extensions);
    allocator.free(extensions);
    defer c.vkDestroyInstance(instance, null);

    const debug_messenger = if (config.enable_validation_layers) try v_layers.setup_debug_messenger(instance) else null;
    defer if (config.enable_validation_layers)
        v_layers.destroy_debug_utils_messenger_ext(instance, debug_messenger, null)
    else {};

    const device_result = try p_device.select_physical_device(instance);

    _ = try device_mod.create_logical_device(device_result.physical_device, device_result.indices);
    // defer c.vkDestroyDevice(device, null);
}
