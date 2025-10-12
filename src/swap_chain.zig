const std = @import("std");

const common = @import("common.zig");
const logger = @import("logger.zig");

const c = common.c;

const SwapChainSupportDetails = common.SwapChainSupportDetails;
const WindowFrameBufferSize = common.WindowFrameBufferSize;
const QueueFamilyIndices = common.QueueFamilyIndices;
const VulkanError = common.VulkanError;

const QuerySwapChainError = error{
    GetCapabilities,

    GetFormatCount,
    FormatCountZero,
    GetFormats,

    GetPresentModeCount,
    PresentModeCountZero,
    GetPresentModes,
};

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
        return QuerySwapChainError.GetCapabilities;

    // formats
    var surface_formats: []c.VkSurfaceFormatKHR = undefined;
    {
        var format_count: u32 = undefined;
        if (c.vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, vk_surface, &format_count, null) != c.VK_SUCCESS)
            return QuerySwapChainError.GetFormatCount;

        if (format_count == 0)
            return QuerySwapChainError.FormatCountZero;

        surface_formats = try allocator.alloc(c.VkSurfaceFormatKHR, format_count);
        errdefer allocator.free(surface_formats);
        if (c.vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, vk_surface, &format_count, surface_formats.ptr) != c.VK_SUCCESS)
            return QuerySwapChainError.GetFormats;
    }
    errdefer allocator.free(surface_formats);

    // present modes
    var present_modes: []c.VkPresentModeKHR = undefined;
    {
        var present_mode_count: u32 = undefined;
        if (c.vkGetPhysicalDeviceSurfacePresentModesKHR(physical_device, vk_surface, &present_mode_count, null) != c.VK_SUCCESS)
            return QuerySwapChainError.GetPresentModeCount;

        if (present_mode_count == 0)
            return QuerySwapChainError.PresentModeCountZero;

        present_modes = try allocator.alloc(c.VkPresentModeKHR, present_mode_count);
        errdefer allocator.free(present_modes);
        if (c.vkGetPhysicalDeviceSurfacePresentModesKHR(physical_device, vk_surface, &present_mode_count, present_modes.ptr) != c.VK_SUCCESS)
            return QuerySwapChainError.GetPresentModes;
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
