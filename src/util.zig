const std = @import("std");

pub const Vec2 = packed struct {
    x: f32,
    y: f32,

    pub fn new(x_: f32, y_: f32) @This() {
        return @This(){ .x = x_, .y = y_ };
    }

    pub fn addVec2(self: @This(), other: @This()) @This() {
        return @This(){
            .x = self.x + other.x,
            .y = self.y + other.y,
        };
    }
};

pub const Vec3 = packed struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn new(x_: f32, y_: f32, z_: f32) @This() {
        return @This(){ .x = x_, .y = y_, .z = z_ };
    }

    pub fn addVec3(self: @This(), other: @This()) @This() {
        return @This(){
            .x = self.x + other.x,
            .y = self.y + other.y,
            .z = self.z + other.z,
        };
    }
};

pub const Vec4 = packed struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,

    pub fn new(x_: f32, y_: f32, z_: f32, w_: f32) @This() {
        return @This(){ .x = x_, .y = y_, .z = z_, .w = w_ };
    }

    pub fn addVec4(self: @This(), other: @This()) @This() {
        return @This(){
            .x = self.x + other.x,
            .y = self.y + other.y,
            .z = self.z + other.z,
        };
    }
};

pub const Mat4 = packed struct {
    m00: f32,
    m10: f32,
    m20: f32,
    m30: f32,
    m01: f32,
    m11: f32,
    m21: f32,
    m31: f32,
    m02: f32,
    m12: f32,
    m22: f32,
    m32: f32,
    m03: f32,
    m13: f32,
    m23: f32,
    m33: f32,

    pub fn fromTups(
        t0: std.meta.Tuple(&.{ f32, f32, f32, f32 }),
        t1: std.meta.Tuple(&.{ f32, f32, f32, f32 }),
        t2: std.meta.Tuple(&.{ f32, f32, f32, f32 }),
        t3: std.meta.Tuple(&.{ f32, f32, f32, f32 }),
    ) @This() {
        return .{
            .m00 = t0[0],
            .m01 = t0[1],
            .m02 = t0[2],
            .m03 = t0[3],

            .m10 = t1[0],
            .m11 = t1[1],
            .m12 = t1[2],
            .m13 = t1[3],

            .m20 = t2[0],
            .m21 = t2[1],
            .m22 = t2[2],
            .m23 = t2[3],

            .m30 = t3[0],
            .m31 = t3[1],
            .m32 = t3[2],
            .m33 = t3[3],
        };
    }

    pub fn fromVec4s(
        v0: Vec4,
        v1: Vec4,
        v2: Vec4,
        v3: Vec4,
    ) @This() {
        return .{
            .m00 = v0.x,
            .m01 = v0.y,
            .m02 = v0.z,
            .m03 = v0.w,

            .m10 = v1.x,
            .m11 = v1.y,
            .m12 = v1.z,
            .m13 = v1.w,

            .m20 = v2.x,
            .m21 = v2.y,
            .m22 = v2.z,
            .m23 = v2.w,

            .m30 = v3.x,
            .m31 = v3.y,
            .m32 = v3.z,
            .m33 = v3.w,
        };
    }

    pub fn addMat4(
        self: @This(),
        other: @This(),
    ) @This() {
        return .{
            .m00 = self.m00 + other.m00,
            .m01 = self.m01 + other.m01,
            .m02 = self.m02 + other.m02,
            .m03 = self.m03 + other.m03,

            .m10 = self.m10 + other.m10,
            .m11 = self.m11 + other.m11,
            .m12 = self.m12 + other.m12,
            .m13 = self.m13 + other.m13,

            .m20 = self.m20 + other.m20,
            .m21 = self.m21 + other.m21,
            .m22 = self.m22 + other.m22,
            .m23 = self.m23 + other.m23,

            .m30 = self.m30 + other.m30,
            .m31 = self.m31 + other.m31,
            .m32 = self.m32 + other.m32,
            .m33 = self.m33 + other.m33,
        };
    }

    pub fn multMat4(
        self: @This(),
        other: @This(),
    ) @This() {
        return .{
            .m00 = self.m00 * other.m00 + self.m01 * other.m10 + self.m02 * other.m20 + self.m03 * other.m30,
            .m01 = self.m00 * other.m01 + self.m01 * other.m11 + self.m02 * other.m21 + self.m03 * other.m31,
            .m02 = self.m00 * other.m02 + self.m01 * other.m12 + self.m02 * other.m22 + self.m03 * other.m32,
            .m03 = self.m00 * other.m03 + self.m01 * other.m13 + self.m02 * other.m23 + self.m03 * other.m33,

            .m10 = self.m10 * other.m00 + self.m11 * other.m10 + self.m12 * other.m20 + self.m13 * other.m30,
            .m11 = self.m10 * other.m01 + self.m11 * other.m11 + self.m12 * other.m21 + self.m13 * other.m31,
            .m12 = self.m10 * other.m02 + self.m11 * other.m12 + self.m12 * other.m22 + self.m13 * other.m32,
            .m13 = self.m10 * other.m03 + self.m11 * other.m13 + self.m12 * other.m23 + self.m13 * other.m33,

            .m20 = self.m20 * other.m00 + self.m21 * other.m10 + self.m22 * other.m20 + self.m23 * other.m30,
            .m21 = self.m20 * other.m01 + self.m21 * other.m11 + self.m22 * other.m21 + self.m23 * other.m31,
            .m22 = self.m20 * other.m02 + self.m21 * other.m12 + self.m22 * other.m22 + self.m23 * other.m32,
            .m23 = self.m20 * other.m03 + self.m21 * other.m13 + self.m22 * other.m23 + self.m23 * other.m33,

            .m30 = self.m30 * other.m00 + self.m31 * other.m10 + self.m32 * other.m20 + self.m33 * other.m30,
            .m31 = self.m30 * other.m01 + self.m31 * other.m11 + self.m32 * other.m21 + self.m33 * other.m31,
            .m32 = self.m30 * other.m02 + self.m31 * other.m12 + self.m32 * other.m22 + self.m33 * other.m32,
            .m33 = self.m30 * other.m03 + self.m31 * other.m13 + self.m32 * other.m23 + self.m33 * other.m33,
        };
    }
};
