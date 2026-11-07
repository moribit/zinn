const std = @import("std");
const m = @import("trained_model");
pub fn main() !void {
    var workspace: m.Model.Workspace = undefined;
    for (m.inputs, m.expected) |input, expected| {
        var actual: [m.Model.output_len]i8 = undefined;
        m.Model.infer(&input, &actual, &workspace);
        if (!std.mem.eql(i8, &expected, &actual)) return error.CsvGeneratedReferenceMismatch;
    }
    std.debug.print("CSV generated core: {d}/{d} exact reference matches\n", .{ m.inputs.len, m.inputs.len });
}
