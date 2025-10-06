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

    GetRequiredExtensionsFailure,
    EnableValidationLayersFailure,
    SetupDebugMessengerFailure,
};

pub const QueueFamilyIndices = struct {
    graphics_family: ?u32,

    pub fn is_complete(self: @This()) bool {
        return self.graphics_family != null;
    }
};

pub const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_vulkan.h");
    @cInclude("vulkan/vulkan.h");
});
