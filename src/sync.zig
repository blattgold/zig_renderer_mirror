const std = @import("std");

const common = @import("common.zig");

const c = common.c;

pub fn create_semaphores(
    allocator: std.mem.Allocator,
    device: c.VkDevice,
    semaphore_amount: u32,
) ![]c.VkSemaphore {
    const semaphore_create_info: c.VkSemaphoreCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    };

    const semaphores: []c.VkSemaphore = try allocator.alloc(c.VkSemaphore, semaphore_amount);
    errdefer allocator.free(semaphores);
    for (0..semaphore_amount) |i|
        if (c.vkCreateSemaphore(device, &semaphore_create_info, null, &semaphores[i]) != c.VK_SUCCESS)
            return error.CreateSemaphore;

    return semaphores;
}

pub fn create_fences(
    allocator: std.mem.Allocator,
    device: c.VkDevice,
    fence_amount: u32,
    create_signaled: bool,
) ![]c.VkFence {
    const fence_create_info: c.VkFenceCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = if (create_signaled) c.VK_FENCE_CREATE_SIGNALED_BIT else 0,
    };

    const fences: []c.VkFence = try allocator.alloc(c.VkFence, fence_amount);
    errdefer allocator.free(fences);
    for (0..fence_amount) |i|
        if (c.vkCreateFence(device, &fence_create_info, null, &fences[i]) != c.VK_SUCCESS)
            return error.CreateFence;

    return fences;
}
