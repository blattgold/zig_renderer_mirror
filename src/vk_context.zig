const std = @import("std");

const config = @import("config.zig");
const logger = @import("logger.zig");
const common = @import("common.zig");
const p_device_mod = @import("p_device.zig");
const v_layers = @import("v_layers.zig");
const instance_mod = @import("instance.zig");
const device_mod = @import("device.zig");

const c = common.c;

const VulkanError = common.VulkanError;
const ArrayList = std.ArrayList;
const QueueFamilyIndices = common.QueueFamilyIndices;

const allocator = std.heap.page_allocator;

pub const VkContext = struct {
    vk_instance: c.VkInstance,
    debug_messenger: c.VkDebugUtilsMessengerEXT,
    device: c.VkDevice,
    graphics_queue: c.VkQueue,

    vk_surface: c.VkSurfaceKHR,

    pub fn init(required_extensions: *ArrayList([*c]const u8)) !VkContext {
        if (config.enable_validation_layers)
            try required_extensions.append(allocator, c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME);

        const vk_instance = try VkContext.create_vk_instance(required_extensions);

        const debug_messenger = if (config.enable_validation_layers) try v_layers.create_debug_messenger(vk_instance) else null;

        const physical_device_result = try VkContext.create_physical_device_and_queue_indices(vk_instance);
        const physical_device = physical_device_result.physical_device;
        const queue_indices = physical_device_result.indices;

        const device = try VkContext.create_device(physical_device, queue_indices);
        const graphics_queue = VkContext.get_graphics_queue(device, queue_indices.graphics_family);

        return .{
            .vk_instance = vk_instance,
            .debug_messenger = debug_messenger,
            .device = device,
            .graphics_queue = graphics_queue,

            .vk_surface = null,
        };
    }

    pub fn deinit(self: @This()) void {
        if (self.vk_surface != null) {
            c.vkDestroySurfaceKHR(self.vk_instance, self.vk_surface, null);
        }
        c.vkDestroyDevice(self.device, null);
        if (self.debug_messenger != null) {
            v_layers.destroy_debug_utils_messenger_ext(self.vk_instance, self.debug_messenger, null);
        }
        c.vkDestroyInstance(self.vk_instance, null);
    }

    pub fn init_surface(self: *@This(), surface: c.VkSurfaceKHR) void {
        if (self.vk_surface == null) {
            logger.log(.Debug, "initialized surface: 0x{x}", .{@intFromPtr(surface)});
            self.vk_surface = surface;
        } else {
            logger.log(.Warn, "attempted to initialize surface after it has been already initialized, ignoring.", .{});
        }
    }

    fn get_graphics_queue(device: c.VkDevice, graphics_family_index: u32) c.VkQueue {
        var graphics_queue: c.VkQueue = undefined;
        c.vkGetDeviceQueue(device, graphics_family_index, 0, &graphics_queue);
        logger.log(.Debug, "graphics queue: 0x{x}", .{@intFromPtr(graphics_queue)});
        return graphics_queue;
    }

    fn create_device(
        physical_device: c.VkPhysicalDevice,
        queue_indices: QueueFamilyIndices,
    ) !c.VkDevice {
        const device = try device_mod.create_logical_device(physical_device, queue_indices);
        logger.log(.Debug, "logical device created successfully: 0x{x}", .{@intFromPtr(device)});
        return device;
    }

    fn create_physical_device_and_queue_indices(instance: c.VkInstance) !p_device_mod.PDeviceResult {
        const physical_devices = try p_device_mod.find_physical_devices(allocator, instance);
        defer allocator.free(physical_devices);
        return try p_device_mod.select_suitable_physical_device(physical_devices);
    }

    fn create_vk_instance(required_extensions: *std.ArrayList([*c]const u8)) !c.VkInstance {
        const required_extensions_slice = try required_extensions.toOwnedSlice(allocator);
        logger.log(.Debug, "required extensions: {any}", .{required_extensions_slice});

        const instance = try instance_mod.create_instance(required_extensions_slice);
        defer allocator.free(required_extensions_slice);

        logger.log(.Debug, "Instance created successfully: 0x{x}", .{@intFromPtr(instance)});
        if (config.enable_validation_layers)
            logger.log(.Debug, "enabled validation layers: {any}", .{config.validation_layers});

        return instance;
    }
};
