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
