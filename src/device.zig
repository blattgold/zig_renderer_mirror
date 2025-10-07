const common = @import("common.zig");
const v_layers = @import("v_layers.zig");
const config = @import("config.zig");
const logger = @import("logger.zig");

const c = common.c;

const VulkanError = common.VulkanError;
const QueueFamilyIndices = common.QueueFamilyIndices;

pub fn create_logical_device(physical_device: c.VkPhysicalDevice, indices: QueueFamilyIndices) !c.VkDevice {
    var queue_create_info: c.VkDeviceQueueCreateInfo = .{};
    queue_create_info.sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    queue_create_info.queueFamilyIndex = indices.graphics_family;
    queue_create_info.queueCount = 1;

    var queue_priority: f32 = 1.0;
    queue_create_info.pQueuePriorities = &queue_priority;

    var features: c.VkPhysicalDeviceFeatures = .{};

    var device_create_info = c.VkDeviceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pQueueCreateInfos = &queue_create_info,
        .pEnabledFeatures = &features,
        .queueCreateInfoCount = 1,
        .enabledExtensionCount = 0,
    };

    // this is no longer necessary, but it is good to do this for backwards compatability
    if (config.enable_validation_layers) {
        device_create_info.enabledLayerCount = config.validation_layers.len;
        device_create_info.ppEnabledLayerNames = @ptrCast(config.validation_layers.ptr);
    } else {
        device_create_info.enabledLayerCount = 0;
    }

    var device: c.VkDevice = undefined;
    if (c.vkCreateDevice(physical_device, &device_create_info, null, &device) != c.VK_SUCCESS)
        return VulkanError.CreateDeviceFailure;

    return device;
}
