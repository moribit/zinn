const zinn = @import("zinn");
pub const Image = zinn.ImageDefinition(.{ .height = 4, .width = 4, .channels = 1 }, &.{
    .{ .kind = .conv2d, .units = 2, .kernel = 3, .activation = .relu },
    .{ .kind = .average_pool2d, .kernel = 2, .stride = 2 },
    .{ .units = 2 },
});
