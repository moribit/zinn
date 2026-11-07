const std = @import("std");
const m = @import("model.zig");
pub fn main() !void {
    var ws: m.Model.Workspace = undefined;
    for (m.inputs, m.expected) |input, expected| {
        var output: [2]i8 = undefined;
        m.Model.infer(&input, &output, &ws);
        if (!std.mem.eql(i8, &output, &expected)) return error.GoldenMismatch;
    }
    std.debug.print("XOR: 4/4 golden vectors passed; workspace={d} bytes\n", .{m.Model.workspace_bytes});
}
