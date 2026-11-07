const std = @import("std");
const protocol = @import("protocol");
const Expected = struct { model_id: u32, sequence: u16, opcode: u8, class: usize, logits: []i8 };
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 3) return error.ExpectedExpectedJsonAndResponseBinary;
    const a = init.arena.allocator();
    const expected_bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], a, .limited(1024 * 1024));
    const expected = (try std.json.parseFromSlice(Expected, a, expected_bytes, .{ .ignore_unknown_fields = true })).value;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, args[2], a, .limited(65536));
    const result = try protocol.decodeResponse(bytes);
    if (result.model_id != expected.model_id or result.sequence != expected.sequence or result.opcode != expected.opcode) return error.ResponseIdentityMismatch;
    if (result.status != 0) {
        std.debug.print("device status={d}\n", .{result.status});
        return error.DeviceRejectedRequest;
    }
    if (expected.opcode != 2) {
        if (result.class != expected.class or result.logits.len != expected.logits.len) return error.DeviceClassificationMismatch;
        for (result.logits, expected.logits) |byte, value| if (@as(i8, @bitCast(byte)) != value) return error.DeviceLogitMismatch;
    }
    const json = try std.json.Stringify.valueAlloc(a, .{ .schema_version = @as(u32, 1), .source = "response_file", .physical_execution_attested = false, .model_id = result.model_id, .sequence = result.sequence, .all_logits_match = expected.opcode != 2, .class = result.class, .clock_hz = result.clock_hz, .timer_overhead = result.overhead, .iterations = result.iterations, .min_cycles = result.min, .median_cycles = result.median, .max_cycles = result.max, .median_ns = if (result.clock_hz == 0) @as(?u64, null) else @as(u64, result.median) * 1_000_000_000 / result.clock_hz, .workspace_bytes = result.workspace, .input_bytes = result.input_len, .adapter_init_cycles = result.adapter_init, .transfer_cycles = result.transfer, .preprocess_cycles = result.preprocess, .stack_watermark_bytes = if (result.stack_high_water == 0xffff) @as(?u16, null) else result.stack_high_water }, .{});
    try std.Io.File.stdout().writeStreamingAll(init.io, json);
}
