# Quantization and export

[Quant source](../../src/quant.zig), [export source](../../src/export.zig), [numeric contract](../quantization.md), [executable example](../../examples/docs/api.zig).

## Runtime arithmetic

`quant.Params` fields: multiplier:u16=1, shift:u5=0, input_zero:i8=0, output_zero:i8=0, optional input_scale/weight_scale/output_scale:?f32=null. `validate(comptime self:Params) void` rejects zero multiplier, partial/nonpositive/nonfinite scales, and scale-ratio mismatch beyond relative1e-4. Dense/Conv invoke it at compile time. `quant.requantize(value:i32,p:Params) i8` uses an i64 product, nearest rounding/ties away from zero, output zero-point and saturation; `quant.relu(value:i8,zero:i8) i8` clamps to real zero. Direct callers must provide valid Params; requantize itself does not run compile-time metadata validation.

## Host conversion

- `export_model.coefficient(ratio:f64) !quant.Params`: nearest representable multiplier/2^shift; InvalidScale or UnrepresentableScale if no coefficient within relative1e-4.
- `export_model.quantizeInput(value:f32,scale:f32) !i8`: round(value/scale), clamp[-128,127]; InvalidScale for invalid inputs/scale. No image preprocessing is performed.
- `export_model.Quantized(comptime S:type) type`: int8 alias.
- `export_model.QuantizedFormat(comptime S:type,comptime format:lowbit.Format) type`: host calibration/reference/export container. format=int8/int4.

Returned type methods:

| Method | Result / errors |
|---|---|
| calibrate(model:*const Trainer(S),samples:[]const Trainer(S).Sample) | !Self; EmptyCalibration, nonfinite parameters/input/activation, InvalidScale, BiasOverflow, AccumulatorOverflow, UnrepresentableScale |
| infer(self:*const Self,input:*const [S.input_len]i8) | `[S.output_len]i8`; independent int64/division reference, **not the small MCU core** |
| modelId(self:*const Self) | u32 fingerprint of structure/quantized contents; not authentication |
| writeSource(self:*const Self,writer:*std.Io.Writer) | !void; emits a compile-time Sequential model, arrays, schema_tag, model_id, input_scale/output_scale |
| writeVerification(self:*const Self,writer:*std.Io.Writer,samples:[]const Trainer(S).Sample) | !void; appends inputs/expected logits; EmptyVerification/invalid scale/writer errors |

Calibration uses symmetric max-absolute per-layer weights/activation scales, zero0. int8 exporter weights[-127,127]; int4[-7,7]; pooling preserves scale. Calibrate only on training/representative data, never the final test split. Bias scale is input_scale×weight_scale. Adjacent generated scales share exact bits; integer coefficients approximate the ratio.

The host container uses oversized parameter-indexed arrays and local activation buffers. Its int4 reference still stores decoded weights: **writeSource packs deployment weights**. Never embed this host container/Trainer into MCU firmware. Use generated `Model.infer` with caller-owned workspace. Source scale floats are compile-time metadata, not runtime MCU arithmetic. Per-channel quantization/QAT/clipping search are not implemented.
