const std = @import("std");
const common = @import("common.zig");
const config = @import("config.zig");
const vk_context_mod = @import("vk_context.zig");
const logger = @import("logger.zig");

const c = common.c;

const ArrayList = std.ArrayList;
const VkContext = vk_context_mod.VkContext;
const VkContextIncompleteInit = vk_context_mod.VkContextIncompleteInit;
const WindowFrameBufferSize = common.WindowFrameBufferSize;

const SDLError = error{
    SDL_InitFailure,
    SDL_GetWindowSizeInPixelsFailure,
    SDL_Vulkan_LoadLibraryFailure,
    SDL_Vulkan_CreateSurfaceFailure,
};

fn get_required_extensions() !ArrayList([*c]const u8) {
    const allocator = std.heap.page_allocator;

    var extension_count_sdl: u32 = undefined;
    const extensions_sdl = c.SDL_Vulkan_GetInstanceExtensions(&extension_count_sdl);

    var extensions: ArrayList([*c]const u8) = .{};
    try extensions.appendSlice(allocator, extensions_sdl[0..extension_count_sdl]);

    return extensions;
}

pub fn main() !void {
    if (c.SDL_Init(c.SDL_INIT_VIDEO) == false)
        return SDLError.SDL_InitFailure;
    defer c.SDL_Quit();

    if (c.SDL_Vulkan_LoadLibrary(null) == false)
        return SDLError.SDL_Vulkan_LoadLibraryFailure;
    defer c.SDL_Vulkan_UnloadLibrary();

    const window: ?*c.SDL_Window = c.SDL_CreateWindow(config.app_name, config.w_width, config.w_height, c.SDL_WINDOW_VULKAN);
    var required_extensions = try get_required_extensions();

    var vk_context: VkContext = undefined;
    {
        const vk_context_incomplete: VkContextIncompleteInit = try VkContext.init_incomplete(&required_extensions);

        var vk_surface: c.VkSurfaceKHR = undefined;
        if (c.SDL_Vulkan_CreateSurface(window, vk_context_incomplete.vk_instance, null, &vk_surface) == false)
            return SDLError.SDL_Vulkan_CreateSurfaceFailure;

        vk_context = try vk_context_incomplete.init_complete(
            vk_surface,
            .{ .h = config.w_height, .w = config.w_width },
        );
    }
    defer vk_context.deinit();

    var t_total: i64 = 0;
    var t_start = std.time.microTimestamp();
    logger.log(.Debug, "entering main loop...", .{});
    logger.log(.Debug, "t_start: {d}", .{t_start});
    while (t_total < 5 * 1000 * 1000) {
        const t_now = std.time.microTimestamp();
        const t_delta = t_now - t_start;
        t_total += t_delta;
        try vk_context.render();
        t_start = t_now;
    }
    logger.log(.Debug, "t_end: {d}", .{t_start});

    _ = c.vkDeviceWaitIdle(vk_context.device);
}
