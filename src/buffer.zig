const std = @import("std");

const common = @import("common.zig");

const c = common.c;

const QueueFamilyIndices = common.QueueFamilyIndices;

pub fn create_framebuffers(
    allocator: std.mem.Allocator,
    device: c.VkDevice,
    render_pass: c.VkRenderPass,
    swap_chain_image_views: []c.VkImageView,
    swap_chain_extent: c.VkExtent2D,
) ![]c.VkFramebuffer {
    var swap_chain_frame_buffers: []c.VkFramebuffer = try allocator.alloc(c.VkFramebuffer, swap_chain_image_views.len);
    errdefer allocator.free(swap_chain_frame_buffers);

    for (swap_chain_image_views, 0..) |swap_chain_image_view, i| {
        const attachments: [1]c.VkImageView = .{
            swap_chain_image_view,
        };

        const framebuffer_create_info: c.VkFramebufferCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .renderPass = render_pass,
            .attachmentCount = 1,
            .pAttachments = &attachments,
            .width = swap_chain_extent.width,
            .height = swap_chain_extent.height,
            .layers = 1,
        };

        if (c.vkCreateFramebuffer(device, &framebuffer_create_info, null, &swap_chain_frame_buffers[i]) != c.VK_SUCCESS)
            return error.CreateFramebuffer;
    }

    return swap_chain_frame_buffers;
}

pub fn create_vertex_buffer(
    device: c.VkDevice,
) !c.VkBuffer {
    const vertex_buffer_create_info: c.VkBufferCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = @sizeOf(common.Vertex) * common.vertices.len,
        .usage = c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
    };

    var vertex_buffer: c.VkBuffer = undefined;
    if (c.vkCreateBuffer(device, &vertex_buffer_create_info, null, &vertex_buffer) != c.VK_SUCCESS)
        return error.CreateBuffer;

    return vertex_buffer;
}

pub fn alloc_vertex_buffer_memory(
    device: c.VkDevice,
    vertex_buffer_memory_requirements: c.VkMemoryRequirements,
    memory_type_index: u32,
) !c.VkDeviceMemory {
    const memory_allocate_info: c.VkMemoryAllocateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = vertex_buffer_memory_requirements.size,
        .memoryTypeIndex = memory_type_index,
    };

    var vertex_buffer_memory: c.VkDeviceMemory = undefined;
    if (c.vkAllocateMemory(device, &memory_allocate_info, null, &vertex_buffer_memory) != c.VK_SUCCESS)
        return error.AllocateMemory;

    return vertex_buffer_memory;
}

pub fn create_command_pool(
    device: c.VkDevice,
    queue_family_indices: QueueFamilyIndices,
) !c.VkCommandPool {
    const command_pool_create_info: c.VkCommandPoolCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = queue_family_indices.graphics_family,
    };

    var command_pool: c.VkCommandPool = undefined;
    if (c.vkCreateCommandPool(device, &command_pool_create_info, null, &command_pool) != c.VK_SUCCESS)
        return error.CreateCommandPool;

    return command_pool;
}

/// it is recommended to free and vkDestroy previous command buffers before creating new ones.
///
/// returned slice must be freed.
pub fn create_command_buffers(
    allocator: std.mem.Allocator,
    device: c.VkDevice,
    command_pool: c.VkCommandPool,
    command_buffer_amount: u32,
) ![]c.VkCommandBuffer {
    // requesting 0 buffers is a nonsensical request
    std.debug.assert(command_buffer_amount != 0);

    const command_buffer_allocate_info: c.VkCommandBufferAllocateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = command_pool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = command_buffer_amount,
    };

    var command_buffers: []c.VkCommandBuffer = try allocator.alloc(c.VkCommandBuffer, command_buffer_amount);
    errdefer allocator.free(command_buffers);

    if (c.vkAllocateCommandBuffers(device, &command_buffer_allocate_info, &command_buffers[0]) != c.VK_SUCCESS)
        return error.AllocateCommandBuffers;

    return command_buffers;
}

pub fn record_command_buffer(
    render_pass: c.VkRenderPass,
    command_buffer: c.VkCommandBuffer,
    swap_chain_extent: c.VkExtent2D,
    swap_chain_frame_buffers: []c.VkFramebuffer,
    image_index: u32,
    graphics_pipeline: c.VkPipeline,
    vertex_buffer: c.VkBuffer,
) !void {
    const command_buffer_begin_info: c.VkCommandBufferBeginInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = 0,
        .pInheritanceInfo = null,
    };

    if (c.vkBeginCommandBuffer(command_buffer, &command_buffer_begin_info) != c.VK_SUCCESS)
        return error.BeginCommandBuffer;

    const clear_color: c.VkClearValue = .{
        .color = .{
            .float32 = .{ 0, 0, 0, 0 },
        },
    };

    const render_pass_begin_info: c.VkRenderPassBeginInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
        .renderPass = render_pass,
        .framebuffer = swap_chain_frame_buffers[image_index],

        .renderArea = .{
            .offset = .{ .x = 0, .y = 0 },
            .extent = swap_chain_extent,
        },

        .clearValueCount = 1,
        .pClearValues = &clear_color,
    };

    c.vkCmdBeginRenderPass(command_buffer, &render_pass_begin_info, c.VK_SUBPASS_CONTENTS_INLINE);
    c.vkCmdBindPipeline(command_buffer, c.VK_PIPELINE_BIND_POINT_GRAPHICS, graphics_pipeline);

    var vertex_buffers: [1]c.VkBuffer = .{vertex_buffer};
    var offsets: [1]c.VkDeviceSize = .{0};
    c.vkCmdBindVertexBuffers(command_buffer, 0, 1, &vertex_buffers, &offsets);

    c.vkCmdDraw(command_buffer, @intCast(common.vertices.len), 1, 0, 0);
    c.vkCmdEndRenderPass(command_buffer);

    if (c.vkEndCommandBuffer(command_buffer) != c.VK_SUCCESS)
        return error.EndCommandBuffer;
}
