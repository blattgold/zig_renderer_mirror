const common = @import("common.zig");

const c = common.c;

pub fn create_semaphore(device: c.VkDevice) !c.VkSemaphore {
    const semaphore_create_info: c.VkSemaphoreCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    };

    var semaphore: c.VkSemaphore = undefined;
    if (c.vkCreateSemaphore(device, &semaphore_create_info, null, &semaphore) != c.VK_SUCCESS)
        return error.CreateSemaphore;

    return semaphore;
}

pub fn create_fence(device: c.VkDevice) !c.VkFence {
    const fence_create_info: c.VkFenceCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
    };

    var fence: c.VkFence = undefined;
    if (c.vkCreateFence(device, &fence_create_info, null, &fence) != c.VK_SUCCESS)
        return error.CreateFence;

    return fence;
}
