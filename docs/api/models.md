# Model definitions and tensors

[Source](../../src/definition.zig). Definitions describe topology and parameter layout, not allocated weights. They are shared by host Trainer/export; generated inference uses Sequential.

```zig
pub fn Definition(comptime inputs: usize, comptime specs: []const Layer) type
pub fn ImageDefinition(comptime shape: Shape, comptime specs: []const Layer) type
```

Shape is `{height:usize,width:usize,channels:usize}`; layout is HWC. Layer fields: units=0, activation=.none (.none/.relu), kind=.dense (.dense/.conv2d/.average_pool2d), kernel=3, stride=1, padding=0. For Dense, units is output width; for Conv, output channels; pooling preserves channels and requires units0/padding0. Dense flattens previous HWC output; a spatial layer cannot follow Dense. Conv uses square kernels, symmetric padding and floor output sizing. No dilation/groups/depthwise.

Return type exposes layers, widths, shapes, offsets, weight_counts, bias_counts, fanins, parameter_count, max_width, input_len, output_len, layer_count and schema_tag. Positive dimensions/layers/units, valid kernel/stride and spatial ordering are checked at comptime. Excessive dimensions may cause compile-time overflow/resource errors; these are not dynamically sized tensors.

<!-- zinn-image-sample -->
```zig
const zinn = @import("zinn");
pub const Image = zinn.ImageDefinition(.{ .height = 4, .width = 4, .channels = 1 }, &.{
    .{ .kind = .conv2d, .units = 2, .kernel = 3, .activation = .relu },
    .{ .kind = .average_pool2d, .kernel = 2, .stride = 2 },
    .{ .units = 2 },
});
```

This exact [sample](../../examples/docs/image.zig) is compiled in docs-check. Model types allocate nothing themselves; training memory and MCU activation workspace are separate.

## Tensor

[Source](../../src/tensor.zig): `Tensor(comptime T:type, comptime dimensions:[]const usize) type` returns a struct with data:[len]T, len and shape. Empty shapes, zero dimensions and size multiplication overflow fail at compile time. Construct explicitly, e.g. `var tensor: zinn.Tensor(i8,&.{2,2}) = .{ .data = .{1,2,3,4} };` (function-body excerpt). It is a fixed storage helper, not an allocator/view/graph node. The caller chooses static or stack placement. [Tests](../../examples/docs/api.zig) use it alongside Definition and ImageDefinition.
