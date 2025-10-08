pub const LogLevel = enum(u2) {
    Debug,
    Info,
    Warn,
    Error,
};

pub const VulkanError = error{
    InstanceCreationFailure,

    NoSuitablePhysicalDevice,
    NoPhysicalDevices,

    CreateDeviceFailure,

    GetRequiredExtensionsFailure,
    EnableValidationLayersFailure,
    SetupDebugMessengerFailure,
};

pub const QueueFamilyIndices = struct {
    graphics_family: u32,
    present_family: u32,
};

pub const QueueFamilyIndicesOpt = struct {
    graphics_family: ?u32,
    present_family: ?u32,

    pub fn is_complete(self: @This()) bool {
        return self.graphics_family != null and self.present_family != null;
    }

    pub fn to_queue_family_indices(self: @This()) ?QueueFamilyIndices {
        if (self.is_complete()) {
            return QueueFamilyIndices{
                .graphics_family = self.graphics_family.?,
                .present_family = self.present_family.?,
            };
        } else {
            return null;
        }
    }
};

pub const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_vulkan.h");
    @cInclude("vulkan/vulkan.h");
});
