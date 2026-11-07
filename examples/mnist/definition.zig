const z = @import("zinn");
pub fn Structure(comptime cnn: bool) type {
    return if (cnn) z.ImageDefinition(.{ .height = 16, .width = 16, .channels = 1 }, &.{
        .{ .kind = .conv2d, .units = 2, .kernel = 3, .activation = .relu },
        .{ .kind = .average_pool2d, .kernel = 2, .stride = 2 },
        .{ .units = 10 },
    }) else z.Definition(256, &.{ .{ .units = 16, .activation = .relu }, .{ .units = 10 } });
}
