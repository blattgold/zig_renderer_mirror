const std = @import("std");

const config = @import("config.zig");
const logger = @import("logger.zig");
const common = @import("common.zig");
const v_layers = @import("v_layers.zig");
const instance_mod = @import("instance.zig");
const device_mod = @import("device.zig");

const c = common.c;

const VulkanError = common.VulkanError;
const ArrayList = std.ArrayList;
const QueueFamilyIndices = common.QueueFamilyIndices;
const WindowFrameBufferSize = common.WindowFrameBufferSize;
const SwapChainSupportDetails = common.SwapChainSupportDetails;

const PhysicalDeviceResult = device_mod.PhysicalDeviceResult;

const allocator = std.heap.page_allocator;

pub const VkContextIncompleteInit = struct {
    vk_instance: c.VkInstance,
    maybe_debug_messenger: c.VkDebugUtilsMessengerEXT,

    pub fn init_complete(
        self: @This(),
        vk_surface: c.VkSurfaceKHR,
        window_frame_buffer_size: WindowFrameBufferSize,
    ) !VkContext {
        std.debug.assert(vk_surface != null);

        var physical_device_result: PhysicalDeviceResult = undefined;
        {
            const physical_devices = try device_mod.find_physical_devices(allocator, self.vk_instance);
            defer allocator.free(physical_devices);
            physical_device_result = try device_mod.select_suitable_physical_device(physical_devices, vk_surface);
        }

        const physical_device = physical_device_result.physical_device;
        const queue_family_indices = physical_device_result.indices;

        const device = try device_mod.create_device(physical_device, queue_family_indices);
        logger.log(.Debug, "logical device created successfully: 0x{x}", .{@intFromPtr(device)});

        var graphics_queue: c.VkQueue = undefined;
        var present_queue: c.VkQueue = undefined;
        c.vkGetDeviceQueue(device, queue_family_indices.graphics_family, 0, &graphics_queue);
        c.vkGetDeviceQueue(device, queue_family_indices.present_family, 0, &present_queue);
        logger.log(.Debug, "graphics queue: 0x{x}", .{@intFromPtr(graphics_queue)});
        logger.log(.Debug, "present queue: 0x{x}", .{@intFromPtr(present_queue)});

        const swap_chain_support_details = try device_mod.query_swapchain_support_details(
            allocator,
            physical_device,
            vk_surface,
        );

        const swap_chain = try device_mod.create_swap_chain(
            device,
            vk_surface,
            swap_chain_support_details,
            window_frame_buffer_size,
            queue_family_indices,
        );

        var swap_chain_images: ArrayList(c.VkImage) = .empty;
        {
            var image_count: u32 = undefined;
            if (c.vkGetSwapchainImagesKHR(device, swap_chain, &image_count, null) != c.VK_SUCCESS)
                return VulkanError.SwapChainGetImagesFailure;

            try swap_chain_images.resize(allocator, image_count);
            if (c.vkGetSwapchainImagesKHR(device, swap_chain, &image_count, swap_chain_images.items.ptr) != c.VK_SUCCESS) {
                swap_chain_images.clearAndFree(allocator);
                return VulkanError.SwapChainGetImagesFailure;
            }
            logger.log(.Debug, "loaded swap chain images successfully", .{});
        }

        logger.log(.Debug, "VkContext created successfully", .{});

        return VkContext{
            .vk_instance = self.vk_instance,
            .maybe_debug_messenger = self.maybe_debug_messenger,

            .queue_family_indices = queue_family_indices,
            .graphics_queue = graphics_queue,
            .present_queue = present_queue,
            .device = device,

            .vk_surface = vk_surface,
            .swap_chain = swap_chain,
            .swap_chain_images = swap_chain_images,
            .swap_chain_support_details = swap_chain_support_details,
        };
    }
};

pub const VkContext = struct {
    vk_instance: c.VkInstance,
    maybe_debug_messenger: c.VkDebugUtilsMessengerEXT,

    queue_family_indices: QueueFamilyIndices,
    graphics_queue: c.VkQueue,
    present_queue: c.VkQueue,
    device: c.VkDevice,

    vk_surface: c.VkSurfaceKHR,
    swap_chain: c.VkSwapchainKHR,
    swap_chain_images: ArrayList(c.VkImage),
    swap_chain_support_details: SwapChainSupportDetails,

    pub fn init_incomplete(required_extensions: *ArrayList([*c]const u8)) !VkContextIncompleteInit {
        if (config.enable_validation_layers)
            try required_extensions.append(allocator, c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME);

        var vk_instance: c.VkInstance = undefined;
        {
            vk_instance = try instance_mod.create_instance(required_extensions.items);
            defer required_extensions.deinit(allocator);

            logger.log(.Debug, "required extensions: {any}", .{required_extensions});
            logger.log(.Debug, "Instance created successfully: 0x{x}", .{@intFromPtr(vk_instance)});
            if (config.enable_validation_layers)
                logger.log(.Debug, "enabled validation layers: {any}", .{config.validation_layers});
        }

        const maybe_debug_messenger = if (config.enable_validation_layers) try v_layers.create_debug_messenger(vk_instance) else null;

        logger.log(.Debug, "VkContextIncompleteInit created successfully", .{});

        return .{
            .vk_instance = vk_instance,
            .maybe_debug_messenger = maybe_debug_messenger,
        };
    }

    pub fn deinit(self: *@This()) void {
        logger.log(.Debug, "unloading VkContext...", .{});

        self.swap_chain_images.clearAndFree(allocator);
        self.swap_chain_support_details.deinit(allocator);

        c.vkDestroySwapchainKHR(self.device, self.swap_chain, null);
        c.vkDestroySurfaceKHR(self.vk_instance, self.vk_surface, null);
        c.vkDestroyDevice(self.device, null);
        if (self.maybe_debug_messenger != null) {
            v_layers.destroy_debug_utils_messenger_ext(self.vk_instance, self.maybe_debug_messenger, null);
        }
        c.vkDestroyInstance(self.vk_instance, null);

        logger.log(.Debug, "finished unloading VkContext", .{});
    }
};
