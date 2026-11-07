//! Allocation-free cycle sampling. The caller supplies the 9-sample buffer.
pub const Summary = struct { overhead: u32, min: u32, median: u32, max: u32, iterations: u16 };
pub fn summarize(samples: *[9]u32, overhead: u32) Summary {
    for (samples, 0..) |_, i| {
        var j = i;
        while (j > 0 and samples[j] < samples[j - 1]) : (j -= 1) {
            const value = samples[j];
            samples[j] = samples[j - 1];
            samples[j - 1] = value;
        }
    }
    return .{ .overhead = overhead, .min = samples[0] -| overhead, .median = samples[4] -| overhead, .max = samples[8] -| overhead, .iterations = 9 };
}
pub fn measure(comptime M: type, comptime Clock: type, input: *const [M.input_len]i8, output: *[M.output_len]i8, workspace: *M.Workspace, samples: *[9]u32) Summary {
    var overhead: u32 = 0xffffffff;
    for (0..9) |_| {
        const start = Clock.now();
        asm volatile ("" ::: .{ .memory = true });
        const end = Clock.now();
        overhead = @min(overhead, end -% start);
    }
    M.infer(input, output, workspace); // warm-up excluded
    for (samples) |*value| {
        const start = Clock.now();
        asm volatile ("" ::: .{ .memory = true });
        M.infer(input, output, workspace);
        asm volatile ("" ::: .{ .memory = true });
        value.* = Clock.now() -% start;
    }
    return summarize(samples, overhead);
}
test "cycle summaries subtract overhead and order all samples" {
    var samples = [9]u32{ 90, 10, 80, 20, 70, 30, 60, 40, 50 };
    const result = summarize(&samples, 3);
    try @import("std").testing.expectEqual(@as(u32, 7), result.min);
    try @import("std").testing.expectEqual(@as(u32, 47), result.median);
    try @import("std").testing.expectEqual(@as(u32, 87), result.max);
}
