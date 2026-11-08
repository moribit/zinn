# Inference and explicit workspace

[Dense/Sequential source](../../src/model.zig), [Conv/Pool](../../src/cnn.zig), [packed formats](../../src/packed.zig), [executable API sample](../../examples/docs/api.zig).

## Layer constructors

`Dense(comptime config:DenseOptions) type` takes input/output:usize, bias:[]const i32; optional weights:[]const i8, packed_weights:[]const u8, format=.int8, quant=.{} and activation=.none. DenseOptions is defined in model.zig; normal callers use inferred literals. Weights are output-major, bias in accumulator units.

`Conv2D(comptime c:ConvOptions) type` takes input:Shape, output_channels:usize, bias and optional weight/format/quant/activation fields as above; kernel3,stride1,padding0. Layout HWC; weights `[output channel][kernel y][kernel x][input channel]`. Padding skips input positions, equivalent to quantized real zero. No im2col scratch allocation.

`AveragePool2D(comptime c:PoolOptions) type` takes input:Shape, kernel2,stride2,zero0,scale:?f32=null,activation=.none. Valid-only pooling preserves channels, zero point and scale. Signed average rounds ties away from zero. No weights or independent requantization.

All return types expose input_len/output_len, input_zero/output_zero, input_scale/output_scale, parameter_bytes and `run(input:*const [input_len]i8,output:*[output_len]i8) void`. Conv/Pool also expose input_shape/output_shape. Compile-time failures cover nonpositive/invalid shapes, weight/bias lengths, invalid packed tail, int32 accumulation bounds and scale consistency. Individual run calls require nonoverlapping input/output; use Sequential for its documented alias support.

## Sequential and Workspace

`Sequential(comptime layers:anytype) type` takes a nonempty tuple of layer types. It checks flattened lengths, spatial shapes when available, zero points and exact adjacent optional scales. Legacy metadata-free layers may connect to each other; mixed metadata is rejected. It exposes parameter_bytes, activation_bytes, workspace_bytes and a Workspace type.

Function-body usage (tested in the sample):

```zig
const M = zinn.Sequential(.{zinn.Dense(.{
    .input = 2, .output = 2,
    .weights = &.{ 1, 0, 0, 1 }, .bias = &.{ 0, 0 },
})});
var ws: M.Workspace = undefined;
var out: [M.output_len]i8 = undefined;
M.infer(&.{ 3, 9 }, &out, &ws);
```

`M.infer(input:*const [M.input_len]i8,output:*[M.output_len]i8,ws:*M.Workspace) void` allocates no heap and performs no floating-point computation. Input/output may overlap each other but **neither may overlap workspace**. Each concurrent inference needs its own workspace. Intermediate buffers use parity maxima of layer outputs; first input/last output are used directly. A single-layer model reserves input-sized alias scratch. Treat Workspace fields as implementation detail; use its type/size instead of assuming two full tensors. Place it in static storage for MCU applications.

`zinn.argmax(values:[]const i8) ?usize` returns the first maximum or null on empty input. ReLU is a layer option or quant.relu; it is not a separate graph node.

## Packed int4

`zinn.lowbit.Format` is int8/int4. For int4 use format=.int4,packed_weights and no int8 weights. Nibble0 is the first weight, nibble1 the next, no row padding; an odd final unused high nibble must be0. Decoder accepts signed[-8,7]; exporter uses symmetric[-7,7]. `lowbit.encode(values:[]const i8,out:[]u8) !void` requires exact ceil(N/2) length and range[-8,7]. See source for helper signatures. Activations/workspace remain int8; packed weights decode on demand, trading Flash for CPU work. No real MCU speed comparison has been measured.
