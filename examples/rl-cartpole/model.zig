const z = @import("zinn");
pub const Structure = z.Definition(4, &.{ .{ .units = 16, .activation = .relu }, .{ .units = 16, .activation = .relu }, .{ .units = 2 } });
