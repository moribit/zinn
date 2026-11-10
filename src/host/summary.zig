//! Host-only presentation sidecars, independent of checkpoint/model schemas.
const std = @import("std");
pub const Kind = enum { train, evaluate, e2e, deploy };
pub const Report = struct {
    schema_version: u32 = 1,
    kind: Kind,
    structure: []const u8 = "",
    dataset: []const u8 = "",
    dataset_source: []const u8 = "",
    split: []const u8 = "",
    format: []const u8 = "",
    result: []const u8 = "PASS",
    samples: ?usize = null,
    matched: ?usize = null,
    mismatched: ?usize = null,
    accuracy: ?f64 = null,
    quantized_accuracy: ?f64 = null,
    loss: ?f64 = null,
    loss_kind: []const u8 = "",
    best_epoch: ?usize = null,
    best_validation_accuracy: ?f64 = null,
    final_epoch_loss: ?f64 = null,
    elapsed_ns: ?u64 = null,
    parameters: ?usize = null,
    workspace: ?usize = null,
    target: []const u8 = "",
    flash: ?u64 = null,
    flash_limit: ?u64 = null,
    static_ram: ?u64 = null,
    stack_allowance: ?u64 = null,
    ram_margin: ?u64 = null,
    note: []const u8 = "",
};
pub fn structure(comptime S: type) []const u8 {
    return comptime blk: {
        const input = S.shapes[0];
        var text: []const u8 = if (input.height == 1 and input.width == 1) std.fmt.comptimePrint("{d}", .{S.input_len}) else std.fmt.comptimePrint("{d}x{d}x{d}", .{ input.height, input.width, input.channels });
        for (S.layers, 0..) |layer, i| {
            if (layer.kind == .dense) text = text ++ std.fmt.comptimePrint(" -> dense({d})", .{layer.units}) else {
                const out = S.shapes[i + 1];
                text = text ++ std.fmt.comptimePrint(" -> {s}({d}x{d}x{d}; k{d}/s{d}/p{d})", .{ @tagName(layer.kind), out.height, out.width, out.channels, layer.kernel, layer.stride, layer.padding });
            }
        }
        break :blk text;
    };
}
fn loss(w: *std.Io.Writer, label: []const u8, kind: []const u8, value: f64) !void {
    try w.print("{s} ({s}): ", .{ label, kind });
    if (value != 0 and @abs(value) < 0.000001) try w.print("{e}\n", .{value}) else try w.print("{d:.6}\n", .{value});
}
pub fn format(w: *std.Io.Writer, r: Report, model: []const u8, executed: bool, prefix: []const u8, artifact: []const u8) !void {
    if (r.schema_version != 1 or !std.mem.eql(u8, r.result, "PASS")) return error.InvalidSuccessfulSummary;
    try w.print("{s} {s}\nOperation: {s}\n", .{ if (executed) "completed" else "cached", model, @tagName(r.kind) });
    if (r.structure.len > 0) try w.print("Model: {s}\n", .{r.structure});
    switch (r.kind) {
        .train => {
            if (r.best_epoch) |v| try w.print("Best epoch: {d}\n", .{v});
            if (r.best_validation_accuracy) |v| try w.print("Best validation accuracy: {d:.4}%\n", .{v}) else try w.writeAll("Validation: n/a (no validation split)\n");
            if (r.final_epoch_loss) |v| try loss(w, "Final epoch loss", r.loss_kind, v);
            if (executed) if (r.elapsed_ns) |v| try w.print("Training elapsed: {d:.3}s\n", .{@as(f64, @floatFromInt(v)) / 1e9});
            try w.print("  checkpoint: {s}/{s}\n  log: {s}/reports/{s}-training-progress.log\n", .{ prefix, artifact, prefix, model });
        },
        .evaluate => {
            try w.print("Dataset: {s} / {s}\n", .{ r.dataset, r.split });
            if (r.dataset_source.len > 0) try w.print("Data: {s}\n", .{r.dataset_source});
            if (r.samples) |v| try w.print("Samples: {d}\n", .{v});
            if (r.accuracy) |v| try w.print("Float accuracy: {d:.4}%\n", .{v});
            if (r.quantized_accuracy) |v| try w.print("Integer classification accuracy: {d:.4}%\n", .{v});
            if (r.loss) |v| try loss(w, "Float loss", r.loss_kind, v);
            try w.print("Quantization: {s}\nReport: {s}/{s}\n", .{ r.format, prefix, artifact });
        },
        .e2e => {
            if (r.dataset.len > 0) try w.print("Dataset: {s}\n", .{r.dataset});
            try w.writeAll("Integer reference verification\nResult: PASS\n");
            if (r.samples) |v| try w.print("Samples: {d}\n", .{v});
            if (r.matched) |v| try w.print("Samples with all logits matched: {d}\n", .{v});
            if (r.mismatched) |v| try w.print("Mismatches: {d}\n", .{v});
            if (r.parameters) |v| try w.print("Parameters: {d} B\n", .{v});
            if (r.workspace) |v| try w.print("Workspace: {d} B\n", .{v});
            try w.writeAll("Note: Exact reference matching is not classification accuracy.\n");
        },
        .deploy => {
            try w.print("Target: {s}\n", .{r.target});
            if (r.flash) |v| try w.print("Flash: {d} / {d} B (usable budget)\n", .{ v, r.flash_limit orelse return error.InvalidMemorySummary });
            if (r.static_ram) |v| try w.print("Static SRAM: {d} B\n", .{v});
            if (r.stack_allowance) |v| try w.print("Stack allowance: {d} B (budget, not measured)\n", .{v});
            if (r.ram_margin) |v| try w.print("RAM margin: {d} B\n", .{v});
            const stem = std.fs.path.stem(artifact);
            const dir = std.fs.path.dirname(artifact) orelse ".";
            try w.print("ELF: {s}/{s}\nBIN: {s}/{s}/{s}.bin\nHardware: not flashed; no physical timing measured.\n", .{ prefix, artifact, prefix, dir, stem });
        },
    }
    if (r.note.len > 0) try w.print("Note: {s}\n", .{r.note});
    if (!executed) try w.writeAll("Saved artifact reused; no new execution time reported.\n");
}
pub fn download(w: *std.Io.Writer, done: u64, total: u64, fetched: f64, cached: f64) !void {
    try w.print("completed MNIST {d}/{d}: {d:.0} new, {d:.0} cached", .{ done, total, fetched, cached });
}
test "cached summaries suppress saved timing and distinguish reference accuracy" {
    var bytes: [2048]u8 = undefined;
    var w: std.Io.Writer = .fixed(&bytes);
    try format(&w, .{ .kind = .train, .elapsed_ns = 1_000_000_000, .final_epoch_loss = 0.1 }, "model", false, "out", "model.zinn");
    try std.testing.expect(std.mem.indexOf(u8, w.buffered(), "Training elapsed:") == null);
    w.end = 0;
    try format(&w, .{ .kind = .e2e, .samples = 3, .matched = 3, .mismatched = 0 }, "model", true, "out", "model.zig");
    try std.testing.expect(std.mem.indexOf(u8, w.buffered(), "not classification accuracy") != null);
    try std.testing.expectError(error.InvalidSuccessfulSummary, format(&w, .{ .kind = .e2e, .result = "FAIL" }, "model", false, "out", "x"));
}
