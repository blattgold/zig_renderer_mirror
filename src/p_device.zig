const std = @import("std");
const common = @import("common.zig");
const logger = @import("logger.zig");

const c = common.c;

const VulkanError = common.VulkanError;
const QueueFamilyIndices = common.QueueFamilyIndices;
const QueueFamilyIndicesOpt = common.QueueFamilyIndicesOpt;

const PDeviceResult = struct {
    indices: QueueFamilyIndices,
    physical_device: c.VkPhysicalDevice,
};

/// returns a list with all available physical devices.
/// physical_device list must be manually freed.
pub fn find_physical_devices(
    allocator: std.mem.Allocator,
    vk_instance: c.VkInstance,
) ![]c.VkPhysicalDevice {
    var physical_device_count: u32 = 0;
    _ = c.vkEnumeratePhysicalDevices(
        vk_instance,
        &physical_device_count,
        null,
    );

    if (physical_device_count == 0)
        return VulkanError.NoPhysicalDevices;

    var physical_devices = try allocator.alloc(c.VkPhysicalDevice, physical_device_count);
    if (c.vkEnumeratePhysicalDevices(
        vk_instance,
        &physical_device_count,
        &physical_devices[0],
    ) != c.VK_SUCCESS)
        return VulkanError.NoPhysicalDevices;

    return physical_devices;
}

/// a device is suitable if at least one queue_family exists that has all the necessary capabilites.
/// return value is a struct that contains QueueFamilyIndices + the PhysicalDevice.
pub fn select_suitable_physical_device(
    physical_devices: []c.VkPhysicalDevice,
) !PDeviceResult {
    const allocator = std.heap.page_allocator;

    var selected_physical_device: c.VkPhysicalDevice = undefined;
    var selected_indices: ?QueueFamilyIndices = undefined;

    for (physical_devices) |physical_device| {
        const queue_families = try find_queue_families(allocator, physical_device);
        defer allocator.free(queue_families);
        const indices = try select_queue_family_indices(queue_families);

        if (indices != null) {
            selected_physical_device = physical_device;
            selected_indices = indices;
            break;
        }
    }

    if (selected_physical_device == null or selected_indices == null)
        return VulkanError.NoSuitablePhysicalDevice;

    return .{
        .indices = selected_indices.?,
        .physical_device = selected_physical_device,
    };
}

pub fn find_queue_families(
    allocator: std.mem.Allocator,
    physical_device: c.VkPhysicalDevice,
) ![]c.VkQueueFamilyProperties {
    var queueFamilyCount: u32 = 0;
    c.vkGetPhysicalDeviceQueueFamilyProperties(
        physical_device,
        &queueFamilyCount,
        null,
    );

    var queue_families = try allocator.alloc(c.VkQueueFamilyProperties, queueFamilyCount);
    c.vkGetPhysicalDeviceQueueFamilyProperties(
        physical_device,
        &queueFamilyCount,
        &queue_families[0],
    );
    return queue_families;
}

pub fn select_queue_family_indices(queue_families: []c.VkQueueFamilyProperties) !?QueueFamilyIndices {
    var indices_opt: QueueFamilyIndicesOpt = undefined;

    for (queue_families, 0..) |queue_family, i| {
        if (queue_family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0) {
            std.debug.assert(i < 2 ^ 32);

            indices_opt.graphics_family = @intCast(i);
        }

        if (indices_opt.is_complete()) {
            break;
        }
    }

    if (!indices_opt.is_complete())
        return VulkanError.NoSuitablePhysicalDevice;

    return indices_opt.to_queue_family_indices();
}
