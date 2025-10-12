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

const allocator = std.heap.page_allocator;

fn get_required_extensions() !ArrayList([*c]const u8) {
    var extension_count_sdl: u32 = undefined;
    const extensions_sdl = c.SDL_Vulkan_GetInstanceExtensions(&extension_count_sdl);

    var extensions: ArrayList([*c]const u8) = .{};
    try extensions.appendSlice(allocator, extensions_sdl[0..extension_count_sdl]);

    return extensions;
}

fn sdl_get_window_buffer_size(context: ?*anyopaque) WindowFrameBufferSize {
    std.debug.assert(context != null);
    const window = @as(?*c.SDL_Window, @ptrCast(context.?));

    var w: c_int = undefined;
    var h: c_int = undefined;
    if (!c.SDL_GetWindowSize(window, &w, &h))
        @panic("failed to get window size");

    return WindowFrameBufferSize{
        .w = @intCast(w),
        .h = @intCast(h),
    };
}

pub fn main() !void {
    if (c.SDL_Init(c.SDL_INIT_VIDEO) == false)
        return SDLError.SDL_InitFailure;
    defer c.SDL_Quit();

    if (c.SDL_Vulkan_LoadLibrary(null) == false)
        return SDLError.SDL_Vulkan_LoadLibraryFailure;
    defer c.SDL_Vulkan_UnloadLibrary();

    const window: ?*c.SDL_Window = c.SDL_CreateWindow(config.app_name, config.w_width, config.w_height, c.SDL_WINDOW_VULKAN | c.SDL_WINDOW_RESIZABLE);
    var required_extensions = try get_required_extensions();

    const required_extensions_slice = try required_extensions.toOwnedSlice(allocator);

    var vk_context_builder = try vk_context_mod.create_vk_context_builder(required_extensions_slice);
    allocator.free(required_extensions_slice);

    const instance = vk_context_builder.get_instance();

    var surface: c.VkSurfaceKHR = undefined;
    if (c.SDL_Vulkan_CreateSurface(window, instance, null, &surface) == false)
        return SDLError.SDL_Vulkan_CreateSurfaceFailure;

    var vk_context = try vk_context_builder
        .set_surface(surface)
        .set_get_window_frame_buffer_size_fn(sdl_get_window_buffer_size)
        .set_get_window_frame_buffer_size_context(@ptrCast(window))
        .build();

    defer vk_context.deinit();

    try main_loop(&vk_context, window);

    _ = c.vkDeviceWaitIdle(vk_context.device);
}

fn main_loop(vk_context: *VkContext, window: ?*c.SDL_Window) !void {
    var event: c.SDL_Event = undefined;
    var quit: bool = false;

    var t_total: i64 = 0;
    var t_start = std.time.microTimestamp();
    logger.log(.Debug, "entering main loop...", .{});
    logger.log(.Debug, "t_start: {d}us", .{t_start});
    while (!quit) {
        // events
        while (c.SDL_PollEvent(&event)) {
            if (event.type == c.SDL_EVENT_QUIT) {
                quit = true;
            } else if (event.type == c.SDL_EVENT_WINDOW_RESIZED) {
                _ = c.SDL_SetWindowSize(window, event.window.data1, event.window.data2);
                vk_context.frame_buffer_resized = true;
            }
        }

        // rendering
        const t_now = std.time.microTimestamp();
        const t_delta = t_now - t_start;
        t_total += t_delta;
        try vk_context.render();
        t_start = t_now;
    }
    logger.log(.Debug, "t_total: {d}us, {d}ms, {d}s", .{ t_total, @as(f64, @floatFromInt(t_total)) / 1000, @as(f64, @floatFromInt(t_total)) / 1000 / 1000 });
    logger.log(.Debug, "t_end: {d}us", .{t_start});
}
