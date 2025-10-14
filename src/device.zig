const std = @import("std");

const common = @import("common.zig");
const logger = @import("logger.zig");
const config = @import("config.zig");
const swap_chain_mod = @import("swap_chain.zig");

const c = common.c;

const ArrayList = std.ArrayList;
const VulkanError = common.VulkanError;
const QueueFamilyIndices = common.QueueFamilyIndices;
const QueueFamilyIndicesOpt = common.QueueFamilyIndicesOpt;
const SwapChainSupportDetails = common.SwapChainSupportDetails;
const WindowFrameBufferSize = common.WindowFrameBufferSize;

pub const PhysicalDeviceResult = struct {
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
    errdefer allocator.free(physical_devices);
    if (c.vkEnumeratePhysicalDevices(
        vk_instance,
        &physical_device_count,
        &physical_devices[0],
    ) != c.VK_SUCCESS)
        return VulkanError.NoPhysicalDevices;

    return physical_devices;
}

/// a device is suitable if:
/// - at least one queue_family exists that has all the necessary capabilites.
/// - it supports all the required device extensions defined in config.device_extensions
/// - querying swapchain details succeeds (vk function calls succeed and neither formats nor present modes are empty)
///
/// return value is a struct that contains QueueFamilyIndices + the PhysicalDevice.
pub fn select_suitable_physical_device(
    physical_devices: []c.VkPhysicalDevice,
    vk_surface: c.VkSurfaceKHR,
) !PhysicalDeviceResult {
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

        const physical_device_suitable =
            indices != null and
            try supports_required_extensions(physical_device) and
            swap_chain_suitable(allocator, physical_device, vk_surface);

        if (physical_device_suitable) {
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

/// helper for select_suitable_physical_device
fn swap_chain_suitable(
    allocator: std.mem.Allocator,
    physical_device: c.VkPhysicalDevice,
    vk_surface: c.VkSurfaceKHR,
) bool {
    const details = swap_chain_mod.query_swapchain_support_details(allocator, physical_device, vk_surface) catch return false;
    details.deinit(allocator);
    return true;
}

/// helper for select_suitable_physical_device
/// returns true if all the required extensions are supported
fn supports_required_extensions(physical_device: c.VkPhysicalDevice) !bool {
    const allocator = std.heap.page_allocator;

    var extension_count: u32 = undefined;
    if (c.vkEnumerateDeviceExtensionProperties(physical_device, null, &extension_count, null) != c.VK_SUCCESS)
        return false;

    const available_extensions = try allocator.alloc(c.VkExtensionProperties, extension_count);
    defer allocator.free(available_extensions);
    if (c.vkEnumerateDeviceExtensionProperties(physical_device, null, &extension_count, available_extensions.ptr) != c.VK_SUCCESS)
        return false;

    for (config.device_extensions) |required_device_extension_name| {
        var found_required_device_extension = false;

        for (available_extensions) |available_extension| {
            if (std.mem.eql(
                u8,
                required_device_extension_name,
                std.mem.sliceTo(available_extension.extensionName[0..], 0),
            )) {
                found_required_device_extension = true;
                break;
            }
        }

        if (!found_required_device_extension) {
            logger.log(.Error, "couldn't find required device extension: {s}", .{required_device_extension_name});
            return false;
        }
        logger.log(.Debug, "found required device extension: {s}", .{required_device_extension_name});
    }

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
        std.debug.assert(i < std.math.maxInt(u32));

        var present_support: c.VkBool32 = undefined;
        _ = c.vkGetPhysicalDeviceSurfaceSupportKHR(physical_device, @intCast(i), vk_surface, &present_support);

        if (queue_family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0) {
            indices_opt.graphics_family = @intCast(i);
        }

        if (present_support == c.VK_TRUE) {
            indices_opt.present_family = @intCast(i);
        }

        if (indices_opt.is_complete()) {
            break;
        }
    }

    return indices_opt.to_queue_family_indices();
}

pub fn create_device(physical_device: c.VkPhysicalDevice, indices: QueueFamilyIndices) !c.VkDevice {
    const allocator = std.heap.page_allocator;

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

    // only add present queue if indices differ
    if (indices.graphics_family != indices.present_family) {
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
        .enabledExtensionCount = @intCast(config.device_extensions.len),
        .ppEnabledExtensionNames = @ptrCast(config.device_extensions.ptr),
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

pub fn select_suitable_memory_type_index(
    physical_device: c.VkPhysicalDevice,
    type_filter: u32,
    properties: c.VkMemoryPropertyFlags,
) !u32 {
    var physical_device_memory_properties: c.VkPhysicalDeviceMemoryProperties = undefined;
    c.vkGetPhysicalDeviceMemoryProperties(physical_device, &physical_device_memory_properties);

    for (0..physical_device_memory_properties.memoryTypeCount) |i|
        if ((type_filter & (@as(usize, 1) << @intCast(i)) != 0) and
            physical_device_memory_properties.memoryTypes[i].propertyFlags & properties == properties)
            return @intCast(i);

    return error.NoSuitableMemoryTypeFound;
}
