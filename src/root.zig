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
    _ = @import("tests.zig");
}
