const q = @import("../quant.zig");
/// Row-major weights [output][input]. Internal kernel; model proves bounds.
/// Input and output must not overlap.
pub fn dense(input: []const i8, output: []i8, weights: []const i8, bias: []const i32, p: q.Params, activation: bool) void {
    for (output, 0..) |*out, row| {
        var acc: i32 = bias[row];
        for (input, weights[row * input.len ..][0..input.len]) |x, w| {
            acc += (@as(i32, x) - p.input_zero) * @as(i32, w);
        }
        const result = q.requantize(acc, p);
        out.* = if (activation) q.relu(result, p.output_zero) else result;
    }
}
