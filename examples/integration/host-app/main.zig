const std = @import("std");
const z = @import("zinn_infer");
fn verify(comptime generated: type) !void {
    const M = generated.Model;
    var workspace: M.Workspace = .{};
    var output: [M.output_len]i8 = undefined;
    for (generated.inputs, generated.expected) |input, expected| {
        M.infer(&input, &output, &workspace);
        if (!std.mem.eql(i8, &output, &expected)) return error.InferenceMismatch;
        if (z.argmax(&output) == null) return error.EmptyOutput;
    }
}
pub fn main() !void {
    try verify(@import("sensor_model"));
    std.debug.print("Integration inference: PASS\n", .{});
}
