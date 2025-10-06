const std = @import("std");
const common = @import("common.zig");
const logger = @import("logger.zig");

const c = common.c;

const VulkanError = common.VulkanError;
const QueueFamilyIndices = common.QueueFamilyIndices;

pub fn choose_physical_device(instance: c.VkInstance) !c.VkPhysicalDevice {
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
        if (try is_device_suitable(device)) {
            physical_device = device;
            break;
        }
    }

    if (physical_device == null)
        return VulkanError.NoSuitableDeviceFound;

    logger.log(.Debug, "suitable physical device found: {any}", .{physical_device.?});

    return physical_device.?;
}

pub fn is_device_suitable(device: c.VkPhysicalDevice) !bool {
    const indices = try find_queue_family_indices(device);

    return indices.isComplete();
}

pub fn find_queue_family_indices(device: c.VkPhysicalDevice) !QueueFamilyIndices {
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
