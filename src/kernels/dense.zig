const lowbit = @import("../packed.zig");
const q = @import("../quant.zig");
/// Row-major weights [output][input]. Internal kernel; model proves bounds.
/// Input and output must not overlap.
pub fn dense(input: []const i8, output: []i8, comptime format: lowbit.Format, weights: []const i8, bytes: []const u8, bias: []const i32, p: q.Params, activation: bool) void {
    for (output, 0..) |*out, row| {
        var acc: i32 = bias[row];
        if (format == .int8) {
            for (input, weights[row * input.len ..][0..input.len]) |x, w| acc += (@as(i32, x) - p.input_zero) * @as(i32, w);
        } else {
            for (input, 0..) |x, i| {
                const w = lowbit.get(format, weights, bytes, row * input.len + i);
                acc += (@as(i32, x) - p.input_zero) * @as(i32, w);
            }
        }
        const result = q.requantize(acc, p);
        out.* = if (activation) q.relu(result, p.output_zero) else result;
    }
}
