const std = @import("std");

const common = @import("common.zig");
const v_layers = @import("v_layers.zig");
const config = @import("config.zig");
const logger = @import("logger.zig");

const c = common.c;

const ArrayList = std.ArrayList;
const VulkanError = common.VulkanError;
const QueueFamilyIndices = common.QueueFamilyIndices;

const allocator = std.heap.page_allocator;

pub fn create_logical_device(physical_device: c.VkPhysicalDevice, indices: QueueFamilyIndices) !c.VkDevice {
    var queue_create_infos: ArrayList(c.VkDeviceQueueCreateInfo) = .{};
    defer queue_create_infos.clearAndFree(allocator);
    var queue_priority: f32 = 1.0;

    // graphics family
    {
        const queue_create_info: c.VkDeviceQueueCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .queueFamilyIndex = indices.graphics_family,
            .queueCount = 1,
            .pQueuePriorities = &queue_priority,
        };
        try queue_create_infos.append(allocator, queue_create_info);
    }

    // present family
    {
        const queue_create_info: c.VkDeviceQueueCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .queueFamilyIndex = indices.present_family,
            .queueCount = 1,
            .pQueuePriorities = &queue_priority,
        };
        try queue_create_infos.append(allocator, queue_create_info);
    }

    var features: c.VkPhysicalDeviceFeatures = .{};

    var device_create_info = c.VkDeviceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pQueueCreateInfos = queue_create_infos.items.ptr,
        .pEnabledFeatures = &features,
        .queueCreateInfoCount = @intCast(queue_create_infos.items.len),
        .enabledExtensionCount = 0,
    };

    // this is no longer necessary, but it is good to do this for backwards compatability
    if (config.enable_validation_layers) {
        device_create_info.enabledLayerCount = config.validation_layers.len;
        device_create_info.ppEnabledLayerNames = @ptrCast(config.validation_layers.ptr);
    } else {
        device_create_info.enabledLayerCount = 0;
    }

    var device: c.VkDevice = undefined;
    if (c.vkCreateDevice(physical_device, &device_create_info, null, &device) != c.VK_SUCCESS)
        return VulkanError.CreateDeviceFailure;

    return device;
}
