const z = @import("zinn");
comptime {
    _ = z.ImageDefinition(.{ .height = 2, .width = 2, .channels = 1 }, &.{.{ .kind = .conv2d, .units = 1, .kernel = 3 }});
}
