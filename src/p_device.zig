const std = @import("std");
const common = @import("common.zig");
const logger = @import("logger.zig");

const c = common.c;

const VulkanError = common.VulkanError;
const QueueFamilyIndices = common.QueueFamilyIndices;

const ChoosePhysicalDeviceResult = struct {
    indices: QueueFamilyIndices,
    physical_device: c.VkPhysicalDevice,
};

pub fn find_physical_devices(
    allocator: std.mem.Allocator,
    instance: c.VkInstance,
) ![]c.VkPhysicalDevice {
    var device_count: u32 = 0;
    _ = c.vkEnumeratePhysicalDevices(
        instance,
        &device_count,
        null,
    );

    if (device_count == 0)
        return VulkanError.NoPhysicalDevices;

    var devices = try allocator.alloc(c.VkPhysicalDevice, device_count);
    if (c.vkEnumeratePhysicalDevices(
        instance,
        &device_count,
        &devices[0],
    ) != c.VK_SUCCESS)
        return VulkanError.NoPhysicalDevices;

    return devices;
}

pub fn find_suitable_physical_device(
    devices: []c.VkPhysicalDevice,
) !ChoosePhysicalDeviceResult {
    var device: c.VkPhysicalDevice = undefined;
    var indices: QueueFamilyIndices = undefined;

    for (devices) |d| {
        const d_i = try find_queue_family_indices(d);

        if (is_device_suitable(d_i)) {
            device = d;
            indices = d_i;
            break;
        }
    }

    if (device == null)
        return VulkanError.NoSuitablePhysicalDevice;

    return .{
        .indices = indices,
        .physical_device = device,
    };
}

// helper for find_suitable_physical_device
fn is_device_suitable(
    indices: QueueFamilyIndices,
) bool {
    return indices.is_complete();
}

pub fn select_physical_device(instance: c.VkInstance) !ChoosePhysicalDeviceResult {
    const allocator = std.heap.page_allocator;

    const devices = try find_physical_devices(allocator, instance);
    defer allocator.free(devices);

    const result = try find_suitable_physical_device(devices);

    logger.log(.Debug, "suitable physical device found: 0x{x}", .{@intFromPtr(result.physical_device)});
    logger.log(.Debug, "with: graphics_family_i: {}", .{result.indices.graphics_family.?});

    return result;
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

        if (indices.is_complete()) {
            break;
        }

        i += 1;
    }

    return indices;
}
