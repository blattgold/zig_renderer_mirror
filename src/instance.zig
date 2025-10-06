const common = @import("common.zig");
const constants = @import("constants.zig");
const v_layers = @import("v_layers.zig");
const logger = @import("logger.zig");

const c = common.c;

const VulkanError = common.VulkanError;

pub fn create_instance(extensions: [][*c]const u8) !c.VkInstance {
    if (constants.ENABLE_VALIDATION_LAYERS)
        try v_layers.check_validation_layer_support();

    var app_info: c.VkApplicationInfo = .{};

    app_info.sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO;
    app_info.pApplicationName = constants.APP_NAME;
    app_info.applicationVersion = c.VK_MAKE_VERSION(0, 1, 0);
    app_info.pEngineName = "No Engine";
    app_info.engineVersion = c.VK_MAKE_VERSION(1, 0, 0);
    app_info.apiVersion = c.VK_API_VERSION_1_0;

    var inst_info: c.VkInstanceCreateInfo = .{};

    inst_info.sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    inst_info.pApplicationInfo = &app_info;
    inst_info.enabledExtensionCount = @intCast(extensions.len);
    inst_info.ppEnabledExtensionNames = extensions.ptr;

    var debug_create_info: c.VkDebugUtilsMessengerCreateInfoEXT = .{};
    if (constants.ENABLE_VALIDATION_LAYERS) {
        inst_info.enabledLayerCount = constants.VALIDATION_LAYERS.len;
        inst_info.ppEnabledLayerNames = @ptrCast(constants.VALIDATION_LAYERS.ptr);

        v_layers.populate_debug_messeneger_create_info(&debug_create_info);
        inst_info.pNext = @ptrCast(&debug_create_info);

        logger.log(.Debug, "enabled validation layers: {any}", .{constants.VALIDATION_LAYERS});
    } else {
        inst_info.enabledLayerCount = 0;
        inst_info.pNext = null;
    }

    var instance: c.VkInstance = undefined;
    if (c.vkCreateInstance(&inst_info, null, &instance) != c.VK_SUCCESS)
        return VulkanError.InstanceCreationFailure;

    logger.log(.Debug, "Instance created successfully", .{});
    return instance;
}
