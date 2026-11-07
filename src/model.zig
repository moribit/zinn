const std = @import("std");
const q = @import("quant.zig");
const kernel = @import("kernels/dense.zig");
pub const Activation = enum { none, relu };
pub const DenseOptions = struct {
    input: usize,
    output: usize,
    weights: []const i8,
    bias: []const i32,
    quant: q.Params = .{},
    activation: Activation = .none,
};
pub fn Dense(comptime config: DenseOptions) type {
    comptime {
        config.quant.validate();
        if (config.input == 0 or config.output == 0) @compileError("dense dimensions must be positive");
        const product = @mulWithOverflow(config.input, config.output);
        if (product[1] != 0 or config.weights.len != product[0] or config.bias.len != config.output)
            @compileError("dense parameter shape mismatch");
        // Absolute-sum bound proves every partial accumulation fits int32.
        @setEvalBranchQuota(10_000_000);
        for (0..config.output) |row| {
            var bound: u64 = @intCast(@abs(@as(i64, config.bias[row])));
            const max_input: u64 = @intCast(@max(@as(i32, 127) - config.quant.input_zero, @as(i32, 128) + config.quant.input_zero));
            for (config.weights[row * config.input ..][0..config.input]) |w| bound += max_input * @as(u64, @abs(@as(i16, w)));
            if (bound > std.math.maxInt(i32)) @compileError("dense accumulator may overflow int32");
        }
    }
    return struct {
        pub const input_len = config.input;
        pub const output_len = config.output;
        pub const input_zero = config.quant.input_zero;
        pub const output_zero = config.quant.output_zero;
        pub fn run(input: *const [input_len]i8, output: *[output_len]i8) void {
            kernel.dense(input, output, config.weights, config.bias, config.quant, config.activation == .relu);
        }
    };
}
pub fn Sequential(comptime layers: anytype) type {
    const count = layers.len;
    if (count == 0) @compileError("sequential requires layers");
    const width = comptime blk: {
        var w: usize = layers[0].input_len;
        for (layers, 0..) |L, i| {
            if (i > 0) {
                if (layers[i - 1].output_len != L.input_len) @compileError("layer shape mismatch");
                if (layers[i - 1].output_zero != L.input_zero) @compileError("layer zero point mismatch");
            }
            w = @max(w, L.output_len);
        }
        break :blk w;
    };
    return struct {
        pub const input_len = layers[0].input_len;
        pub const output_len = layers[count - 1].output_len;
        pub const Workspace = @import("workspace.zig").Workspace(width);
        pub const workspace_bytes = @sizeOf(Workspace);
        /// Input/output may alias each other but must not alias workspace.
        pub fn infer(input: *const [input_len]i8, output: *[output_len]i8, ws: *Workspace) void {
            @memcpy(ws.buffers[0][0..input_len], input);
            inline for (layers, 0..) |L, i| {
                L.run(ws.buffers[i % 2][0..L.input_len], ws.buffers[(i + 1) % 2][0..L.output_len]);
            }
            @memcpy(output, ws.buffers[count % 2][0..output_len]);
        }
    };
}
