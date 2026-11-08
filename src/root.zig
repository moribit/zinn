pub const Service = @import("service.zig").Service;
pub const benchmark = @import("benchmark.zig");
pub const protocol = @import("protocol.zig");
pub const fit = @import("fit.zig");
pub const host = @import("host/root.zig");
pub const data = @import("data.zig");
pub const Conv2D = @import("cnn.zig").Conv2D;
pub const AveragePool2D = @import("cnn.zig").AveragePool2D;
pub const lowbit = @import("packed.zig");
pub const ImageDefinition = @import("definition.zig").ImageDefinition;
pub const Shape = @import("spatial.zig").Shape;
pub const export_model = @import("export.zig");
pub const Definition = @import("definition.zig").Definition;
pub const Trainer = @import("train.zig").Trainer;
pub const Tensor = @import("tensor.zig").Tensor;
pub const quant = @import("quant.zig");
pub const Dense = @import("model.zig").Dense;
pub const Sequential = @import("model.zig").Sequential;
pub fn argmax(values: []const i8) ?usize {
    if (values.len == 0) return null;
    var best: usize = 0;
    for (values, 0..) |v, i| {
        if (v > values[best]) best = i;
    }
    return best;
}
test {
    _ = @import("host/progress.zig");
    _ = @import("host/download.zig");
    _ = @import("tests.zig");
    _ = @import("train_tests.zig");
    _ = @import("budget_tests.zig");
    _ = @import("stack_audit.zig");
    _ = @import("fit.zig");
    _ = @import("benchmark.zig");
    _ = @import("service.zig");
    _ = @import("protocol_tests.zig");
    _ = @import("cnn_tests.zig");
    _ = @import("data_tests.zig");
}
