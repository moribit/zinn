const std = @import("std");
const z = @import("zinn");
const m = @import("trained_model");
const definition = @import("definition.zig");
pub fn main() !void {
    if (m.schema_tag != definition.Structure.schema_tag) return error.DefinitionMismatch;
    var ws: m.Model.Workspace = undefined;
    for (m.inputs, m.expected, 0..) |input, expected, i| {
        var output: [2]i8 = undefined;
        m.Model.infer(&input, &output, &ws);
        if (!std.mem.eql(i8, &output, &expected)) return error.IntegerReferenceMismatch;
        const target: usize = if (i == 1 or i == 2) 1 else 0;
        if (z.argmax(&output).? != target) return error.ClassificationMismatch;
        std.debug.print("integer XOR {d}: [{d},{d}] class={d}\n", .{ i, output[0], output[1], target });
    }
    std.debug.print("e2e: 4/4 exact reference matches; workspace={d} B; parameters={d} B\n", .{ m.Model.workspace_bytes, m.Model.parameter_bytes });
}
