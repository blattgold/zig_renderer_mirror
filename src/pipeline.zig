const std = @import("std");

const common = @import("common.zig");

const c = common.c;

pub fn create_graphics_pipeline(
    vert_shader_module: c.VkShaderModule,
    frag_shader_module: c.VkShaderModule,
) !void {
    var shader_stage_create_infos: [2]c.VkPipelineShaderStageCreateInfo = undefined;

    {
        const vert_shader_stage_create_info: c.VkPipelineShaderStageCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
            .module = vert_shader_module,
            .pName = "main",
        };

        const frag_shader_stage_create_info: c.VkPipelineShaderStageCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
            .module = frag_shader_module,
            .pName = "main",
        };

        shader_stage_create_infos[0] = vert_shader_stage_create_info;
        shader_stage_create_infos[1] = frag_shader_stage_create_info;
    }
}

pub fn create_shader_module(
    device: c.VkDevice,
    shader_code: []u8,
) !c.VkShaderModule {
    const shader_module_create_info: c.VkShaderModuleCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = shader_code.len,
        .pCode = shader_code.ptr,
    };

    var shader_module: c.VkShaderModule = undefined;
    if (c.vkCreateShaderModule(device, &shader_module_create_info, null, &shader_module) != c.VK_SUCCESS)
        return error.CreateShaderModule;
    return shader_module;
}
