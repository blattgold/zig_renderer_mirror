const std = @import("std");

const constants = @import("constants.zig");
const logger = @import("logger.zig");
const common = @import("common.zig");
const choose_p_device = @import("choose_p_device.zig");
const v_layers = @import("v_layers.zig");

const c = common.c;

const VulkanError = common.VulkanError;
const ArrayList = std.ArrayList;

fn create_instance() !c.VkInstance {
    if (constants.ENABLE_VALIDATION_LAYERS)
        try v_layers.check_validation_layer_support();

    var app_info: c.VkApplicationInfo = .{};

    app_info.sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO;
    app_info.pApplicationName = constants.APP_NAME;
    app_info.applicationVersion = c.VK_MAKE_VERSION(0, 1, 0);
    app_info.pEngineName = "No Engine";
    app_info.engineVersion = c.VK_MAKE_VERSION(1, 0, 0);
    app_info.apiVersion = c.VK_API_VERSION_1_0;

    var inst_info: c.VkInstanceCreateInfo = .{};
    const extensions = try get_required_extensions();

    inst_info.sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    inst_info.pApplicationInfo = &app_info;
    inst_info.enabledExtensionCount = @intCast(extensions.len);
    inst_info.ppEnabledExtensionNames = extensions.ptr;

    var debug_create_info: c.VkDebugUtilsMessengerCreateInfoEXT = .{};
    if (constants.ENABLE_VALIDATION_LAYERS) {
        inst_info.enabledLayerCount = constants.VALIDATION_LAYERS.len;
        inst_info.ppEnabledLayerNames = @ptrCast(constants.VALIDATION_LAYERS.ptr);

        v_layers.populate_debug_messeneger_create_info(&debug_create_info);
        inst_info.pNext = @ptrCast(&debug_create_info);

        logger.log(.Debug, "enabled validation layers: {any}", .{constants.VALIDATION_LAYERS});
    } else {
        inst_info.enabledLayerCount = 0;
        inst_info.pNext = null;
    }

    var instance: c.VkInstance = undefined;
    if (c.vkCreateInstance(&inst_info, null, &instance) != c.VK_SUCCESS)
        return VulkanError.InstanceCreationFailure;

    logger.log(.Debug, "Instance created successfully", .{});
    return instance;
}

/// allocates memory, on you to free it
fn get_required_extensions() ![][*c]const u8 {
    const allocator = std.heap.page_allocator;

    var extension_count_sdl: u32 = undefined;
    const extensions_sdl = c.SDL_Vulkan_GetInstanceExtensions(&extension_count_sdl);

    var extensions: ArrayList([*c]const u8) = .{};
    try extensions.appendSlice(allocator, extensions_sdl[0..extension_count_sdl]);

    if (constants.ENABLE_VALIDATION_LAYERS)
        try extensions.append(allocator, c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME);

    return try extensions.toOwnedSlice(allocator);
}

pub fn main() !void {
    //const allocator = std.heap.page_allocator;

    _ = c.SDL_Init(c.SDL_INIT_VIDEO);
    _ = c.SDL_Vulkan_LoadLibrary(null);
    defer c.SDL_Quit();
    //const window: ?*c.SDL_Window = c.SDL_CreateWindow(APP_NAME, W_WIDTH, W_HEIGHT, c.SDL_WINDOW_VULKAN);

    const instance = try create_instance();
    defer c.vkDestroyInstance(instance, null);

    const debug_messenger = try v_layers.setup_debug_messenger(instance);

    // physical device
    _ = try choose_p_device.choose_physical_device(instance);

    cleanup(instance, debug_messenger);
}

fn cleanup(
    instance: c.VkInstance,
    debug_messenger: c.VkDebugUtilsMessengerEXT,
) void {
    if (constants.ENABLE_VALIDATION_LAYERS) {
        v_layers.destroy_debug_utils_messenger_ext(instance, debug_messenger, null);
    }

    c.vkDestroyInstance(instance, null);
    c.SDL_Quit();
}
