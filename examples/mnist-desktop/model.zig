const z = @import("zinn");
pub const Structure = z.Definition(256, &.{ .{ .units = 32, .activation = .relu }, .{ .units = 10 } });
