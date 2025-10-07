const common = @import("common.zig");
const vk_context_mod = @import("vk_context.zig");

const c = common.c;

pub fn main() !void {
    _ = c.SDL_Init(c.SDL_INIT_VIDEO);
    _ = c.SDL_Vulkan_LoadLibrary(null);
    //const window: ?*c.SDL_Window = c.SDL_CreateWindow(APP_NAME, W_WIDTH, W_HEIGHT, c.SDL_WINDOW_VULKAN);

    var vk_context = try vk_context_mod.VkContext.init();
    vk_context.deinit();
    c.SDL_Quit();
}
