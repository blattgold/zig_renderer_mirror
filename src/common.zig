const std = @import("std");
const util = @import("util.zig");

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

    SwapChainSupportDetailsQueryFailure,
    SwapChainCreateFailure,
    SwapChainGetImagesFailure,

    ImageViewCreateError,
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

pub const SwapChainSupportDetails = struct {
    capabilities: c.VkSurfaceCapabilitiesKHR,
    formats: []c.VkSurfaceFormatKHR,
    present_modes: []c.VkPresentModeKHR,

    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        allocator.free(self.formats);
        allocator.free(self.present_modes);
    }
};

pub const c = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_vulkan.h");
    @cInclude("vulkan/vulkan.h");
});

const Vec2 = util.Vec2;
const Vec3 = util.Vec3;

pub const Vertex = extern struct {
    pos: Vec2,
    col: Vec3,

    pub fn get_binding_description() c.VkVertexInputBindingDescription {
        return .{
            .binding = 0,
            .stride = @sizeOf(Vertex),
            .inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
        };
    }

    pub fn get_attribute_descriptions() [2]c.VkVertexInputAttributeDescription {
        return .{ .{
            .binding = 0,
            .location = 0,
            .format = c.VK_FORMAT_R32G32_SFLOAT,
            .offset = @offsetOf(Vertex, "pos"),
        }, .{
            .binding = 0,
            .location = 1,
            .format = c.VK_FORMAT_R32G32B32_SFLOAT,
            .offset = @offsetOf(Vertex, "col"),
        } };
    }
};

// temporary TODO: replace
pub const vertices = [_]Vertex{
    .{ .pos = Vec2.new(0, -0.5), .col = Vec3.new(1, 0, 0) },
    .{ .pos = Vec2.new(0.5, 0.5), .col = Vec3.new(0, 1, 0) },
    .{ .pos = Vec2.new(-0.5, 0.5), .col = Vec3.new(0, 0, 1) },
};

pub const vertices_raw = [_][5]f32{
    .{ 0, -0.5, 1, 0, 0 },
    .{ 0.5, 0.5, 0, 1, 0 },
    .{ -0.5, 0.5, 0, 0, 1 },
};

pub const WindowFrameBufferSize = struct {
    w: u32,
    h: u32,
};

pub fn read_file(
    allocator: std.mem.Allocator,
    file_path: []const u8,
) ![]u8 {
    var file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const stat = try file.stat();
    const buffer: []u8 = try allocator.alloc(u8, stat.size);

    errdefer allocator.free(buffer);
    var reader = file.readerStreaming(buffer);
    _ = reader.interface.adaptToOldInterface().readAll(buffer) catch |err| {
        if (err == std.Io.Reader.Error.ReadFailed)
            return err;
    };
    return buffer;
}
