const options = @import("dataset_options");
pub const Structure = @import("definition.zig").Configured(options.cnn, options.hidden, options.channels);
