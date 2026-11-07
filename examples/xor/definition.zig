const z = @import("zinn");
pub const Structure = z.Definition(2, &.{ .{ .units = 8, .activation = .relu }, .{ .units = 2 } });
pub const Training = z.Trainer(Structure);
pub const samples = [_]Training.Sample{
    .{ .input = .{ 0, 0 }, .target = .{ 1, 0 } }, .{ .input = .{ 0, 1 }, .target = .{ 0, 1 } },
    .{ .input = .{ 1, 0 }, .target = .{ 0, 1 } }, .{ .input = .{ 1, 1 }, .target = .{ 1, 0 } },
};
