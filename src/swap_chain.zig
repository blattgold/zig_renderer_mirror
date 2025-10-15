const std = @import("std");

const common = @import("common.zig");
const logger = @import("logger.zig");
const buffer_mod = @import("buffer.zig");

const c = common.c;

const SwapChainSupportDetails = common.SwapChainSupportDetails;
const WindowFrameBufferSize = common.WindowFrameBufferSize;
const QueueFamilyIndices = common.QueueFamilyIndices;
const VulkanError = common.VulkanError;

pub const SwapChainState = struct {
    // persistent data
    allocator: std.mem.Allocator,
    surface: c.VkSurfaceKHR,
    device: c.VkDevice,
    queue_family_indices: QueueFamilyIndices,

    // variable data
    swap_chain: c.VkSwapchainKHR,
    images: []c.VkImage,
    image_views: []c.VkImageView,

    // meta data
    surface_capabilities: c.VkSurfaceCapabilitiesKHR,
    surface_format: c.VkSurfaceFormatKHR,
    present_mode: c.VkPresentModeKHR,

    // variable meta data
    extent: c.VkExtent2D,

    pub fn recreate(
        self: *@This(),
        window_frame_buffer_size: WindowFrameBufferSize,
    ) !void {
        self.deinit();
        try populate_swap_chain_common_helper(self, window_frame_buffer_size);
    }

    /// vkDestroy and freeing of slices
    pub fn deinit(
        self: *@This(),
    ) void {
        logger.log(.Debug, "destroying swap_chain_state members...", .{});
        self.destroy_all();

        logger.log(.Debug, "freeing image_views...", .{});
        self.allocator.free(self.image_views);
        logger.log(.Debug, "freeing images...", .{});
        self.allocator.free(self.images);
    }

    fn destroy_all(
        self: *@This(),
    ) void {
        for (self.image_views) |image_view|
            c.vkDestroyImageView(self.device, image_view, null);

        c.vkDestroySwapchainKHR(self.device, self.swap_chain, null);
    }
};

/// ## helper for both recreating and creating the swap chain.
///
/// fills out images, image_views, swap_chain and extent.
/// The rest of the fields need to be initialized before being passed to this function.
fn populate_swap_chain_common_helper(
    swap_chain_state_ptr: *SwapChainState,
    window_frame_buffer_size: WindowFrameBufferSize,
) !void {
    const allocator = swap_chain_state_ptr.*.allocator;
    const device = swap_chain_state_ptr.*.device;
    const surface = swap_chain_state_ptr.*.surface;
    const queue_family_indices = swap_chain_state_ptr.*.queue_family_indices;

    const surface_format = swap_chain_state_ptr.*.surface_format;
    const surface_present_mode = swap_chain_state_ptr.*.present_mode;
    const surface_capabilities = swap_chain_state_ptr.*.surface_capabilities;

    const surface_extent = select_swap_extent(
        surface_capabilities,
        window_frame_buffer_size,
    );

    const swap_chain = try create_swap_chain(
        device,
        surface,
        surface_capabilities,
        surface_format,
        surface_present_mode,
        surface_extent,
        queue_family_indices,
    );

    const swap_chain_images = try get_swap_chain_images(
        swap_chain_state_ptr.allocator,
        device,
        swap_chain,
    );
    errdefer allocator.free(swap_chain_images);

    const swap_chain_image_views = try create_image_views(
        allocator,
        device,
        swap_chain_images,
        surface_format.format,
    );
    errdefer allocator.free(swap_chain_image_views);
    errdefer for (swap_chain_image_views) |view| c.vkDestroyImageView(device, view, null);

    swap_chain_state_ptr.swap_chain = swap_chain;
    swap_chain_state_ptr.images = swap_chain_images;
    swap_chain_state_ptr.image_views = swap_chain_image_views;
    swap_chain_state_ptr.extent = surface_extent;
}

pub fn create_swap_chain_state(
    allocator: std.mem.Allocator,
    device: c.VkDevice,
    surface: c.VkSurfaceKHR,
    surface_capabilities: c.VkSurfaceCapabilitiesKHR,
    surface_format: c.VkSurfaceFormatKHR,
    surface_present_mode: c.VkPresentModeKHR,
    queue_family_indices: QueueFamilyIndices,
    window_frame_bufer_size: WindowFrameBufferSize,
) !SwapChainState {
    var swap_chain_state: SwapChainState = undefined;
    swap_chain_state.allocator = allocator;
    swap_chain_state.device = device;
    swap_chain_state.present_mode = surface_present_mode;
    swap_chain_state.queue_family_indices = queue_family_indices;
    swap_chain_state.surface = surface;
    swap_chain_state.surface_capabilities = surface_capabilities;
    swap_chain_state.surface_format = surface_format;

    try populate_swap_chain_common_helper(
        &swap_chain_state,
        window_frame_bufer_size,
    );

    return swap_chain_state;
}

fn get_swap_chain_images(
    allocator: std.mem.Allocator,
    device: c.VkDevice,
    swap_chain: c.VkSwapchainKHR,
) ![]c.VkImage {
    var swap_chain_images: []c.VkImage = undefined;
    {
        var image_count: u32 = undefined;
        if (c.vkGetSwapchainImagesKHR(device, swap_chain, &image_count, null) != c.VK_SUCCESS)
            return VulkanError.SwapChainGetImagesFailure;

        swap_chain_images = try allocator.alloc(c.VkImage, image_count);
        errdefer allocator.free(swap_chain_images);
        if (c.vkGetSwapchainImagesKHR(device, swap_chain, &image_count, swap_chain_images.ptr) != c.VK_SUCCESS)
            return VulkanError.SwapChainGetImagesFailure;
    }
    return swap_chain_images;
}

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
    var surface_capabilities: c.VkSurfaceCapabilitiesKHR = undefined;
    if (c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, vk_surface, @ptrCast(&surface_capabilities)) != c.VK_SUCCESS)
        return QuerySwapChainError.GetCapabilities;

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

/// if preferred present mode is unavailable, picks c.VK_PRESENT_MODE_FIFO_KHR (guaranteed to be supported).
pub fn select_swap_present_mode(available_present_modes: []c.VkPresentModeKHR) c.VkPresentModeKHR {
    for (available_present_modes) |available_present_mode| {
        if (available_present_mode == c.VK_PRESENT_MODE_MAILBOX_KHR) {
            return available_present_mode;
        }
    }

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
