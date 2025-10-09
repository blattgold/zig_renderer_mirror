const std = @import("std");
const common = @import("common.zig");
const logger = @import("logger.zig");
const config = @import("config.zig");

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
    const details = query_swapchain_support_details(allocator, physical_device, vk_surface) catch return false;
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

        if (present_support == c.VK_SUCCESS) {
            indices_opt.present_family = @intCast(i);
        }

        if (indices_opt.is_complete()) {
            break;
        }
    }

    return indices_opt.to_queue_family_indices();
}

/// alloctes memory, details has to be manually deallocated after use.
///
/// returns an error if:
/// - vulkan function call fails
/// - format_count or present_mode_count is less than 1
pub fn query_swapchain_support_details(
    allocator: std.mem.Allocator,
    physical_device: c.VkPhysicalDevice,
    vk_surface: c.VkSurfaceKHR,
) !SwapChainSupportDetails {
    // capabilities
    var surface_capabilities: c.VkSurfaceCapabilitiesKHR = undefined;
    if (c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, vk_surface, @ptrCast(&surface_capabilities)) != c.VK_SUCCESS)
        return VulkanError.SwapChainSupportDetailsQueryFailure;

    // formats
    var surface_formats: []c.VkSurfaceFormatKHR = undefined;
    {
        var format_count: u32 = undefined;
        if (c.vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, vk_surface, &format_count, null) != c.VK_SUCCESS)
            return VulkanError.SwapChainSupportDetailsQueryFailure;

        if (format_count < 1)
            return VulkanError.SwapChainSupportDetailsQueryFailure;

        surface_formats = try allocator.alloc(c.VkSurfaceFormatKHR, format_count);
        errdefer allocator.free(surface_formats);
        if (c.vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, vk_surface, &format_count, surface_formats.ptr) != c.VK_SUCCESS)
            return VulkanError.SwapChainSupportDetailsQueryFailure;
    }
    errdefer allocator.free(surface_formats);

    // present modes
    var present_modes: []c.VkPresentModeKHR = undefined;
    {
        var present_mode_count: u32 = undefined;
        if (c.vkGetPhysicalDeviceSurfacePresentModesKHR(physical_device, vk_surface, &present_mode_count, null) != c.VK_SUCCESS)
            return VulkanError.SwapChainSupportDetailsQueryFailure;

        if (present_mode_count < 1)
            return VulkanError.SwapChainSupportDetailsQueryFailure;

        present_modes = try allocator.alloc(c.VkPresentModeKHR, present_mode_count);
        errdefer allocator.free(present_modes);
        if (c.vkGetPhysicalDeviceSurfacePresentModesKHR(physical_device, vk_surface, &present_mode_count, present_modes.ptr) != c.VK_SUCCESS)
            return VulkanError.SwapChainSupportDetailsQueryFailure;
    }

    return .{
        .capabilities = surface_capabilities,
        .formats = surface_formats,
        .present_modes = present_modes,
    };
}

/// choose preferred format.
///
/// if preferred format is unavailable, picks the first one.
pub fn select_swap_surface_format(available_formats: []c.VkSurfaceFormatKHR) c.VkSurfaceFormatKHR {
    std.debug.assert(available_formats.len != 0);

    for (available_formats) |available_format| {
        if (available_format.format == c.VK_FORMAT_B8G8R8_SRGB and
            available_format.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)
            return available_format;
    }

    return available_formats[0];
}
/// choose preferred present mode.
///
/// if preferred present mode is unavailable, picks c.VK_PRESENT_MODE_FIFO_KHR.
pub fn select_swap_present_mode(available_present_modes: []c.VkPresentModeKHR) c.VkPresentModeKHR {
    for (available_present_modes) |available_present_mode| {
        if (available_present_mode == c.VK_PRESENT_MODE_MAILBOX_KHR) {
            return available_present_mode;
        }
    }

    // all devices that support Vulkan must support this present mode so it is a nice default.
    return c.VK_PRESENT_MODE_FIFO_KHR;
}

pub fn select_swap_extent(
    capabilites: c.VkSurfaceCapabilitiesKHR,
    window_frame_buffer_size: WindowFrameBufferSize,
) c.VkExtent2D {
    if (capabilites.currentExtent.width != std.math.maxInt(u32)) {
        return capabilites.currentExtent;
    } else {
        var actual_extent: c.VkExtent2D = .{
            .height = window_frame_buffer_size.h,
            .width = window_frame_buffer_size.w,
        };

        actual_extent.width = std.math.clamp(
            actual_extent.width,
            capabilites.minImageExtent.width,
            capabilites.maxImageExtent.width,
        );
        actual_extent.height = std.math.clamp(
            actual_extent.height,
            capabilites.minImageExtent.height,
            capabilites.maxImageExtent.height,
        );

        return actual_extent;
    }
}

pub fn create_swap_chain(
    device: c.VkDevice,
    vk_surface: c.VkSurfaceKHR,
    surface_capabilities: c.VkSurfaceCapabilitiesKHR,
    surface_format: c.VkSurfaceFormatKHR,
    present_mode: c.VkPresentModeKHR,
    extent: c.VkExtent2D,
    queue_family_indices: QueueFamilyIndices,
) !c.VkSwapchainKHR {
    logger.log(.Debug, "swap chain extent: {d}x{d}", .{ extent.width, extent.height });

    var image_count = surface_capabilities.minImageCount + 1;
    if (surface_capabilities.maxImageCount > 0 and
        image_count > surface_capabilities.maxImageCount)
        image_count = surface_capabilities.maxImageCount;

    logger.log(.Debug, "swap chain min image count: {d}", .{image_count});

    var indices: [2]u32 = .{
        queue_family_indices.graphics_family,
        queue_family_indices.present_family,
    };

    var swap_chain_create_info: c.VkSwapchainCreateInfoKHR = .{
        .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = vk_surface,

        .minImageCount = image_count,
        .imageFormat = surface_format.format,
        .imageColorSpace = surface_format.colorSpace,
        .imageExtent = extent,
        .imageArrayLayers = 1,
        .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,

        .preTransform = surface_capabilities.currentTransform,
        .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = present_mode,
        .clipped = c.VK_TRUE,
        .oldSwapchain = null,
    };

    if (queue_family_indices.graphics_family != queue_family_indices.present_family) {
        logger.log(.Debug, "swap chain mode: VK_SHARING_MODE_CONCURRENT", .{});
        swap_chain_create_info.imageSharingMode = c.VK_SHARING_MODE_CONCURRENT;
        swap_chain_create_info.queueFamilyIndexCount = @intCast(indices.len);
        swap_chain_create_info.pQueueFamilyIndices = @ptrCast(indices[0..]);
    } else {
        logger.log(.Debug, "swap chain mode: VK_SHARING_MODE_EXCLUSIVE", .{});
        swap_chain_create_info.imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE;
    }

    var swap_chain: c.VkSwapchainKHR = undefined;
    if (c.vkCreateSwapchainKHR(device, &swap_chain_create_info, null, &swap_chain) != c.VK_SUCCESS)
        return VulkanError.SwapChainCreateFailure;

    logger.log(.Debug, "successfully created swap chain", .{});

    return swap_chain;
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

pub fn create_image_views(
    allocator: std.mem.Allocator,
    device: c.VkDevice,
    swap_chain_images: []c.VkImage,
    swap_chain_image_format: c.VkFormat,
) ![]c.VkImageView {
    var swap_chain_image_views: []c.VkImageView = try allocator.alloc(c.VkImageView, swap_chain_images.len);
    errdefer allocator.free(swap_chain_image_views);
    // create info for each image
    for (swap_chain_images, 0..) |swap_chain_image, i| {
        var image_view_create_info: c.VkImageViewCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = swap_chain_image,
            .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
            .format = swap_chain_image_format,

            // Swizzling allows you to map a color channel to a different one, or setting it to a constant value.
            .components = .{
                .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            },

            // describes image's purpose
            .subresourceRange = .{
                .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        };

        if (c.vkCreateImageView(device, &image_view_create_info, null, &swap_chain_image_views[i]) != c.VK_SUCCESS)
            return VulkanError.ImageViewCreateError;
    }

    return swap_chain_image_views;
}
