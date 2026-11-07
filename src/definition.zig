const spatial = @import("spatial.zig");
pub const Layer = struct {
    units: usize = 0,
    activation: @import("model.zig").Activation = .none,
    kind: spatial.Kind = .dense,
    kernel: usize = 3,
    stride: usize = 1,
    padding: usize = 0,
};
pub fn Definition(comptime inputs: usize, comptime specs: []const Layer) type {
    return makeDefinition(.{ .height = 1, .width = 1, .channels = inputs }, specs, false);
}
pub fn ImageDefinition(comptime shape: spatial.Shape, comptime specs: []const Layer) type {
    return makeDefinition(shape, specs, true);
}
fn makeDefinition(comptime shape: spatial.Shape, comptime specs: []const Layer, comptime image: bool) type {
    const inputs = shape.len();
    if (specs.len == 0) @compileError("definition requires positive input and at least one layer");
    const layout = comptime blk: {
        var widths: [specs.len + 1]usize = undefined;
        var shapes: [specs.len + 1]spatial.Shape = undefined;
        var offsets: [specs.len]usize = undefined;
        var weights: [specs.len]usize = undefined;
        var biases: [specs.len]usize = undefined;
        var fanins: [specs.len]usize = undefined;
        widths[0] = inputs;
        shapes[0] = shape;
        var total: usize = 0;
        var maximum = inputs;
        var spatial_valid = image;
        var tag: u64 = 14695981039346656037;
        for (specs, 0..) |layer, i| {
            offsets[i] = total;
            if (layer.kind == .dense) {
                if (layer.units == 0) @compileError("definition layer units must be positive");
                shapes[i + 1] = .{ .height = 1, .width = 1, .channels = layer.units };
                fanins[i] = widths[i];
                weights[i] = widths[i] * layer.units;
                biases[i] = layer.units;
                spatial_valid = false;
            } else {
                if (!spatial_valid) @compileError("spatial layer requires an image input and cannot follow Dense");
                if (layer.kernel == 0 or layer.stride == 0) @compileError("kernel and stride must be positive");
                const src = shapes[i];
                if (src.height + 2 * layer.padding < layer.kernel or src.width + 2 * layer.padding < layer.kernel) @compileError("kernel exceeds padded input shape");
                const channels = if (layer.kind == .conv2d) layer.units else src.channels;
                if (channels == 0) @compileError("convolution channels must be positive");
                if (layer.kind == .average_pool2d and (layer.padding != 0 or layer.units != 0)) @compileError("average pooling requires zero padding and preserves channels");
                shapes[i + 1] = .{ .height = (src.height + 2 * layer.padding - layer.kernel) / layer.stride + 1, .width = (src.width + 2 * layer.padding - layer.kernel) / layer.stride + 1, .channels = channels };
                fanins[i] = layer.kernel * layer.kernel * (if (layer.kind == .conv2d) src.channels else 1);
                weights[i] = if (layer.kind == .conv2d) fanins[i] * channels else 0;
                biases[i] = if (layer.kind == .conv2d) channels else 0;
            }
            widths[i + 1] = shapes[i + 1].len();
            total += weights[i] + biases[i];
            maximum = @max(maximum, widths[i + 1]);
        }
        for (widths) |width| tag = (tag ^ @as(u64, width)) *% 1099511628211;
        for (specs) |layer| tag = (tag ^ @as(u64, @backingInt(layer.activation))) *% 1099511628211;
        // Keep legacy Dense checkpoint IDs unchanged.
        if (image) {
            tag = (tag ^ shape.height) *% 1099511628211;
            tag = (tag ^ shape.width) *% 1099511628211;
            tag = (tag ^ shape.channels) *% 1099511628211;
            for (specs) |layer| {
                tag = (tag ^ @as(u64, @backingInt(layer.kind))) *% 1099511628211;
                tag = (tag ^ layer.kernel) *% 1099511628211;
                tag = (tag ^ layer.stride) *% 1099511628211;
                tag = (tag ^ layer.padding) *% 1099511628211;
            }
        }
        break :blk .{ .widths = widths, .shapes = shapes, .offsets = offsets, .weights = weights, .biases = biases, .fanins = fanins, .total = total, .maximum = maximum, .tag = tag };
    };
    return struct {
        pub const layers = specs;
        pub const widths = layout.widths;
        pub const shapes = layout.shapes;
        pub const offsets = layout.offsets;
        pub const weight_counts = layout.weights;
        pub const bias_counts = layout.biases;
        pub const fanins = layout.fanins;
        pub const parameter_count = layout.total;
        pub const max_width = layout.maximum;
        pub const input_len = inputs;
        pub const output_len = layout.widths[specs.len];
        pub const layer_count = specs.len;
        pub const schema_tag = layout.tag;
    };
}
