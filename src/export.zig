//! Host-only min/max calibration and source export for a shared Definition.
const std = @import("std");
const q = @import("quant.zig");
const train = @import("train.zig");
pub fn coefficient(ratio: f64) !q.Params {
    if (!std.math.isFinite(ratio) or ratio <= 0) return error.InvalidScale;
    var best: q.Params = .{};
    var best_error: f64 = std.math.inf(f64);
    for (0..32) |shift| {
        const denominator: f64 = @floatFromInt(@as(u64, 1) << @intCast(shift));
        const rounded = @round(ratio * denominator);
        if (rounded < 1 or rounded > 65535) continue;
        const relative = @abs(rounded / denominator - ratio) / ratio;
        if (relative < best_error) {
            best_error = relative;
            best = .{ .multiplier = @intFromFloat(rounded), .shift = @intCast(shift) };
        }
    }
    if (best_error > 0.0001) return error.UnrepresentableScale;
    return best;
}
pub fn quantizeInput(value: f32, scale: f32) !i8 {
    if (!std.math.isFinite(value) or !std.math.isFinite(scale) or scale <= 0) return error.InvalidScale;
    return @intFromFloat(@max(-128, @min(127, @round(value / scale))));
}
pub fn Quantized(comptime S: type) type {
    return QuantizedFormat(S, .int8);
}
pub fn QuantizedFormat(comptime S: type, comptime format: @import("packed.zig").Format) type {
    const spatial = @import("spatial.zig");
    return struct {
        const Self = @This();
        weights: [S.parameter_count]i8 = @splat(0),
        biases: [S.parameter_count]i32 = @splat(0),
        params: [S.layer_count]q.Params = undefined,
        scales: [S.layer_count + 1]f32 = undefined,
        pub fn calibrate(model: *const train.Trainer(S), samples: []const train.Trainer(S).Sample) !Self {
            return calibrateObserved(model, samples, .{});
        }
        pub fn calibrateObserved(model: *const train.Trainer(S), samples: []const train.Trainer(S).Sample, observer: @import("host/progress.zig").Observer) !Self {
            var task = observer.task("Calibration", samples.len);
            errdefer task.fail("operation failed");
            if (samples.len == 0) return error.EmptyCalibration;
            var result: Self = .{};
            var maxima: [S.layer_count + 1]f32 = @splat(0);
            for (model.parameters) |v| if (!std.math.isFinite(v)) return error.NonFiniteParameters;
            for (samples, 0..) |sample, index| {
                for (sample.input) |v| if (!std.math.isFinite(v)) return error.NonFiniteInput;
                var a: train.Trainer(S).Activations = undefined;
                model.forward(&sample.input, &a);
                inline for (S.widths, 0..) |width, l| for (a[l][0..width]) |v| {
                    if (!std.math.isFinite(v)) return error.NonFiniteActivation;
                    maxima[l] = @max(maxima[l], @abs(v));
                };
                if (index % 128 == 0 or index + 1 == samples.len) task.update(index + 1, &.{});
            }
            for (&result.scales, maxima) |*scale, maximum| {
                scale.* = if (maximum == 0) 1.0 / 127.0 else maximum / 127.0;
                if (!std.math.isFinite(scale.*) or scale.* <= 0) return error.InvalidScale;
            }
            inline for (S.layers, 0..) |layer, l| {
                if (layer.kind == .average_pool2d) {
                    result.scales[l + 1] = result.scales[l];
                    result.params[l] = .{ .input_scale = result.scales[l], .weight_scale = 1, .output_scale = result.scales[l] };
                } else {
                    const base = S.offsets[l];
                    const weight_count = S.weight_counts[l];
                    var maximum: f32 = 0;
                    for (model.parameters[base..][0..weight_count]) |v| maximum = @max(maximum, @abs(v));
                    const max_weight: f32 = if (format == .int4) 7 else 127;
                    const weight_scale: f32 = if (maximum == 0) 1.0 / max_weight else maximum / max_weight;
                    const accumulator_scale = @as(f64, result.scales[l]) * weight_scale;
                    var p = try coefficient(accumulator_scale / result.scales[l + 1]);
                    p.input_scale = result.scales[l];
                    p.weight_scale = weight_scale;
                    p.output_scale = result.scales[l + 1];
                    result.params[l] = p;
                    for (0..weight_count) |i| result.weights[base + i] = @intFromFloat(@max(-max_weight, @min(max_weight, @round(model.parameters[base + i] / weight_scale))));
                    for (0..S.bias_counts[l]) |o| {
                        const rounded = @round(@as(f64, model.parameters[base + weight_count + o]) / accumulator_scale);
                        if (!std.math.isFinite(rounded) or rounded < -2147483647 or rounded > 2147483647) return error.BiasOverflow;
                        result.biases[base + o] = @intFromFloat(rounded);
                        var bound: u64 = @abs(@as(i64, result.biases[base + o]));
                        for (result.weights[base + o * S.fanins[l] ..][0..S.fanins[l]]) |w| bound += 128 * @as(u64, @abs(@as(i16, w)));
                        if (bound > 2147483647) return error.AccumulatorOverflow;
                    }
                }
            }
            task.finish();
            return result;
        }
        /// Independently accumulated int64/division reference, not the integer core.
        pub fn infer(self: *const Self, input: *const [S.input_len]i8) [S.output_len]i8 {
            var buffers: [2][S.max_width]i8 = undefined;
            @memcpy(buffers[0][0..S.input_len], input);
            inline for (S.layers, 0..) |layer, l| {
                const base = S.offsets[l];
                for (0..S.widths[l + 1]) |o| {
                    var acc: i64 = if (layer.kind == .average_pool2d) 0 else self.biases[base + spatial.biasIndex(S, l, o)];
                    for (0..S.fanins[l]) |k| if (spatial.inputIndex(S, l, o, k)) |i| {
                        acc += @as(i64, buffers[l % 2][i]) * (if (layer.kind == .average_pool2d) @as(i64, 1) else self.weights[base + spatial.weightIndex(S, l, o, k)]);
                    };
                    const p = self.params[l];
                    const product = if (layer.kind == .average_pool2d) acc else acc * p.multiplier;
                    const denominator = if (layer.kind == .average_pool2d) S.fanins[l] else @as(u64, 1) << p.shift;
                    const magnitude = (@abs(product) + denominator / 2) / denominator;
                    const signed = if (product < 0) -@as(i64, @intCast(magnitude)) else @as(i64, @intCast(magnitude));
                    var value: i8 = @intCast(@max(-128, @min(127, signed)));
                    if (layer.activation == .relu) value = @max(0, value);
                    buffers[(l + 1) % 2][o] = value;
                }
            }
            return buffers[S.layer_count % 2][0..S.output_len].*;
        }
        pub fn modelId(self: *const Self) u32 {
            var hash: u64 = (14695981039346656037 ^ S.schema_tag) *% 1099511628211;
            for (self.weights) |w| hash = (hash ^ @as(u8, @bitCast(w))) *% 1099511628211;
            for (self.biases) |bias| {
                const bits: u32 = @bitCast(bias);
                for (0..4) |i| hash = (hash ^ @as(u8, @truncate(bits >> @intCast(i * 8)))) *% 1099511628211;
            }
            for (self.params) |p| {
                for ([_]u32{ p.multiplier, p.shift, @bitCast(p.input_scale.?), @bitCast(p.weight_scale.?), @bitCast(p.output_scale.?) }) |bits| for (0..4) |i| {
                    hash = (hash ^ @as(u8, @truncate(bits >> @intCast(i * 8)))) *% 1099511628211;
                };
            }
            hash = (hash ^ @as(u64, @backingInt(format))) *% 1099511628211;
            return @truncate(hash ^ (hash >> 32));
        }
        pub fn writeVerification(self: *const Self, writer: *std.Io.Writer, samples: []const train.Trainer(S).Sample) !void {
            if (samples.len == 0) return error.EmptyVerification;
            try writer.print("pub const inputs = [{d}][{d}]i8{{\n", .{ samples.len, S.input_len });
            for (samples) |sample| {
                try writer.writeAll(".{");
                for (sample.input) |v| try writer.print("{d},", .{try quantizeInput(v, self.scales[0])});
                try writer.writeAll("},\n");
            }
            try writer.writeAll("};\n");
            try writer.print("pub const expected = [{d}][{d}]i8{{\n", .{ samples.len, S.output_len });
            for (samples) |sample| {
                var input: [S.input_len]i8 = undefined;
                for (&input, sample.input) |*v, f| v.* = try quantizeInput(f, self.scales[0]);
                const output = self.infer(&input);
                try writer.writeAll(".{");
                for (output) |v| try writer.print("{d},", .{v});
                try writer.writeAll("},\n");
            }
            try writer.writeAll("};\n");
        }
        pub fn writeSource(self: *const Self, writer: *std.Io.Writer) !void {
            try writer.writeAll("// Generated by Zinn. Do not edit. Float metadata is comptime only.\nconst z = @import(\"zinn\");\n");
            try writer.print("pub const schema_tag: u64 = {d};\npub const input_scale: f32 = @bitCast(@as(u32,{d}));\n", .{ S.schema_tag, @as(u32, @bitCast(self.scales[0])) });
            try writer.print("pub const model_id: u32={d};\npub const output_scale: f32=@bitCast(@as(u32,{d}));\n", .{ self.modelId(), @as(u32, @bitCast(self.scales[S.layer_count])) });
            try writer.writeAll("pub const Model = z.Sequential(.{\n");
            inline for (S.layers, 0..) |layer, l| {
                const shape = S.shapes[l];
                if (layer.kind == .dense) {
                    try writer.print("z.Dense(.{{ .input={d}, .output={d},", .{ S.widths[l], S.widths[l + 1] });
                } else if (layer.kind == .conv2d) {
                    try writer.print("z.Conv2D(.{{ .input=.{{.height={d},.width={d},.channels={d}}}, .output_channels={d}, .kernel={d}, .stride={d}, .padding={d},", .{ shape.height, shape.width, shape.channels, layer.units, layer.kernel, layer.stride, layer.padding });
                } else {
                    try writer.print("z.AveragePool2D(.{{ .input=.{{.height={d},.width={d},.channels={d}}}, .kernel={d}, .stride={d}, .scale=@bitCast(@as(u32,{d})), .activation=.{s} }}),\n", .{ shape.height, shape.width, shape.channels, layer.kernel, layer.stride, @as(u32, @bitCast(self.scales[l])), @tagName(layer.activation) });
                }
                if (layer.kind != .average_pool2d) {
                    const base = S.offsets[l];
                    if (format == .int4) {
                        var bytes: [(S.weight_counts[l] + 1) / 2]u8 = undefined;
                        try @import("packed.zig").encode(self.weights[base..][0..S.weight_counts[l]], &bytes);
                        try writer.writeAll(" .format=.int4, .packed_weights=&.{");
                        for (bytes) |byte| try writer.print("{d},", .{byte});
                    } else {
                        try writer.writeAll(" .weights=&.{");
                        for (self.weights[base..][0..S.weight_counts[l]]) |w| try writer.print("{d},", .{w});
                    }
                    try writer.writeAll("}, .bias=&.{");
                    for (self.biases[base..][0..S.bias_counts[l]]) |bias| try writer.print("{d},", .{bias});
                    const p = self.params[l];
                    try writer.print("}}, .activation=.{s}, .quant=.{{ .multiplier={d}, .shift={d},", .{ @tagName(layer.activation), p.multiplier, p.shift });
                    try writer.print(" .input_scale=@bitCast(@as(u32,{d})), .weight_scale=@bitCast(@as(u32,{d})), .output_scale=@bitCast(@as(u32,{d})) }} }}),\n", .{ @as(u32, @bitCast(p.input_scale.?)), @as(u32, @bitCast(p.weight_scale.?)), @as(u32, @bitCast(p.output_scale.?)) });
                }
            }
            try writer.writeAll("});\n");
        }
    };
}
