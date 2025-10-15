const std = @import("std");
const common = @import("common.zig");
const config = @import("config.zig");
const logger = @import("logger.zig");

const c = common.c;

const VulkanError = common.VulkanError;

pub fn checkValidationLayerSupport() !void {
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

    for (config.validation_layers) |requested_layer_name| {
        var layer_found = false;

        for (available_layers) |available_layer| {
            logger.log(.Debug, "available layer: {s}", .{available_layer.layerName});

            if (std.mem.eql(
                u8,
                requested_layer_name,
                std.mem.sliceTo(&available_layer.layerName, 0),
            )) {
                logger.log(.Debug, "found requested layer: {s}", .{requested_layer_name});
                layer_found = true;
                break;
            }
        }

        if (!layer_found) {
            logger.log(.Error, "could not find requested layer: {s}", .{requested_layer_name});
            return VulkanError.EnableValidationLayersFailure;
        }
    }
}

fn debugCallback(
    _: c.VkDebugUtilsMessageSeverityFlagBitsEXT,
    _: c.VkDebugUtilsMessageTypeFlagsEXT,
    callback_data: [*c]const c.VkDebugUtilsMessengerCallbackDataEXT,
    _: ?*anyopaque,
) callconv(.c) c.VkBool32 {
    std.debug.print("[VULKAN]: {s}\n", .{callback_data.*.pMessage});

    return c.VK_FALSE;
}

fn createDebugUtilsMessengerExt(
    instance: c.VkInstance,
    create_info: *c.VkDebugUtilsMessengerCreateInfoEXT,
    vk_allocator: ?*c.VkAllocationCallbacks,
    debug_messenger: *c.VkDebugUtilsMessengerEXT,
) c.VkResult {
    const func: c.PFN_vkCreateDebugUtilsMessengerEXT = @ptrCast(c.vkGetInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT"));
    if (func != null) {
        return func.?(instance, create_info, vk_allocator, debug_messenger);
    } else {
        return c.VK_ERROR_EXTENSION_NOT_PRESENT;
    }
}

pub fn destroyDebugUtilsMessengerExt(
    instance: c.VkInstance,
    debug_messenger: c.VkDebugUtilsMessengerEXT,
    vk_allocator: ?*c.VkAllocationCallbacks,
) void {
    const func: c.PFN_vkDestroyDebugUtilsMessengerEXT = @ptrCast(c.vkGetInstanceProcAddr(instance, "vkDestroyDebugUtilsMessengerEXT"));
    if (func != null) {
        func.?(instance, debug_messenger, vk_allocator);
    }
}

pub fn createDebugUtilsMessengerCreateInfoExt() c.VkDebugUtilsMessengerCreateInfoEXT {
    return c.VkDebugUtilsMessengerCreateInfoEXT{
        .flags = 0,
        .sType = c.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
        .messageSeverity = c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT |
            c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT |
            c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
        .messageType = c.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT |
            c.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT |
            c.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
        .pfnUserCallback = debugCallback,
        .pUserData = null, // custom user data pointer
    };
}

pub fn createDebugMessenger(instance: c.VkInstance) !c.VkDebugUtilsMessengerEXT {
    var info = createDebugUtilsMessengerCreateInfoExt();
    var debug_messenger: c.VkDebugUtilsMessengerEXT = null;
    if (createDebugUtilsMessengerExt(instance, &info, null, &debug_messenger) != c.VK_SUCCESS)
        return VulkanError.SetupDebugMessengerFailure;

    return debug_messenger;
}
