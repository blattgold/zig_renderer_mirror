const std = @import("std");

const ArrayList = std.ArrayList;

const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_vulkan.h");
    @cInclude("vulkan/vulkan.h");
});

const DEBUG = true;
const ENABLE_VALIDATION_LAYERS = DEBUG;
const LOG_LEVEL = if (DEBUG) LogLevel.Debug else LogLevel.Warn;
const VALIDATION_LAYERS: []const []const u8 = &[_][]const u8{
    "VK_LAYER_KHRONOS_validation",
};

const APP_NAME = "my-vulkan";
const W_WIDTH = 640;
const W_HEIGHT = 480;

const LogLevel = enum(u2) {
    Debug,
    Info,
    Warn,
    Error,
};

const VulkanError = error{
    InstanceCreationFailure,
    NoSuitableDeviceFound,
    GetRequiredExtensionsFailure,
    EnableValidationLayersFailure,
    SetupDebugMessengerFailure,
};

const QueueFamilyIndices = struct {
    graphics_family: ?u32,

    pub fn isComplete(self: @This()) bool {
        return self.graphics_family != null;
    }
};

fn log(comptime level: LogLevel, comptime msg: []const u8, args: anytype) void {
    if (comptime @intFromEnum(level) >= @intFromEnum(LOG_LEVEL)) {
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

fn checkValidationLayerSupport() !void {
    const allocator = std.heap.page_allocator;

    var layer_count: u32 = undefined;
    if (c.vkEnumerateInstanceLayerProperties(
        &layer_count,
        null,
    ) != c.VK_SUCCESS)
        return VulkanError.EnableValidationLayersFailure;

    var available_layers = try allocator.alloc(c.VkLayerProperties, layer_count);
    defer allocator.free(available_layers);
    if (c.vkEnumerateInstanceLayerProperties(
        &layer_count,
        &available_layers[0],
    ) != c.VK_SUCCESS)
        return VulkanError.EnableValidationLayersFailure;

    for (VALIDATION_LAYERS) |requested_layer_name| {
        var layer_found = false;

        for (available_layers) |available_layer| {
            log(.Debug, "available layer: {s}", .{available_layer.layerName});

            const available_layer_name_len = std.mem.indexOf(
                u8,
                &available_layer.layerName,
                &[1]u8{0},
            ) orelse available_layer.layerName.len;

            if (std.mem.eql(u8, requested_layer_name, available_layer.layerName[0..available_layer_name_len])) {
                log(.Debug, "found requested layer: {s}", .{requested_layer_name});
                layer_found = true;
                break;
            }
        }

        if (!layer_found) {
            log(.Error, "could not find requested layer: {s}", .{requested_layer_name});
            return VulkanError.EnableValidationLayersFailure;
        }
    }
}

fn findQueueFamilyIndices(device: c.VkPhysicalDevice) !QueueFamilyIndices {
    const allocator = std.heap.page_allocator;

    var indices: QueueFamilyIndices = undefined;

    var queueFamilyCount: u32 = 0;
    c.vkGetPhysicalDeviceQueueFamilyProperties(
        device,
        &queueFamilyCount,
        null,
    );

    var queue_families = try allocator.alloc(c.VkQueueFamilyProperties, queueFamilyCount);
    defer allocator.free(queue_families);
    c.vkGetPhysicalDeviceQueueFamilyProperties(
        device,
        &queueFamilyCount,
        &queue_families[0],
    );

    var i: u32 = 0;
    for (queue_families) |queue_family| {
        if (queue_family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0) {
            indices.graphics_family = i;
        }

        if (indices.isComplete()) {
            break;
        }

        i += 1;
    }

    return indices;
}

fn isDeviceSuitable(device: c.VkPhysicalDevice) !bool {
    const indices = try findQueueFamilyIndices(device);

    return indices.isComplete();
}

fn choosePhysicalDevice(instance: c.VkInstance) !c.VkPhysicalDevice {
    var device_count: u32 = 0;
    _ = c.vkEnumeratePhysicalDevices(
        instance,
        &device_count,
        null,
    );

    if (device_count == 0)
        return VulkanError.NoSuitableDeviceFound;

    const MAX_DEVICES = 16;
    var devices: [MAX_DEVICES]c.VkPhysicalDevice = undefined;

    if (c.vkEnumeratePhysicalDevices(
        instance,
        &device_count,
        &devices[0],
    ) != c.VK_SUCCESS)
        return VulkanError.NoSuitableDeviceFound;

    var physical_device: c.VkPhysicalDevice = undefined;
    for (devices) |device| {
        if (try isDeviceSuitable(device)) {
            physical_device = device;
            break;
        }
    }

    if (physical_device == null)
        return VulkanError.NoSuitableDeviceFound;

    log(.Debug, "suitable physical device found: {any}", .{physical_device.?});

    return physical_device.?;
}

fn debugCallback(
    _: c.VkDebugUtilsMessageSeverityFlagBitsEXT,
    _: c.VkDebugUtilsMessageTypeFlagsEXT,
    p_callback_data: [*c]const c.VkDebugUtilsMessengerCallbackDataEXT,
    _: ?*anyopaque,
) callconv(.c) c.VkBool32 {
    std.debug.print("[VULKAN]: {s}\n", .{p_callback_data.*.pMessage});

    return c.VK_FALSE;
}

fn createInstance() !c.VkInstance {
    if (ENABLE_VALIDATION_LAYERS)
        try checkValidationLayerSupport();

    var app_info: c.VkApplicationInfo = .{};

    app_info.sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO;
    app_info.pApplicationName = APP_NAME;
    app_info.applicationVersion = c.VK_MAKE_VERSION(0, 1, 0);
    app_info.pEngineName = "No Engine";
    app_info.engineVersion = c.VK_MAKE_VERSION(1, 0, 0);
    app_info.apiVersion = c.VK_API_VERSION_1_0;

    var inst_info: c.VkInstanceCreateInfo = .{};
    const extensions = try getRequiredExtensions();

    inst_info.sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    inst_info.pApplicationInfo = &app_info;
    inst_info.enabledExtensionCount = @intCast(extensions.len);
    inst_info.ppEnabledExtensionNames = extensions.ptr;

    var debug_create_info: c.VkDebugUtilsMessengerCreateInfoEXT = .{};
    if (ENABLE_VALIDATION_LAYERS) {
        inst_info.enabledLayerCount = VALIDATION_LAYERS.len;
        inst_info.ppEnabledLayerNames = @ptrCast(VALIDATION_LAYERS.ptr);

        populateDebugMessengerCreateInfo(&debug_create_info);
        inst_info.pNext = @ptrCast(&debug_create_info);

        log(.Debug, "enabled validation layers: {any}", .{VALIDATION_LAYERS});
    } else {
        inst_info.enabledLayerCount = 0;
        inst_info.pNext = null;
    }

    var instance: c.VkInstance = undefined;
    if (c.vkCreateInstance(&inst_info, null, &instance) != c.VK_SUCCESS)
        return VulkanError.InstanceCreationFailure;

    log(.Debug, "Instance created successfully", .{});
    return instance;
}

fn createDebugUtilsMessengerEXT(
    instance: c.VkInstance,
    p_create_info: *c.VkDebugUtilsMessengerCreateInfoEXT,
    p_allocator: ?*c.VkAllocationCallbacks,
    p_debug_messenger: *c.VkDebugUtilsMessengerEXT,
) c.VkResult {
    const func: c.PFN_vkCreateDebugUtilsMessengerEXT = @ptrCast(c.vkGetInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT"));
    if (func != null) {
        return func.?(instance, p_create_info, p_allocator, p_debug_messenger);
    } else {
        return c.VK_ERROR_EXTENSION_NOT_PRESENT;
    }
}

fn destroyDebugUtilsMessengerEXT(
    instance: c.VkInstance,
    debug_messenger: c.VkDebugUtilsMessengerEXT,
    p_allocator: ?*c.VkAllocationCallbacks,
) void {
    const func: c.PFN_vkDestroyDebugUtilsMessengerEXT = @ptrCast(c.vkGetInstanceProcAddr(instance, "vkDestroyDebugUtilsMessengerEXT"));
    if (func != null) {
        func.?(instance, debug_messenger, p_allocator);
    }
}

/// allocates memory, on you to free it
fn getRequiredExtensions() ![][*c]const u8 {
    const allocator = std.heap.page_allocator;

    var extension_count_sdl: u32 = undefined;
    const extensions_sdl = c.SDL_Vulkan_GetInstanceExtensions(&extension_count_sdl);

    var extensions: ArrayList([*c]const u8) = .{};
    try extensions.appendSlice(allocator, extensions_sdl[0..extension_count_sdl]);

    if (ENABLE_VALIDATION_LAYERS)
        try extensions.append(allocator, c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME);

    return try extensions.toOwnedSlice(allocator);
}

fn populateDebugMessengerCreateInfo(info: *c.VkDebugUtilsMessengerCreateInfoEXT) void {
    info.flags = 0;
    info.sType = c.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT;
    info.messageSeverity =
        c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT |
        c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT |
        c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT;
    info.messageType =
        c.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT |
        c.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT |
        c.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT;
    info.pfnUserCallback = debugCallback;
    info.pUserData = null; // custom data to pass to callback
}

fn setupDebugMessenger(instance: c.VkInstance) !c.VkDebugUtilsMessengerEXT {
    if (!ENABLE_VALIDATION_LAYERS) return;

    var info: c.VkDebugUtilsMessengerCreateInfoEXT = undefined;
    populateDebugMessengerCreateInfo(&info);

    var debug_messenger: c.VkDebugUtilsMessengerEXT = undefined;
    if (createDebugUtilsMessengerEXT(instance, &info, null, &debug_messenger) != c.VK_SUCCESS)
        return VulkanError.SetupDebugMessengerFailure;

    return debug_messenger;
}

pub fn main() !void {
    //const allocator = std.heap.page_allocator;

    _ = c.SDL_Init(c.SDL_INIT_VIDEO);
    _ = c.SDL_Vulkan_LoadLibrary(null);
    //const window: ?*c.SDL_Window = c.SDL_CreateWindow(APP_NAME, W_WIDTH, W_HEIGHT, c.SDL_WINDOW_VULKAN);

    const instance = try createInstance();
    const debug_messenger = try setupDebugMessenger(instance);

    // physical device
    _ = try choosePhysicalDevice(instance);

    cleanup(instance, debug_messenger);
}

fn cleanup(
    instance: c.VkInstance,
    debug_messenger: c.VkDebugUtilsMessengerEXT,
) void {
    if (ENABLE_VALIDATION_LAYERS) {
        destroyDebugUtilsMessengerEXT(instance, debug_messenger, null);
    }

    c.vkDestroyInstance(instance, null);
    c.SDL_Quit();
}
