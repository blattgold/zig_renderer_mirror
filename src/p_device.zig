const std = @import("std");
const common = @import("common.zig");
const logger = @import("logger.zig");

const c = common.c;

const VulkanError = common.VulkanError;
const QueueFamilyIndices = common.QueueFamilyIndices;

const PDeviceResult = struct {
    indices: QueueFamilyIndices,
    physical_device: c.VkPhysicalDevice,
};

/// returns a list with all available physical devices.
/// physical_device list must be manually freed.
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

/// a device is suitable if at least one queue_family exists that has all the necessary capabilites.
/// return value is a struct that contains QueueFamilyIndices + the PhysicalDevice.
pub fn find_suitable_physical_device(
    devices: []c.VkPhysicalDevice,
) !PDeviceResult {
    const allocator = std.heap.page_allocator;

    var device: c.VkPhysicalDevice = undefined;
    var indices: QueueFamilyIndices = undefined;

    for (devices) |d| {
        const d_queue_families = try find_queue_families(allocator, d);
        defer allocator.free(d_queue_families);
        const d_queue_family_indices = try select_queue_family_indices(d_queue_families);

        if (d_queue_family_indices.is_complete()) {
            device = d;
            indices = d_queue_family_indices;
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

pub fn find_queue_families(
    allocator: std.mem.Allocator,
    device: c.VkPhysicalDevice,
) ![]c.VkQueueFamilyProperties {
    var queueFamilyCount: u32 = 0;
    c.vkGetPhysicalDeviceQueueFamilyProperties(
        device,
        &queueFamilyCount,
        null,
    );

    var queue_families = try allocator.alloc(c.VkQueueFamilyProperties, queueFamilyCount);
    c.vkGetPhysicalDeviceQueueFamilyProperties(
        device,
        &queueFamilyCount,
        &queue_families[0],
    );
    return queue_families;
}

pub fn select_queue_family_indices(queue_families: []c.VkQueueFamilyProperties) !QueueFamilyIndices {
    var indices: QueueFamilyIndices = undefined;

    for (queue_families, 0..) |queue_family, i| {
        if (queue_family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0) {
            std.debug.assert(i < 2 ^ 32);

            indices.graphics_family = @intCast(i);
        }

        if (indices.is_complete()) {
            break;
        }
    }

    if (!indices.is_complete())
        return VulkanError.NoSuitablePhysicalDevice;

    return indices;
}
