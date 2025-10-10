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

pub fn create_command_buffer(
    device: c.VkDevice,
    command_pool: c.VkCommandPool,
) !c.VkCommandBuffer {
    const command_buffer_allocate_info: c.VkCommandBufferAllocateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = command_pool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };

    var command_buffer: c.VkCommandBuffer = undefined;
    if (c.vkAllocateCommandBuffers(device, &command_buffer_allocate_info, &command_buffer) != c.VK_SUCCESS)
        return error.AllocateCommandBuffers;

    return command_buffer;
}
