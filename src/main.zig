const std = @import("std");
const common = @import("common.zig");
const vk_context_mod = @import("vk_context.zig");

const c = common.c;

const ArrayList = std.ArrayList;

fn get_required_extensions() !ArrayList([*c]const u8) {
    const allocator = std.heap.page_allocator;

    var extension_count_sdl: u32 = undefined;
    const extensions_sdl = c.SDL_Vulkan_GetInstanceExtensions(&extension_count_sdl);

    var extensions: ArrayList([*c]const u8) = .{};
    try extensions.appendSlice(allocator, extensions_sdl[0..extension_count_sdl]);

    return extensions;
}

pub fn main() !void {
    _ = c.SDL_Init(c.SDL_INIT_VIDEO);
    _ = c.SDL_Vulkan_LoadLibrary(null);
    //const window: ?*c.SDL_Window = c.SDL_CreateWindow(APP_NAME, W_WIDTH, W_HEIGHT, c.SDL_WINDOW_VULKAN);
    var required_extensions = try get_required_extensions();

    var vk_context = try vk_context_mod.VkContext.init(&required_extensions);
    vk_context.deinit();
    c.SDL_Quit();
}
