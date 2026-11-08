# Tutorial 1 — Train XOR

First complete [Getting Started](../getting-started.md). Run commands from the Zinn checkout, using Zig0.17.0.

## Shared structure

[examples/xor/definition.zig](../../examples/xor/definition.zig) defines two inputs, a ReLU hidden layer of8, and two logits with no final activation. Both Trainer and exporter consume that Structure. The four one-hot targets encode equal/different input bits. Keep logits unactivated for cross entropy; the legacy XOR tool uses MSE.

```sh
zig build train
zig build evaluate
zig build quantize -Dcheckpoint=zig-out/models/xor.zinn
zig build e2e -Dcheckpoint=zig-out/models/xor.zinn
zig build e2e -Dcheckpoint=zig-out/models/xor.zinn -Dweight-format=int4
```

Output `.zinn` holds float parameters; generated `.zig` holds quantized parameters and a compile-time model. e2e reports integer logits/class and exact reference agreement. The four training cases also form the verification truth table: this is not generalization evaluation.

## API behind the tools

See the executable [API sample](../../examples/docs/api.zig): initialize Trainer(Structure) with a seed, call trainBatch or trainEpoch, evaluate, encode/decode, calibrate QuantizedFormat, encode each input using the calibrated scale, then infer. It checks saving and both integer formats without assuming an untrained model has learned XOR. [Training](../api/training-data.md) and [export](../api/quantization-export.md) document signatures/errors.

The existing hand-written low-level XOR remains separately available:

```sh
zig build xor
```

It checks fixed Golden vectors. Do not substitute its parameters/results for the trained model's logits. For a user-owned model and CSV dataset, continue with [Tutorial2](csv-classifier.md).
