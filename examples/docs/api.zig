const std = @import("std");
const z = @import("zinn");
test "documented model, training, CSV, save, export and inference APIs" {
    const S = @import("model.zig").Structure;
    const T = z.Trainer(S);
    const a = std.testing.allocator;
    const samples = try z.data.csv(T, a, "0,0,0\n1,0,1\n1,1,0\n0,1,1\n", false);
    defer a.free(samples);
    var model = T.init(42);
    _ = try model.trainBatch(samples, 0.05, .cross_entropy);
    _ = try model.evaluateWithLoss(samples, .cross_entropy);
    const bytes = model.encode();
    var restored = T.init(0);
    try restored.decode(&bytes);
    inline for (.{ .int8, .int4 }) |format| {
        const Q = z.export_model.QuantizedFormat(S, format);
        const q = try Q.calibrate(&restored, samples);
        var input: [S.input_len]i8 = undefined;
        for (&input, samples[0].input) |*dst, v| dst.* = try z.export_model.quantizeInput(v, q.scales[0]);
        const output = q.infer(&input);
        try std.testing.expect(z.argmax(&output) != null);
        var source: std.Io.Writer.Allocating = .init(a);
        defer source.deinit();
        try q.writeSource(&source.writer);
        try q.writeVerification(&source.writer, samples);
        try std.testing.expect(std.mem.indexOf(u8, source.written(), "pub const Model") != null);
    }
    try std.testing.expectError(error.CsvColumnCountMismatch, z.data.csv(T, a, "0,1\n", false));
    const Image = @import("image.zig").Image;
    const ImageTrainer = z.Trainer(Image);
    const image_model = ImageTrainer.init(42);
    const image_output = image_model.predict(&@as([16]f32, @splat(0.5)));
    try std.testing.expectEqual(@as(usize, 2), image_output.len);
}
test "documented static Dense, Conv, Pool, packed and transport APIs" {
    const M = z.Sequential(.{z.Dense(.{ .input = 2, .output = 2, .weights = &.{ 1, 0, 0, 1 }, .bias = &.{ 0, 0 } })});
    M.checkBudget(.{});
    var ws: M.Workspace = undefined;
    var output: [M.output_len]i8 = undefined;
    M.infer(&.{ 3, 9 }, &output, &ws);
    try std.testing.expectEqualSlices(i8, &.{ 3, 9 }, &output);
    const C = z.Conv2D(.{ .input = .{ .height = 2, .width = 2, .channels = 1 }, .output_channels = 1, .kernel = 1, .weights = &.{1}, .bias = &.{0} });
    const P = z.AveragePool2D(.{ .input = C.output_shape });
    var convolution: [C.output_len]i8 = undefined;
    var pooled: [P.output_len]i8 = undefined;
    C.run(&.{ 1, 2, 3, 4 }, &convolution);
    P.run(&convolution, &pooled);
    try std.testing.expectEqual(@as(i8, 3), pooled[0]);
    var tensor: z.Tensor(i8, &.{ 2, 2 }) = .{ .data = .{ 1, 2, 3, 4 } };
    tensor.data[0] = 3;
    var packed_bytes: [2]u8 = undefined;
    try z.lowbit.encode(&.{ -8, 7, -1 }, &packed_bytes);
    try std.testing.expectEqual(@as(i8, -1), z.lowbit.get(.int4, &.{}, &packed_bytes, 2));
    try std.testing.expectEqual(@as(i8, -2), z.quant.requantize(-3, .{ .shift = 1 }));
    var frame: [16]u8 = undefined;
    _ = try z.protocol.request(&frame, .infer, 1, 42, &.{ 3, 9 });
    var receiver = z.protocol.Receiver(2).init(42, 10, 100);
    var event: z.protocol.Event = .none;
    for (frame, 0..) |byte, i| event = receiver.feed(byte, @intCast(i));
    try std.testing.expect(event == .request);
}
