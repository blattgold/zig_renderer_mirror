const std = @import("std");

const common = @import("common.zig");

const c = common.c;

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
