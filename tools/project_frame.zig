const std = @import("std");
const z = @import("zinn");
const m = @import("trained_model");
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 7) return error.ExpectedInputRequestExpectedSequenceSampleOpcode;
    const sequence = try std.fmt.parseInt(u16, args[4], 10);
    const sample = try std.fmt.parseInt(usize, args[5], 10);
    const op: z.protocol.Opcode = if (std.mem.eql(u8, args[6], "benchmark")) .benchmark else if (std.mem.eql(u8, args[6], "info")) .info else .infer;
    var input: [m.Model.input_len]i8 = undefined;
    if (std.mem.eql(u8, args[1], "-")) {
        if (sample >= m.inputs.len) return error.SampleOutOfBounds;
        input = m.inputs[sample];
    } else {
        const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], init.arena.allocator(), .limited(m.Model.input_len + 1));
        if (bytes.len != m.Model.input_len) return error.InvalidInputLength;
        for (&input, bytes) |*v, byte| v.* = @bitCast(byte);
    }
    var workspace: m.Model.Workspace = undefined;
    var logits: [m.Model.output_len]i8 = undefined;
    m.Model.infer(&input, &logits, &workspace);
    var frame: [m.Model.input_len + 14]u8 = undefined;
    const encoded = try z.protocol.request(&frame, op, sequence, m.model_id, if (op == .info) &.{} else &input);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[2], .data = encoded });
    const json = try std.json.Stringify.valueAlloc(init.arena.allocator(), .{ .schema_version = @as(u32, 1), .model_id = m.model_id, .sequence = sequence, .opcode = @backingInt(op), .class = z.argmax(&logits).?, .logits = logits, .input_count = m.Model.input_len, .input_scale_bits = @as(u32, @bitCast(m.input_scale)), .hardware_measured = false }, .{});
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[3], .data = json });
}
