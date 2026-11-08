# Getting Started

This host-first tutorial requires no hardware. It performs only the small XOR fit, never real MNIST training or physical flashing.

## Prepare Zig0.17.0

Install exactly0.17.0 using your Zig installation/version manager. Check the compiler selected by PATH:

```sh
zig version
```

Expected: `0.17.0`. Later Zig versions may have incompatible standard-library/Build APIs. macOS and Linux are the intended development environments; CI is configured for both.

## Get Zinn and its dependency

```sh
git clone https://github.com/moribit/zinn.git
cd zinn
```

The checkout includes a fixed [ch32fun_zig snapshot](../vendor/ch32fun_zig/UPSTREAM.md) for board support, including its MIT notice. No submodule setup, package download, Python, C compiler or ML runtime is required. Network is needed for cloning, not subsequent tests/XOR builds. See [licenses](licenses.md).

## Run host tests

```sh
zig build test
zig build test -Doptimize=safe
zig build docs-check
```

Tests cover numerical/Golden behavior and expected compile failures. docs-check validates local Markdown links and executable API examples without fitting a dataset.

Host progress is separate from stdout reports. Add -Dprogress=plain or -Dquiet=true to root commands. Cacheable training/export phases save detail in zig-out/reports/*-progress.log; auto can update Zig's progress UI. See [controls and limitations](progress.md).

## Train and evaluate XOR

```sh
zig build train
zig build evaluate
zig build eval -Dcheckpoint=zig-out/models/xor.zinn
```

train saves `zig-out/models/xor.zinn`. evaluate defaults to the same deterministic cached fit; eval with checkpoint explicitly loads that file. Four examples form the full XOR truth table:4/4 is a functional check, not held-out accuracy. The shared model is [examples/xor/definition.zig](../examples/xor/definition.zig).

## Quantize and infer on the host

```sh
zig build quantize -Dcheckpoint=zig-out/models/xor.zinn
zig build e2e -Dcheckpoint=zig-out/models/xor.zinn
```

Generated integer source: `zig-out/models/xor.zig`. e2e compiles it, runs all four inputs and compares every logit with an independent integer reference. int8/int4 reuse the same float checkpoint.

## Generate CH32V003 firmware

```sh
zig build deploy -Dcheckpoint=zig-out/models/xor.zinn
zig build size -Dcheckpoint=zig-out/models/xor.zinn
```

Default XOR deploy emits `zig-out/bin/zinn-trained-production` (ELF, no extension) and `zig-out/firmware/zinn-trained-production.bin`, and checks the final ELF budget. size checks manual XOR and trained diagnostic/production builds, saving `zig-out/reports/*-memory.json/.txt`. The512B stack allowance is a reservation, not a measurement.

**deploy never flashes hardware.** XOR production is a minimal embedded example; application-owned CSV/MNIST projects use framed UART firmware instead. A cross-build does not establish physical inference or timing.

Optional: try int4 from the same checkpoint after completing the int8 flow:

```sh
zig build e2e deploy -Dcheckpoint=zig-out/models/xor.zinn -Dweight-format=int4
```

Keep the format option on every related command; omitting it returns to int8. Generated source paths in the legacy XOR tool are shared across formats, so retain copies if comparing both.

## Next

[Train XOR](tutorials/xor.md) explains the API. [Custom CSV Classifier](tutorials/csv-classifier.md) takes you to a standalone Zig package with its own model/data/build script. Then read [MNIST](tutorials/mnist.md), [UART](tutorials/uart.md) and the [API reference](api/README.md).
