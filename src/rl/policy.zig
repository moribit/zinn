//! Host export transform: subtract the shared action-head component.
//! Argmax is invariant in exact arithmetic. Exported values are centered action
//! scores, not absolute discounted returns; measure floating/quantized agreement.
const train = @import("../train.zig");
pub fn centeredActionHead(comptime S: type, model: *const train.Trainer(S)) train.Trainer(S) {
    const last = S.layer_count - 1;
    if (S.layers[last].kind != .dense or S.layers[last].activation != .none) @compileError("policy centering requires a linear Dense head");
    var result = model.*;
    const base = S.offsets[last];
    const inputs = S.fanins[last];
    for (0..inputs) |i| {
        var mean: f32 = 0;
        for (0..S.output_len) |o| mean += model.parameters[base + o * inputs + i] / @as(f32, @floatFromInt(S.output_len));
        for (0..S.output_len) |o| result.parameters[base + o * inputs + i] -= mean;
    }
    var bias_mean: f32 = 0;
    for (0..S.output_len) |o| bias_mean += model.parameters[base + S.weight_counts[last] + o] / @as(f32, @floatFromInt(S.output_len));
    for (0..S.output_len) |o| result.parameters[base + S.weight_counts[last] + o] -= bias_mean;
    return result;
}
