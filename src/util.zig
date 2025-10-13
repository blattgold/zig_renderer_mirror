pub const Vec2 = struct {
    content: f32[2],

    pub fn x(self: @This()) f32 {
        self.content[0];
    }

    pub fn y(self: @This()) f32 {
        self.content[1];
    }

    pub fn new(x_: f32, y_: f32) @This() {
        return @This(){ .content = .{ x_, y_ } };
    }

    pub fn addVec2(self: @This(), other: @This()) @This() {
        return @This(){
            .x = self.x + other.x,
            .y = self.y + other.y,
        };
    }
};

pub const Vec3 = struct {
    content: f32[3],

    pub fn x(self: @This()) f32 {
        self.content[0];
    }

    pub fn y(self: @This()) f32 {
        self.content[1];
    }

    pub fn z(self: @This()) f32 {
        self.content[2];
    }

    pub fn new(x_: f32, y_: f32, z_: f32) @This() {
        return @This(){ .content = .{ x_, y_, z_ } };
    }

    pub fn addVec3(self: @This(), other: @This()) @This() {
        return @This(){
            .x = self.x + other.x,
            .y = self.y + other.y,
            .z = self.z + other.z,
        };
    }
};

pub const Vec4 = struct {
    content: f32[4],

    pub fn x(self: @This()) f32 {
        self.content[0];
    }

    pub fn y(self: @This()) f32 {
        self.content[1];
    }

    pub fn z(self: @This()) f32 {
        self.content[2];
    }

    pub fn w(self: @This()) f32 {
        self.content[3];
    }

    pub fn new(x_: f32, y_: f32, z_: f32, w_: f32) @This() {
        return @This(){ .content = .{ x_, y_, z_, w_ } };
    }

    pub fn addVec4(self: @This(), other: @This()) @This() {
        return @This(){
            .x = self.x + other.x,
            .y = self.y + other.y,
            .z = self.z + other.z,
        };
    }
};
