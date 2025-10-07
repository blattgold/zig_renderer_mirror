const common = @import("common.zig");
const config = @import("config.zig");
const v_layers = @import("v_layers.zig");

const c = common.c;

const VulkanError = common.VulkanError;

pub fn create_instance(extensions: [][*c]const u8) !c.VkInstance {
    if (config.enable_validation_layers)
        try v_layers.check_validation_layer_support();

    var app_info: c.VkApplicationInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = config.app_name,
        .applicationVersion = c.VK_MAKE_VERSION(0, 1, 0),
        .pEngineName = "No Engine",
        .engineVersion = c.VK_MAKE_VERSION(1, 0, 0),
        .apiVersion = c.VK_API_VERSION_1_0,
    };

    var inst_info: c.VkInstanceCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app_info,
        .enabledExtensionCount = @intCast(extensions.len),
        .ppEnabledExtensionNames = extensions.ptr,
    };

    var debug_create_info: c.VkDebugUtilsMessengerCreateInfoEXT = undefined;
    if (config.enable_validation_layers) {
        inst_info.enabledLayerCount = config.validation_layers.len;
        inst_info.ppEnabledLayerNames = @ptrCast(config.validation_layers.ptr);

        debug_create_info = v_layers.create_debug_utils_messenger_create_info_ext();
        inst_info.pNext = @ptrCast(&debug_create_info);
    } else {
        inst_info.enabledLayerCount = 0;
    }

    var instance: c.VkInstance = undefined;
    if (c.vkCreateInstance(&inst_info, null, &instance) != c.VK_SUCCESS)
        return VulkanError.InstanceCreationFailure;

    return instance;
}
