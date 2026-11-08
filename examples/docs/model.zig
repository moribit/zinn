const zinn = @import("zinn");
pub const Structure = zinn.Definition(2, &.{
    .{ .units = 8, .activation = .relu },
    .{ .units = 2 },
});
