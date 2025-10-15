const std = @import("std");

const config = @import("config.zig");
const logger = @import("logger.zig");
const common = @import("common.zig");
const validation_layers = @import("validation_layers.zig");
const instance_mod = @import("instance.zig");
const device_mod = @import("device.zig");
const pipeline_mod = @import("pipeline.zig");
const buffer_mod = @import("buffer.zig");
const sync_mod = @import("sync.zig");
const swapchain_mod = @import("swapchain.zig");

const c = common.c;

const VulkanError = common.VulkanError;
const ArrayList = std.ArrayList;
const QueueFamilyIndices = common.QueueFamilyIndices;
const WindowFrameBufferSize = common.WindowFrameBufferSize;
const SwapChainSupportDetails = common.SwapchainSupportDetails;
const SwapchainState = swapchain_mod.SwapchainState;

const PhysicalDeviceResult = device_mod.PhysicalDeviceResult;

const allocator = std.heap.page_allocator;

/// IMPORTANT: must call deinit, otherwise leaks memory and doesn't uninit Vulkan
pub const VkContext = struct {
    instance: c.VkInstance,
    maybe_debug_messenger: c.VkDebugUtilsMessengerEXT,

    get_window_fb_size_callback: *const fn (context: ?*anyopaque) WindowFrameBufferSize,
    get_window_fb_size_context: ?*anyopaque,

    queue_family_indices: QueueFamilyIndices,
    graphics_queue: c.VkQueue,
    present_queue: c.VkQueue,
    device: c.VkDevice,

    surface: c.VkSurfaceKHR,

    swapchain_state: SwapchainState,

    graphics_pipeline: c.VkPipeline,
    graphics_pipeline_layout: c.VkPipelineLayout,
    render_pass: c.VkRenderPass,

    swapchain_framebuffers: []c.VkFramebuffer,

    vertex_buffer: c.VkBuffer,
    vertex_buffer_memory: c.VkDeviceMemory,

    command_pool: c.VkCommandPool,
    command_buffers: []c.VkCommandBuffer,

    semaphores_image_available: []c.VkSemaphore,
    semaphores_render_finished: []c.VkSemaphore,
    fences_in_flight: []c.VkFence,

    framebuffer_resized: bool,
    current_frame: usize,

    pub fn render(self: *@This()) !void {
        const current_frame_modulo_index: usize = self.current_frame % config.max_frames_in_flight;

        if (c.vkWaitForFences(self.device, 1, &self.fences_in_flight[current_frame_modulo_index], c.VK_TRUE, std.math.maxInt(u64)) != c.VK_SUCCESS)
            return error.WaitForFences;

        var image_index: u32 = undefined;
        const acquire_next_image_result = c.vkAcquireNextImageKHR(
            self.device,
            self.swapchain_state.swapchain,
            std.math.maxInt(u64),
            self.semaphores_image_available[current_frame_modulo_index],
            null,
            @ptrCast(&image_index),
        );

        if (self.framebuffer_resized) {
            self.framebuffer_resized = false;
            try self.recreateSwapchain();
        } else {
            switch (acquire_next_image_result) {
                c.VK_SUCCESS => {},
                c.VK_ERROR_OUT_OF_DATE_KHR, c.VK_SUBOPTIMAL_KHR => {
                    self.framebuffer_resized = false;
                    try self.recreateSwapchain();
                },
                else => return error.AcquireNextImage,
            }
        }

        if (c.vkResetFences(self.device, 1, &self.fences_in_flight[current_frame_modulo_index]) != c.VK_SUCCESS)
            return error.ResetFences;

        if (c.vkResetCommandBuffer(self.command_buffers[current_frame_modulo_index], 0) != c.VK_SUCCESS)
            return error.ResetCommandBuffer;

        try buffer_mod.recordCommandBuffer(
            self.render_pass,
            self.command_buffers[current_frame_modulo_index],
            self.swapchain_state.extent,
            self.swapchain_framebuffers,
            image_index,
            self.graphics_pipeline,
            self.vertex_buffer,
        );

        const wait_semaphores: [1]c.VkSemaphore = .{
            self.semaphores_image_available[current_frame_modulo_index],
        };

        const signal_semaphores: [1]c.VkSemaphore = .{
            self.semaphores_render_finished[current_frame_modulo_index],
        };

        const pipeline_stage_flags: c.VkPipelineStageFlags = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;

        const submit_info: c.VkSubmitInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &wait_semaphores,
            .pWaitDstStageMask = &pipeline_stage_flags,

            .commandBufferCount = 1,
            .pCommandBuffers = &self.command_buffers[current_frame_modulo_index],

            .signalSemaphoreCount = 1,
            .pSignalSemaphores = &signal_semaphores,
        };

        if (c.vkQueueSubmit(self.graphics_queue, 1, &submit_info, self.fences_in_flight[current_frame_modulo_index]) != c.VK_SUCCESS)
            return error.QueueSubmit;

        const swap_chains: [1]c.VkSwapchainKHR = .{
            self.swapchain_state.swapchain,
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

        self.current_frame += 1;
    }

    pub fn recreateSwapchain(self: *@This()) !void {
        _ = c.vkDeviceWaitIdle(self.device);
        const new_window_buffer_size = self.get_window_fb_size_callback(self.get_window_fb_size_context);
        try self.swapchain_state.recreate(new_window_buffer_size);

        for (self.swapchain_framebuffers) |buffer| c.vkDestroyFramebuffer(self.device, buffer, null);
        allocator.free(self.swapchain_framebuffers);

        self.swapchain_framebuffers = try buffer_mod.createFramebuffers(
            allocator,
            self.device,
            self.render_pass,
            self.swapchain_state.image_views,
            self.swapchain_state.extent,
        );
    }

    pub fn deinit(self: *@This()) void {
        logger.log(.Debug, "unloading VkContext...", .{});

        c.vkDestroyBuffer(self.device, self.vertex_buffer, null);
        c.vkFreeMemory(self.device, self.vertex_buffer_memory, null);

        for (self.semaphores_image_available, self.semaphores_render_finished, self.fences_in_flight) |
            semaphore_image_available,
            semaphore_render_finished,
            fence_in_flight,
        | {
            c.vkDestroySemaphore(self.device, semaphore_image_available, null);
            c.vkDestroySemaphore(self.device, semaphore_render_finished, null);
            c.vkDestroyFence(self.device, fence_in_flight, null);
        }

        c.vkFreeCommandBuffers(self.device, self.command_pool, config.max_frames_in_flight, &self.command_buffers[0]);
        c.vkDestroyCommandPool(self.device, self.command_pool, null);
        for (self.swapchain_framebuffers) |swap_chain_frame_buffer|
            c.vkDestroyFramebuffer(self.device, swap_chain_frame_buffer, null);

        c.vkDestroyPipeline(self.device, self.graphics_pipeline, null);
        c.vkDestroyRenderPass(self.device, self.render_pass, null);
        c.vkDestroyPipelineLayout(self.device, self.graphics_pipeline_layout, null);

        self.swapchain_state.deinit();

        c.vkDestroySurfaceKHR(self.instance, self.surface, null);
        c.vkDestroyDevice(self.device, null);
        if (self.maybe_debug_messenger != null)
            validation_layers.destroyDebugUtilsMessengerExt(self.instance, self.maybe_debug_messenger, null);
        c.vkDestroyInstance(self.instance, null);

        logger.log(.Debug, "finished unloading VkContext", .{});
    }
};

const VkContextBuilder = struct {
    instance: c.VkInstance,
    maybe_debug_messenger: c.VkDebugUtilsMessengerEXT,

    surface: c.VkSurfaceKHR,
    get_window_fb_size_callback: ?*const fn (context: ?*anyopaque) WindowFrameBufferSize,
    get_window_fb_size_context: ?*anyopaque,

    pub fn setSurface(
        self: *@This(),
        surface: c.VkSurfaceKHR,
    ) *@This() {
        self.surface = surface;
        return self;
    }

    pub fn setGetWindowFbSizeCallback(
        self: *@This(),
        get_window_frame_buffer_size_fn: fn (context: ?*anyopaque) WindowFrameBufferSize,
    ) *@This() {
        self.get_window_fb_size_callback = get_window_frame_buffer_size_fn;
        return self;
    }

    pub fn setGetWindowFbSizeContext(
        self: *@This(),
        get_window_frame_buffer_size_context: ?*anyopaque,
    ) *@This() {
        self.get_window_fb_size_context = get_window_frame_buffer_size_context;
        return self;
    }

    pub fn getInstance(
        self: @This(),
    ) c.VkInstance {
        return self.instance;
    }

    pub fn build(
        self: *@This(),
    ) !VkContext {
        errdefer c.vkDestroyInstance(self.instance, null);
        errdefer if (config.enable_validation_layers) validation_layers.destroyDebugUtilsMessengerExt(self.instance, self.maybe_debug_messenger, null);

        try self.validate();

        const surface = self.surface;
        const get_window_frame_buffer_size_fn = self.get_window_fb_size_callback.?;
        const get_window_frame_buffer_size_context = self.get_window_fb_size_context.?;

        var physical_device: c.VkPhysicalDevice = undefined;
        var queue_family_indices: QueueFamilyIndices = undefined;
        {
            const physical_devices = try device_mod.findPhysicalDevices(allocator, self.instance);
            defer allocator.free(physical_devices);
            const physical_device_result = try device_mod.selectSuitablePhysicalDevice(physical_devices, self.surface);

            physical_device = physical_device_result.physical_device;
            queue_family_indices = physical_device_result.indices;
        }

        const device = try device_mod.createDevice(physical_device, queue_family_indices);
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

        const swapchain_support_details = try swapchain_mod.querySwapchainSupportDetails(
            allocator,
            physical_device,
            self.surface,
        );

        var swapchain_state = try swapchain_mod.createSwapchainState(
            allocator,
            device,
            surface,
            swapchain_support_details.capabilities,
            swapchain_mod.selectSwapSurfaceFormat(swapchain_support_details.formats),
            swapchain_mod.selectSwapchainPresentMode(swapchain_support_details.present_modes),
            queue_family_indices,
            get_window_frame_buffer_size_fn(get_window_frame_buffer_size_context),
        );
        errdefer swapchain_state.deinit();

        var render_pass: c.VkRenderPass = undefined;
        {
            render_pass = try pipeline_mod.createRenderPass(device, swapchain_state.surface_format.format);
            logger.log(.Debug, "created render pass successfully", .{});
        }
        errdefer c.vkDestroyRenderPass(device, render_pass, null);

        var graphics_pipeline_layout: c.VkPipelineLayout = undefined;
        {
            graphics_pipeline_layout = try pipeline_mod.createGraphicsPipelineLayout(device);
            logger.log(.Debug, "created graphics pipeline layout successfully", .{});
        }
        errdefer c.vkDestroyPipelineLayout(device, graphics_pipeline_layout, null);

        var graphics_pipeline: c.VkPipeline = undefined;
        {
            const vert_shader_code = try common.readFile(allocator, "./shaders/vert.spv");
            defer allocator.free(vert_shader_code);
            const vert_shader_module = try pipeline_mod.createShaderModule(device, vert_shader_code);
            defer c.vkDestroyShaderModule(device, vert_shader_module, null);

            const frag_shader_code = try common.readFile(allocator, "./shaders/frag.spv");
            defer allocator.free(frag_shader_code);
            const frag_shader_module = try pipeline_mod.createShaderModule(device, frag_shader_code);
            defer c.vkDestroyShaderModule(device, frag_shader_module, null);

            graphics_pipeline = try pipeline_mod.createGraphicsPipeline(
                device,
                swapchain_state.extent,
                graphics_pipeline_layout,
                render_pass,
                vert_shader_module,
                frag_shader_module,
            );
            logger.log(.Debug, "graphics_pipeline created successfully: 0x{x}", .{@intFromPtr(graphics_pipeline)});
        }
        errdefer c.vkDestroyPipeline(device, graphics_pipeline, null);

        const swapchain_framebuffers = try buffer_mod.createFramebuffers(
            allocator,
            device,
            render_pass,
            swapchain_state.image_views,
            swapchain_state.extent,
        );
        errdefer for (swapchain_framebuffers) |swap_chain_frame_buffer| c.vkDestroyFramebuffer(device, swap_chain_frame_buffer, null);

        var command_pool: c.VkCommandPool = undefined;
        {
            command_pool = try buffer_mod.createCommandPool(device, queue_family_indices);
            logger.log(.Debug, "created command pool successfully", .{});
        }
        errdefer c.vkDestroyCommandPool(device, command_pool, null);

        var vertex_buffer: c.VkBuffer = undefined;
        var vertex_buffer_memory: c.VkDeviceMemory = undefined;
        {
            vertex_buffer = try buffer_mod.createVertexBuffer(device);
            errdefer c.vkDestroyBuffer(device, vertex_buffer, null);

            var vertex_buffer_memory_requirements: c.VkMemoryRequirements = undefined;
            c.vkGetBufferMemoryRequirements(device, vertex_buffer, &vertex_buffer_memory_requirements);
            logger.log(
                .Debug,
                "vertex buffer memory requirements: size: {d}, alignment: {d}, memoryTypeBits: {b}, memoryTypeBits: {d}, memoryTypeBits: {x}",
                .{
                    vertex_buffer_memory_requirements.size,
                    vertex_buffer_memory_requirements.alignment,
                    vertex_buffer_memory_requirements.memoryTypeBits,
                    vertex_buffer_memory_requirements.memoryTypeBits,
                    vertex_buffer_memory_requirements.memoryTypeBits,
                },
            );

            const memory_type_index = try device_mod.selectSuitableMemoryTypeIndex(
                physical_device,
                vertex_buffer_memory_requirements.memoryTypeBits,
                c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            );
            vertex_buffer_memory = try buffer_mod.allocVertexBufferMemory(
                device,
                vertex_buffer_memory_requirements,
                memory_type_index,
            );
            errdefer c.vkFreeMemory(device, vertex_buffer_memory, null);

            if (c.vkBindBufferMemory(device, vertex_buffer, vertex_buffer_memory, 0) != c.VK_SUCCESS)
                return error.BindBufferMemory;

            var mapped_data: *[common.vertices.len]common.Vertex = undefined;
            const vert_slice_size = @sizeOf(common.Vertex) * common.vertices.len;
            _ = c.vkMapMemory(device, vertex_buffer_memory, 0, vert_slice_size, 0, @ptrCast(&mapped_data));
            @memcpy(mapped_data, &common.vertices);
            _ = c.vkUnmapMemory(device, vertex_buffer_memory);

            logger.log(.Debug, "created vertex buffer successfully", .{});
        }
        errdefer c.vkFreeMemory(device, vertex_buffer_memory, null);
        errdefer c.vkDestroyBuffer(device, vertex_buffer, null);

        var command_buffers: []c.VkCommandBuffer = undefined;
        {
            command_buffers = try buffer_mod.createCommandBuffers(allocator, device, command_pool, config.max_frames_in_flight);
            logger.log(.Debug, "created command buffers(amount: {d}) successfully", .{config.max_frames_in_flight});
        }
        errdefer c.vkFreeCommandBuffers(device, command_pool, config.max_frames_in_flight, &command_buffers[0]);

        const semaphores_image_available: []c.VkSemaphore = try sync_mod.createSemaphores(
            allocator,
            device,
            config.max_frames_in_flight,
        );
        errdefer for (semaphores_image_available) |semaphore| c.vkDestroySemaphore(device, semaphore, null);
        const semaphores_render_finished: []c.VkSemaphore = try sync_mod.createSemaphores(
            allocator,
            device,
            config.max_frames_in_flight,
        );
        errdefer for (semaphores_render_finished) |semaphore| c.vkDestroySemaphore(device, semaphore, null);
        const fences_in_flight: []c.VkFence = try sync_mod.createFences(
            allocator,
            device,
            config.max_frames_in_flight,
            true,
        );
        errdefer for (fences_in_flight) |fence| c.vkDestroyFence(device, fence, null);
        logger.log(.Debug, "Semaphores and Fences(amount: {d}) created successfully", .{config.max_frames_in_flight});

        logger.log(.Debug, "VkContext created successfully", .{});

        return VkContext{
            .instance = self.instance,
            .maybe_debug_messenger = self.maybe_debug_messenger,

            .get_window_fb_size_callback = get_window_frame_buffer_size_fn,
            .get_window_fb_size_context = get_window_frame_buffer_size_context,

            .queue_family_indices = queue_family_indices,
            .graphics_queue = graphics_queue,
            .present_queue = present_queue,
            .device = device,

            .surface = self.surface,

            .swapchain_state = swapchain_state,

            .graphics_pipeline = graphics_pipeline,
            .graphics_pipeline_layout = graphics_pipeline_layout,
            .render_pass = render_pass,

            .swapchain_framebuffers = swapchain_framebuffers,

            .vertex_buffer = vertex_buffer,
            .vertex_buffer_memory = vertex_buffer_memory,

            .command_pool = command_pool,
            .command_buffers = command_buffers,

            .semaphores_image_available = semaphores_image_available,
            .semaphores_render_finished = semaphores_render_finished,
            .fences_in_flight = fences_in_flight,

            .current_frame = 0,
            .framebuffer_resized = false,
        };
    }

    fn validate(
        self: *@This(),
    ) !void {
        std.debug.assert(self.instance != null);
        std.debug.assert(self.get_window_fb_size_callback != null);
        std.debug.assert(self.get_window_fb_size_context != null);
    }
};

pub fn createVkContextBuilder(
    required_extensions: []const [*c]const u8,
) !VkContextBuilder {
    var instance: c.VkInstance = undefined;
    {
        var total_required_extensions: [][*c]const u8 = undefined;
        {
            defer allocator.free(required_extensions);

            var additional_required_extensions: [][*c]const u8 = undefined;
            if (config.enable_validation_layers) {
                additional_required_extensions = try allocator.alloc([*c]const u8, 1);
                additional_required_extensions[0] = c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME;
            } else {
                additional_required_extensions = .{};
            }
            defer allocator.free(additional_required_extensions);

            total_required_extensions = try allocator.alloc(
                [*c]const u8,
                additional_required_extensions.len + required_extensions.len,
            );

            for (required_extensions, 0..) |extensions, i|
                total_required_extensions[i] = extensions;

            for (additional_required_extensions, required_extensions.len..) |extension, i|
                total_required_extensions[i] = extension;
        }
        defer allocator.free(total_required_extensions);

        instance = try instance_mod.createInstance(total_required_extensions);

        logger.log(.Debug, "required extensions: {any}", .{required_extensions});
        logger.log(.Debug, "Instance created successfully: 0x{x}", .{@intFromPtr(instance)});
        if (config.enable_validation_layers)
            logger.log(.Debug, "enabled validation layers: {any}", .{config.validation_layers});
    }
    errdefer c.vkDestroyInstance(instance, null);

    const maybe_debug_messenger =
        if (config.enable_validation_layers)
            try validation_layers.createDebugMessenger(instance)
        else
            null;
    errdefer if (config.enable_validation_layers) validation_layers.destroyDebugUtilsMessengerExt(instance, maybe_debug_messenger, null);

    logger.log(.Debug, "VkContextIncompleteInit created successfully", .{});

    return .{
        .instance = instance,
        .maybe_debug_messenger = maybe_debug_messenger,

        .surface = null,
        .get_window_fb_size_callback = null,
        .get_window_fb_size_context = null,
    };
}
