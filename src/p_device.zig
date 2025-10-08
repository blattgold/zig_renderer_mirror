const std = @import("std");
const common = @import("common.zig");
const logger = @import("logger.zig");

const c = common.c;

const VulkanError = common.VulkanError;
const QueueFamilyIndices = common.QueueFamilyIndices;
const QueueFamilyIndicesOpt = common.QueueFamilyIndicesOpt;

pub const PDeviceResult = struct {
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
    vk_surface: c.VkSurfaceKHR,
) !PDeviceResult {
    const allocator = std.heap.page_allocator;

    var selected_physical_device: c.VkPhysicalDevice = null;
    var selected_indices: ?QueueFamilyIndices = null;

    for (physical_devices) |physical_device| {
        const queue_families = try find_queue_families(allocator, physical_device);
        defer allocator.free(queue_families);
        const indices = select_queue_family_indices(
            physical_device,
            queue_families,
            vk_surface,
        );

        const is_suitable = indices != null and supports_required_device_extensions(physical_device);
        if (is_suitable) {
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

// helper for select_suitable_physical_device
// returns true if all the required extensions are supported
fn supports_required_device_extensions(_: c.VkPhysicalDevice) bool {
    return true;
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

pub fn select_queue_family_indices(
    physical_device: c.VkPhysicalDevice,
    queue_families: []c.VkQueueFamilyProperties,
    vk_surface: c.VkSurfaceKHR,
) ?QueueFamilyIndices {
    var indices_opt: QueueFamilyIndicesOpt = .{ .graphics_family = null, .present_family = null };

    for (queue_families, 0..) |queue_family, i| {
        // sanity check, no device will ever have this many queue families.
        // if it does, something really weird occured.
        std.debug.assert(i < 4294967296);

        var present_support: c.VkBool32 = undefined;
        _ = c.vkGetPhysicalDeviceSurfaceSupportKHR(physical_device, @intCast(i), vk_surface, &present_support);

        if (queue_family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0) {
            indices_opt.graphics_family = @intCast(i);
        }

        if (present_support == c.VK_SUCCESS) {
            indices_opt.present_family = @intCast(i);
        }

        if (indices_opt.is_complete()) {
            break;
        }
    }

    return indices_opt.to_queue_family_indices();
}
