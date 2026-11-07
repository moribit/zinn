const z = @import("zinn");
const options = @import("dataset_options");
pub const Structure = z.Definition(options.features, &.{ .{ .units = options.hidden, .activation = .relu }, .{ .units = options.classes } });
