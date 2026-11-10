const std = @import("std");
const generated = @import("policy");
pub fn main() !void {
    const M = generated.Model;
    var workspace: M.Workspace = .{};
    var output: [M.output_len]i8 = undefined;
    for (generated.inputs, generated.expected) |input, expected| {
        M.infer(&input, &output, &workspace);
        if (!std.mem.eql(i8, &output, &expected)) return error.IntegerReferenceMismatch;
    }
    std.debug.print("CartPole integer core: {d}/{d} all Q-score vectors match independent reference; params={d} workspace={d}\n", .{ generated.inputs.len, generated.inputs.len, M.parameter_bytes, M.workspace_bytes });
}
