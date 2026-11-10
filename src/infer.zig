//! Integer inference only: no training, transport, board or host tooling imports.
pub const Dense = @import("model.zig").Dense;
pub const Sequential = @import("model.zig").Sequential;
pub const Conv2D = @import("cnn.zig").Conv2D;
pub const AveragePool2D = @import("cnn.zig").AveragePool2D;
pub const Workspace = @import("workspace.zig").Workspace;
pub const Tensor = @import("tensor.zig").Tensor;
pub const Shape = @import("spatial.zig").Shape;
pub const quant = @import("quant.zig");
pub const lowbit = @import("packed.zig");
pub fn argmax(values: []const i8) ?usize {
    if (values.len == 0) return null;
    var best: usize = 0;
    for (values, 0..) |v, i| {
        if (v > values[best]) best = i;
    }
    return best;
}
