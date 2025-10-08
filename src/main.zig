const std = @import("std");
const common = @import("common.zig");
const config = @import("config.zig");
const vk_context_mod = @import("vk_context.zig");

const c = common.c;

const ArrayList = std.ArrayList;
const VkContext = vk_context_mod.VkContext;
const VkContextIncompleteInit = vk_context_mod.VkContextIncompleteInit;

const SDLError = error{
    SDL_InitFailure,
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

    if (c.SDL_Vulkan_LoadLibrary(null) == false)
        return SDLError.SDL_Vulkan_LoadLibraryFailure;

    const window: ?*c.SDL_Window = c.SDL_CreateWindow(config.app_name, config.w_width, config.w_height, c.SDL_WINDOW_VULKAN);
    var required_extensions = try get_required_extensions();

    var vk_context: VkContext = undefined;
    {
        const vk_context_incomplete: VkContextIncompleteInit = try VkContext.init_incomplete(&required_extensions);

        var vk_surface: c.VkSurfaceKHR = undefined;
        if (c.SDL_Vulkan_CreateSurface(window, vk_context_incomplete.vk_instance, null, &vk_surface) == false)
            return SDLError.SDL_Vulkan_CreateSurfaceFailure;

        vk_context = try vk_context_incomplete.init_complete(vk_surface);
    }

    vk_context.deinit();
    c.SDL_Quit();
}
