const std = @import("std");

const config = @import("config.zig");
const logger = @import("logger.zig");
const common = @import("common.zig");
const v_layers = @import("v_layers.zig");
const instance_mod = @import("instance.zig");
const device_mod = @import("device.zig");
const pipeline_mod = @import("pipeline.zig");
const buffer_mod = @import("buffer.zig");
const sync_mod = @import("sync.zig");

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
        errdefer c.vkDestroyInstance(self.vk_instance, null);
        errdefer if (config.enable_validation_layers) v_layers.destroy_debug_utils_messenger_ext(self.vk_instance, self.maybe_debug_messenger, null);

        var physical_device: c.VkPhysicalDevice = undefined;
        var queue_family_indices: QueueFamilyIndices = undefined;
        {
            const physical_devices = try device_mod.find_physical_devices(allocator, self.vk_instance);
            defer allocator.free(physical_devices);
            const physical_device_result = try device_mod.select_suitable_physical_device(physical_devices, vk_surface);

            physical_device = physical_device_result.physical_device;
            queue_family_indices = physical_device_result.indices;
        }

        const device = try device_mod.create_device(physical_device, queue_family_indices);
        errdefer c.vkDestroyDevice(device, null);
        logger.log(.Debug, "logical device created successfully: 0x{x}", .{@intFromPtr(device)});

        var graphics_queue: c.VkQueue = undefined;
        var present_queue: c.VkQueue = undefined;
        {
            c.vkGetDeviceQueue(device, queue_family_indices.graphics_family, 0, &graphics_queue);
            c.vkGetDeviceQueue(device, queue_family_indices.present_family, 0, &present_queue);
            logger.log(.Debug, "graphics queue: 0x{x}", .{@intFromPtr(graphics_queue)});
            logger.log(.Debug, "present queue: 0x{x}", .{@intFromPtr(present_queue)});
        }

        var swap_chain_surface_capabilities: c.VkSurfaceCapabilitiesKHR = undefined;
        var swap_chain_surface_format: c.VkSurfaceFormatKHR = undefined;
        var swap_chain_present_mode: c.VkPresentModeKHR = undefined;
        var swap_chain_extent: c.VkExtent2D = undefined;
        {
            const swap_chain_support_details = try device_mod.query_swapchain_support_details(
                allocator,
                physical_device,
                vk_surface,
            );
            defer swap_chain_support_details.deinit(allocator);
            swap_chain_surface_capabilities = swap_chain_support_details.capabilities;
            swap_chain_surface_format = device_mod.select_swap_surface_format(swap_chain_support_details.formats);
            swap_chain_present_mode = device_mod.select_swap_present_mode(swap_chain_support_details.present_modes);
            swap_chain_extent = device_mod.select_swap_extent(
                swap_chain_support_details.capabilities,
                window_frame_buffer_size,
            );
        }

        const swap_chain = try device_mod.create_swap_chain(
            device,
            vk_surface,
            swap_chain_surface_capabilities,
            swap_chain_surface_format,
            swap_chain_present_mode,
            swap_chain_extent,
            queue_family_indices,
        );
        errdefer c.vkDestroySwapchainKHR(device, swap_chain, null);

        var swap_chain_images: []c.VkImage = undefined;
        {
            var image_count: u32 = undefined;
            if (c.vkGetSwapchainImagesKHR(device, swap_chain, &image_count, null) != c.VK_SUCCESS)
                return VulkanError.SwapChainGetImagesFailure;

            swap_chain_images = try allocator.alloc(c.VkImage, image_count);
            if (c.vkGetSwapchainImagesKHR(device, swap_chain, &image_count, swap_chain_images.ptr) != c.VK_SUCCESS) {
                allocator.free(swap_chain_images);
                return VulkanError.SwapChainGetImagesFailure;
            }
            logger.log(.Debug, "loaded swap chain images successfully", .{});
        }
        errdefer allocator.free(swap_chain_images);

        const swap_chain_image_format = swap_chain_surface_format.format;
        const swap_chain_image_views = try device_mod.create_image_views(
            allocator,
            device,
            swap_chain_images,
            swap_chain_image_format,
        );
        errdefer allocator.free(swap_chain_image_views);
        errdefer for (swap_chain_image_views) |swap_chain_image_view| c.vkDestroyImageView(device, swap_chain_image_view, null);

        const render_pass = try pipeline_mod.create_render_pass(device, swap_chain_image_format);
        errdefer c.vkDestroyRenderPass(device, render_pass, null);

        const graphics_pipeline_layout = try pipeline_mod.create_graphics_pipeline_layout(device);
        errdefer c.vkDestroyPipelineLayout(device, graphics_pipeline_layout, null);

        var graphics_pipeline: c.VkPipeline = undefined;
        {
            const vert_shader_code = try common.read_file(allocator, "./shaders/vert.spv");
            defer allocator.free(vert_shader_code);
            const vert_shader_module = try pipeline_mod.create_shader_module(device, vert_shader_code);
            defer c.vkDestroyShaderModule(device, vert_shader_module, null);

            const frag_shader_code = try common.read_file(allocator, "./shaders/frag.spv");
            defer allocator.free(frag_shader_code);
            const frag_shader_module = try pipeline_mod.create_shader_module(device, frag_shader_code);
            defer c.vkDestroyShaderModule(device, frag_shader_module, null);

            graphics_pipeline = try pipeline_mod.create_graphics_pipeline(
                device,
                swap_chain_extent,
                graphics_pipeline_layout,
                render_pass,
                vert_shader_module,
                frag_shader_module,
            );
            logger.log(.Debug, "graphics_pipeline created successfully: 0x{x}", .{@intFromPtr(graphics_pipeline)});
        }
        errdefer c.vkDestroyPipeline(device, graphics_pipeline, null);

        const swap_chain_frame_buffers = try buffer_mod.create_framebuffers(
            allocator,
            device,
            render_pass,
            swap_chain_image_views,
            swap_chain_extent,
        );
        errdefer for (swap_chain_frame_buffers) |swap_chain_frame_buffer| c.vkDestroyFramebuffer(device, swap_chain_frame_buffer, null);

        const command_pool = try buffer_mod.create_command_pool(device, queue_family_indices);
        errdefer c.vkDestroyCommandPool(device, command_pool, null);

        const command_buffer = try buffer_mod.create_command_buffer(device, command_pool);
        errdefer c.vkFreeCommandBuffers(device, command_pool, 1, &command_buffer);

        const semaphore_image_available: c.VkSemaphore = try sync_mod.create_semaphore(device);
        errdefer c.vkDestroySemaphore(device, semaphore_image_available, null);
        const semaphore_render_finished: c.VkSemaphore = try sync_mod.create_semaphore(device);
        errdefer c.vkDestroySemaphore(device, semaphore_render_finished, null);
        const fence_in_flight: c.VkFence = try sync_mod.create_fence(device, true);
        errdefer c.vkDestroyFence(device, fence_in_flight, null);

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
            .swap_chain_extent = swap_chain_extent,
            .swap_chain_image_format = swap_chain_image_format,
            .swap_chain_images = swap_chain_images, // needs to be freed
            .swap_chain_image_views = swap_chain_image_views, // needs to be freed

            .graphics_pipeline = graphics_pipeline,
            .graphics_pipeline_layout = graphics_pipeline_layout,
            .render_pass = render_pass,

            .swap_chain_frame_buffers = swap_chain_frame_buffers,

            .command_pool = command_pool,
            .command_buffer = command_buffer,

            .semaphore_image_available = semaphore_image_available,
            .semaphore_render_finished = semaphore_render_finished,
            .fence_in_flight = fence_in_flight,
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
    swap_chain_extent: c.VkExtent2D,
    swap_chain_images: []c.VkImage,
    swap_chain_image_format: c.VkFormat,
    swap_chain_image_views: []c.VkImageView,

    graphics_pipeline: c.VkPipeline,
    graphics_pipeline_layout: c.VkPipelineLayout,
    render_pass: c.VkRenderPass,

    swap_chain_frame_buffers: []c.VkFramebuffer,

    command_pool: c.VkCommandPool,
    command_buffer: c.VkCommandBuffer,

    semaphore_image_available: c.VkSemaphore,
    semaphore_render_finished: c.VkSemaphore,
    fence_in_flight: c.VkFence,

    pub fn init_incomplete(required_extensions: *ArrayList([*c]const u8)) !VkContextIncompleteInit {
        if (config.enable_validation_layers)
            try required_extensions.append(allocator, c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME);

        var vk_instance: c.VkInstance = undefined;
        {
            defer required_extensions.deinit(allocator);
            vk_instance = try instance_mod.create_instance(required_extensions.items);

            logger.log(.Debug, "required extensions: {any}", .{required_extensions});
            logger.log(.Debug, "Instance created successfully: 0x{x}", .{@intFromPtr(vk_instance)});
            if (config.enable_validation_layers)
                logger.log(.Debug, "enabled validation layers: {any}", .{config.validation_layers});
        }
        errdefer c.vkDestroyInstance(vk_instance, null);

        const maybe_debug_messenger =
            if (config.enable_validation_layers)
                try v_layers.create_debug_messenger(vk_instance)
            else
                null;
        errdefer if (config.enable_validation_layers) v_layers.destroy_debug_utils_messenger_ext(vk_instance, maybe_debug_messenger, null);

        logger.log(.Debug, "VkContextIncompleteInit created successfully", .{});

        return .{
            .vk_instance = vk_instance,
            .maybe_debug_messenger = maybe_debug_messenger,
        };
    }

    pub fn render(self: @This()) !void {
        if (c.vkWaitForFences(self.device, 1, &self.fence_in_flight, c.VK_TRUE, std.math.maxInt(u64)) != c.VK_SUCCESS)
            return error.WaitForFences;
        if (c.vkResetFences(self.device, 1, &self.fence_in_flight) != c.VK_SUCCESS)
            return error.ResetFences;

        var image_index: u32 = undefined;
        if (c.vkAcquireNextImageKHR(
            self.device,
            self.swap_chain,
            std.math.maxInt(u64),
            self.semaphore_image_available,
            null,
            @ptrCast(&image_index),
        ) != c.VK_SUCCESS)
            return error.AcquireNextImage;

        if (c.vkResetCommandBuffer(self.command_buffer, 0) != c.VK_SUCCESS)
            return error.ResetCommandBuffer;

        try buffer_mod.record_command_buffer(
            self.render_pass,
            self.command_buffer,
            self.swap_chain_extent,
            self.swap_chain_frame_buffers,
            image_index,
            self.graphics_pipeline,
        );

        const wait_semaphores: [1]c.VkSemaphore = .{
            self.semaphore_image_available,
        };

        const signal_semaphores: [1]c.VkSemaphore = .{
            self.semaphore_render_finished,
        };

        const pipeline_stage_flags: c.VkPipelineStageFlags = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;

        const submit_info: c.VkSubmitInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &wait_semaphores,
            .pWaitDstStageMask = &pipeline_stage_flags,

            .commandBufferCount = 1,
            .pCommandBuffers = &self.command_buffer,

            .signalSemaphoreCount = 1,
            .pSignalSemaphores = &signal_semaphores,
        };

        if (c.vkQueueSubmit(self.graphics_queue, 1, &submit_info, self.fence_in_flight) != c.VK_SUCCESS)
            return error.QueueSubmit;

        const swap_chains: [1]c.VkSwapchainKHR = .{
            self.swap_chain,
        };

        const present_info: c.VkPresentInfoKHR = .{
            .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,

            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &signal_semaphores,

            .swapchainCount = 1,
            .pSwapchains = &swap_chains,
            .pImageIndices = &image_index,

            .pResults = null,
        };

        if (c.vkQueuePresentKHR(self.present_queue, &present_info) != c.VK_SUCCESS)
            return error.QueuePresent;
    }

    pub fn deinit(self: *@This()) void {
        logger.log(.Debug, "unloading VkContext...", .{});

        c.vkDestroySemaphore(self.device, self.semaphore_image_available, null);
        c.vkDestroySemaphore(self.device, self.semaphore_render_finished, null);
        c.vkDestroyFence(self.device, self.fence_in_flight, null);

        c.vkFreeCommandBuffers(self.device, self.command_pool, 1, &self.command_buffer);
        c.vkDestroyCommandPool(self.device, self.command_pool, null);
        for (self.swap_chain_frame_buffers) |swap_chain_frame_buffer|
            c.vkDestroyFramebuffer(self.device, swap_chain_frame_buffer, null);

        c.vkDestroyPipeline(self.device, self.graphics_pipeline, null);
        c.vkDestroyRenderPass(self.device, self.render_pass, null);
        c.vkDestroyPipelineLayout(self.device, self.graphics_pipeline_layout, null);
        for (self.swap_chain_image_views) |swap_chain_image_view|
            c.vkDestroyImageView(self.device, swap_chain_image_view, null);

        allocator.free(self.swap_chain_image_views);
        allocator.free(self.swap_chain_images);

        c.vkDestroySwapchainKHR(self.device, self.swap_chain, null);
        c.vkDestroySurfaceKHR(self.vk_instance, self.vk_surface, null);
        c.vkDestroyDevice(self.device, null);
        if (self.maybe_debug_messenger != null)
            v_layers.destroy_debug_utils_messenger_ext(self.vk_instance, self.maybe_debug_messenger, null);
        c.vkDestroyInstance(self.vk_instance, null);

        logger.log(.Debug, "finished unloading VkContext", .{});
    }
};
