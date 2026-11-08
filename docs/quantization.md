# Numerical contract v1

Inputs/outputs/activations are signed int8. Weight zero point is always0. Input zero zi and output zero zo are signed int8. Dense weights are output-major; bias is in accumulator units:

```text
acc = bias[o] + sum((i32(input[i]) - zi) * i32(weight[o,i]))
y = clamp_i8(round_nearest_ties_away(acc * multiplier / 2^shift) + zo)
relu(y) = max(y, zo)
```

multiplier1..65535, shift0..31, positive scale only. No bit-compatibility with TFLite/CMSIS Q31/two-stage rounding is claimed. Kernel/compiler-failure tests preserve this contract.

## Accumulation and requantization

Each Dense row/Conv output channel must satisfy the conservative compile-time bound:

```text
abs(bias) + max(127-zi,128+zi) * sum(abs(weights)) <= 2147483647
```

This proves every partial sum fits int32 for all possible int8 inputs. It deliberately rejects even the special bias=-2147483648-only case. Overflow is not hidden by wrapping/saturating the accumulator. Conv's bound covers the full kernel; padding can only remove contributions.

Requantization alone uses an i64 intermediate product. Convert i32 to i64 before taking absolute value. Add half to nonnegative magnitude, shift, restore sign, then add zo and clamp[-128,127]. This avoids depending on signed right-shift rounding. Examples:+3/2→+2,-3/2→-2,-2/2→-1; shift0 adds no half. Worst supported product plus half remains within i64. On RV32EC, software i64 helpers have code/cycle cost; real cycles remain unmeasured.

## Scale metadata

Params accepts optional input_scale/weight_scale/output_scale. Supply all three or none. Values must be positive/finite, and input_scale×weight_scale/output_scale must agree with multiplier/2^shift within relative1e-4. Adjacent output/input scales must match exactly (including whether metadata exists). Exporter passes the same f32 bit pattern between layers. Metadata-free legacy layers keep their integer contract, but cannot establish real-value scale consistency. Float metadata is compile-time-only in generated inference.

Host quantizeInput rounds value/scale to nearest/ties away then saturates[-128,127]. Export uses symmetric zero0, max-absolute activation calibration/per-layer weight scales and int32 bias. Calibration comes from training only. Pooling preserves activation scale. See [export API](api/quantization-export.md).

## Packed int4 and spatial operators

Dense/Conv format=.int4 uses packed_weights with no int8 weights. First weight is low nibble, next high nibble; contiguous across rows, no row padding. For odd length, unused last high nibble must be0. Decode two's-complement[-8,7]; exporter uses symmetric[-7,7] and weight_scale=max_abs/7. Activations/workspace stay int8, bias/accumulator int32. Weights decode on use without an expanded buffer.

Conv weights order is [output channel][kernel y][kernel x][input channel]; activations HWC. Padding means real zero (input_zero), implemented by skipping contributions. AveragePool sums(input-zero), divides by area with nearest/ties-away rounding and adds zero back. It has no independent requantization coefficient; input/output scales and zero point are identical. ReLU clamps at the encoded real zero.

Authoritative implementations: [quant](../src/quant.zig), [Dense](../src/kernels/dense.zig), [Conv/Pool](../src/cnn.zig), [packed layout](../src/packed.zig). Preserve independent reference/Golden tests when changing these paths.
