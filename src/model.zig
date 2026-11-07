const std = @import("std");
const q = @import("quant.zig");
const lowbit = @import("packed.zig");
const kernel = @import("kernels/dense.zig");
pub const Activation = enum { none, relu };
pub const DenseOptions = struct {
    input: usize,
    output: usize,
    weights: []const i8 = &.{},
    packed_weights: []const u8 = &.{},
    format: lowbit.Format = .int8,
    bias: []const i32,
    quant: q.Params = .{},
    activation: Activation = .none,
};
pub fn Dense(comptime config: DenseOptions) type {
    comptime {
        config.quant.validate();
        if (config.input == 0 or config.output == 0) @compileError("dense dimensions must be positive");
        const product = @mulWithOverflow(config.input, config.output);
        if (product[1] != 0 or config.bias.len != config.output or (config.format == .int8 and (config.weights.len != product[0] or config.packed_weights.len != 0)))
            @compileError("dense parameter shape mismatch");
        lowbit.validate(config.format, product[0], config.weights, config.packed_weights);
        // Absolute-sum bound proves every partial accumulation fits int32.
        @setEvalBranchQuota(10_000_000);
        for (0..config.output) |row| {
            var bound: u64 = @intCast(@abs(@as(i64, config.bias[row])));
            const max_input: u64 = @intCast(@max(@as(i32, 127) - config.quant.input_zero, @as(i32, 128) + config.quant.input_zero));
            for (0..config.input) |i| bound += max_input * @as(u64, @abs(@as(i16, lowbit.get(config.format, config.weights, config.packed_weights, row * config.input + i))));
            if (bound > std.math.maxInt(i32)) @compileError("dense accumulator may overflow int32");
        }
    }
    return struct {
        pub const parameter_bytes = config.weights.len + config.packed_weights.len + @sizeOf(i32) * config.bias.len;
        pub const input_len = config.input;
        pub const output_len = config.output;
        pub const input_scale = config.quant.input_scale;
        pub const output_scale = config.quant.output_scale;
        pub const input_zero = config.quant.input_zero;
        pub const output_zero = config.quant.output_zero;
        pub fn run(input: *const [input_len]i8, output: *[output_len]i8) void {
            kernel.dense(input, output, config.format, config.weights, config.packed_weights, config.bias, config.quant, config.activation == .relu);
        }
    };
}
pub fn Sequential(comptime layers: anytype) type {
    const count = layers.len;
    if (count == 0) @compileError("sequential requires layers");
    const widths = comptime blk: {
        var sizes = [2]usize{ 0, 0 };
        for (layers, 0..) |L, i| {
            if (i > 0) {
                if (layers[i - 1].output_len != L.input_len) @compileError("layer shape mismatch");
                if (layers[i - 1].output_zero != L.input_zero) @compileError("layer zero point mismatch");
                if (@hasDecl(layers[i - 1], "output_shape") and @hasDecl(L, "input_shape")) {
                    const a = layers[i - 1].output_shape;
                    const b = L.input_shape;
                    if (a.height != b.height or a.width != b.width or a.channels != b.channels) @compileError("layer spatial shape mismatch");
                }
                const previous_scale = if (@hasDecl(layers[i - 1], "output_scale")) layers[i - 1].output_scale else null;
                const next_scale = if (@hasDecl(L, "input_scale")) L.input_scale else null;
                if (previous_scale != next_scale) @compileError("layer scale mismatch (including missing metadata)");
            }
            if (i + 1 < count) sizes[i % 2] = @max(sizes[i % 2], L.output_len);
        }
        if (count == 1) sizes[0] = layers[0].input_len; // preserve alias-safe single-layer API
        break :blk sizes;
    };
    return struct {
        pub const input_len = layers[0].input_len;
        pub const output_len = layers[count - 1].output_len;
        pub const Workspace = struct { first: [widths[0]]i8 = undefined, second: [widths[1]]i8 = undefined };
        pub const workspace_bytes = @sizeOf(Workspace);
        pub const parameter_bytes = blk: {
            var total: usize = 0;
            for (layers) |L| total += L.parameter_bytes;
            break :blk total;
        };
        pub const activation_bytes = input_len + output_len + workspace_bytes;
        /// Model-only estimate; final ELF must additionally pass `zig build size`.
        pub fn checkBudget(comptime target: @import("budget.zig").Target) void {
            comptime {
                if (target.reserved_flash_bytes > target.flash_bytes or target.stack_bytes > target.ram_bytes) @compileError("invalid target memory budget");
                if (parameter_bytes > target.flash_bytes - target.reserved_flash_bytes) @compileError("model parameters exceed target Flash budget (runtime not yet included)");
                if (activation_bytes + target.stack_bytes > target.ram_bytes) @compileError("model activations and stack allowance exceed target SRAM budget");
            }
        }

        /// Input/output may alias each other but must not alias workspace.
        pub fn infer(input: *const [input_len]i8, output: *[output_len]i8, ws: *Workspace) void {
            if (count == 1) {
                const in_start = @intFromPtr(input);
                const out_start = @intFromPtr(output);
                if (in_start < out_start + output_len and out_start < in_start + input_len) {
                    @memcpy(ws.first[0..input_len], input);
                    layers[0].run(ws.first[0..input_len], output);
                } else layers[0].run(input, output);
            } else {
                inline for (layers, 0..) |L, i| {
                    const src = if (i == 0) input else if ((i - 1) % 2 == 0) ws.first[0..L.input_len] else ws.second[0..L.input_len];
                    const dst = if (i + 1 == count) output else if (i % 2 == 0) ws.first[0..L.output_len] else ws.second[0..L.output_len];
                    L.run(src, dst);
                }
            }
        }
    };
}
