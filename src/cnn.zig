const std = @import("std");
const spatial = @import("spatial.zig");
const definition = @import("definition.zig");
const lowbit = @import("packed.zig");
const q = @import("quant.zig");
const Activation = @import("model.zig").Activation;
pub const ConvOptions = struct {
    input: spatial.Shape,
    output_channels: usize,
    kernel: usize = 3,
    stride: usize = 1,
    padding: usize = 0,
    weights: []const i8 = &.{},
    packed_weights: []const u8 = &.{},
    format: lowbit.Format = .int8,
    bias: []const i32,
    quant: q.Params = .{},
    activation: Activation = .none,
};
pub fn Conv2D(comptime c: ConvOptions) type {
    const S = definition.ImageDefinition(c.input, &.{.{ .kind = .conv2d, .units = c.output_channels, .kernel = c.kernel, .stride = c.stride, .padding = c.padding, .activation = c.activation }});
    comptime {
        c.quant.validate();
        @setEvalBranchQuota(10_000_000);
        lowbit.validate(c.format, S.weight_counts[0], c.weights, c.packed_weights);
        if (c.bias.len != c.output_channels) @compileError("convolution bias shape mismatch");
        const max_input: u64 = @intCast(@max(@as(i32, 127) - c.quant.input_zero, @as(i32, 128) + c.quant.input_zero));
        for (0..c.output_channels) |o| {
            var bound: u64 = @abs(@as(i64, c.bias[o]));
            for (0..S.fanins[0]) |k| bound += max_input * @as(u64, @abs(@as(i16, lowbit.get(c.format, c.weights, c.packed_weights, o * S.fanins[0] + k))));
            if (bound > std.math.maxInt(i32)) @compileError("convolution accumulator may overflow int32");
        }
    }
    return struct {
        pub const input_len = S.input_len;
        pub const output_len = S.output_len;
        pub const input_shape = c.input;
        pub const output_shape = S.shapes[1];
        pub const input_zero = c.quant.input_zero;
        pub const output_zero = c.quant.output_zero;
        pub const input_scale = c.quant.input_scale;
        pub const output_scale = c.quant.output_scale;
        pub const parameter_bytes = c.weights.len + c.packed_weights.len + 4 * c.bias.len;
        pub fn run(input: *const [input_len]i8, output: *[output_len]i8) void {
            for (output, 0..) |*value, o| {
                var acc: i32 = c.bias[spatial.biasIndex(S, 0, o)];
                for (0..S.fanins[0]) |k| {
                    if (spatial.inputIndex(S, 0, o, k)) |i| {
                        acc += (@as(i32, input[i]) - c.quant.input_zero) * @as(i32, lowbit.get(c.format, c.weights, c.packed_weights, spatial.weightIndex(S, 0, o, k)));
                    }
                }
                const result = q.requantize(acc, c.quant);
                value.* = if (c.activation == .relu) q.relu(result, c.quant.output_zero) else result;
            }
        }
    };
}
pub const PoolOptions = struct { input: spatial.Shape, kernel: usize = 2, stride: usize = 2, zero: i8 = 0, scale: ?f32 = null, activation: Activation = .none };
pub fn AveragePool2D(comptime c: PoolOptions) type {
    const S = definition.ImageDefinition(c.input, &.{.{ .kind = .average_pool2d, .kernel = c.kernel, .stride = c.stride, .activation = c.activation }});
    comptime {
        if (S.fanins[0] > std.math.maxInt(i32) / 255) @compileError("pool accumulator may overflow int32");
        if (c.scale) |scale| {
            if (!std.math.isFinite(scale) or scale <= 0) @compileError("pool scale must be finite and positive");
        }
    }
    return struct {
        pub const input_len = S.input_len;
        pub const output_len = S.output_len;
        pub const input_shape = c.input;
        pub const output_shape = S.shapes[1];
        pub const input_zero = c.zero;
        pub const output_zero = c.zero;
        pub const input_scale = c.scale;
        pub const output_scale = c.scale;
        pub const parameter_bytes = 0;
        pub fn run(input: *const [input_len]i8, output: *[output_len]i8) void {
            for (output, 0..) |*value, o| {
                var sum: i32 = 0;
                for (0..S.fanins[0]) |k| sum += @as(i32, input[spatial.inputIndex(S, 0, o, k).?]) - c.zero;
                const magnitude = (@abs(sum) + S.fanins[0] / 2) / S.fanins[0];
                const signed = if (sum < 0) -@as(i32, @intCast(magnitude)) else @as(i32, @intCast(magnitude));
                const result: i8 = @intCast(signed + c.zero);
                value.* = if (c.activation == .relu) q.relu(result, c.zero) else result;
            }
        }
    };
}
