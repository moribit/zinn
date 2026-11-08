# Benchmarks and verification

Representative evidence recorded2026-11-07 with Zig0.17.0 on macOS arm64. These results are not measurements newly performed by this documentation pass. [Raw manifests/curves](experiments/README.md) and [full analysis](practicality-report.md) retain provenance. [Initial baseline](benchmarks-initial.md) and [older MNIST](mnist-report.md) are historical and use different configurations.

## What is verified

| Category | Evidence / status |
|---|---|
| Host f32 training/evaluation | Real MNIST; deterministic train/validation split and selected checkpoints |
| Host integer inference | Every logit matches independent int64/division reference on all10,000 official test samples per configuration |
| CH32V003 build | RV32EC ELF/bin cross-build including startup/runtime/HAL/UART/CRC/benchmark service |
| Flash/static SRAM | Final ELF PT_LOAD accounting,64B Flash reservation |
| Static stack estimate | Optional normal direct-call disassembly estimate; IRQs excluded |
| MCU cycles/latency | **Unmeasured** |
| Physical UART/logits | **Unverified** |
| MCU stack high-water/startup peak | **Unmeasured**; since-ready paint implemented, not startup measurement |

## Frozen representative configurations

Official [CVDF MNIST mirror](https://github.com/cvdfoundation/mnist), training60,000/test10,000. Area28×28→16×16, /255, HWC. split_seed24301 gives55,000 training +5,000 validation; seed42 initialization/training shuffle, mini-batch32, SGD/CE. Learning rate decays×0.3 after10 epochs. Checkpoints selected by best validation accuracy then lower CE. Official test is used only after fixing configuration; calibration1024 uses training partition only. int8/int4 share the float checkpoint.

- MLP:256→32/ReLU→10 logits, rate0.1, max20 epochs, best epoch13; f32 test96.62%.
- CNN:Conv3×3/channels4/ReLU→AveragePool2×2/stride2→Dense10, rate0.05, max20 epochs, best epoch19; f32 test97.06%.

| UART firmware | Integer test | Parameters B | Flash B | Static SRAM B | Workspace B | Static stack estimate B | RAM margin after512B allowance |
|---|---:|---:|---:|---:|---:|---:|---:|
| MLP32 int8 | 96.59% | 8680 | 12408 | 460 | 32 | 252 | 1076 |
| MLP32 int4 | 94.90% | 4424 | 8184 | 460 | 32 | 256 | 1076 |
| CNN4 int8 | 97.07% | 2052 | 6436 | 1408 | 980 | 224 | 128 |
| CNN4 int4 | 95.21% | 1054 | 5496 | 1408 | 980 | 224 | 128 |

Parameters count weights+bias, not total binary. Flash includes runtime/transport/helpers and is limited to16320B usable of16384B. Static RAM includes all linked globals/transport/workspace, **not stack**.512B is a budget, not a measurement. CNN4's128B remaining RAM restricts added application features/IRQs. Budget flags do not alter hardware capacity/linker placement. The50ms inference goal remains unverified. Default model widths remain MLP16/CNN2; these rows require explicit options.

## Reproduce intentionally

This performs real fitting; it is not required for offline documentation checks:

```sh
zig build mnist-download
ZIG=zig sh tools/validation-study.sh data/mnist
zig build deploy infer-host simulate-uart -Dproject=mnist -Ddata-dir=data/mnist -Dproject-checkpoint=zig-out/models/val-mlp32-lr1-e20-s42.zinn -Dmnist-hidden=32 -Dapp-name=final-mlp-int8 -Devaluation-split=test -Drequest=benchmark
zig build deploy infer-host simulate-uart -Dproject=mnist -Ddata-dir=data/mnist -Dproject-checkpoint=zig-out/models/val-mlp32-lr1-e20-s42.zinn -Dmnist-hidden=32 -Dweight-format=int4 -Dapp-name=final-mlp-int4 -Devaluation-split=test -Drequest=benchmark
zig build deploy infer-host simulate-uart -Dproject=mnist -Ddata-dir=data/mnist -Dproject-checkpoint=zig-out/models/val-cnn4-e20-s42.zinn -Dmnist-model=cnn -Dcnn-channels=4 -Dapp-name=final-cnn-int8 -Devaluation-split=test -Drequest=benchmark
zig build deploy infer-host simulate-uart -Dproject=mnist -Ddata-dir=data/mnist -Dproject-checkpoint=zig-out/models/val-cnn4-e20-s42.zinn -Dmnist-model=cnn -Dcnn-channels=4 -Dweight-format=int4 -Dapp-name=final-cnn-int4 -Devaluation-split=test -Drequest=benchmark
```

The study script runs eight prespecified validation comparisons; it never opens official test files. Do not select a different seed/model based on final test results. Keep script/options/curves beside checkpoints, because v1 lacks preprocessing/split provenance. Optional `stack-audit` with the same project options and -Dobjdump=/path/to/llvm-objdump checks static direct-call bounds; LLVM is not required for standard builds.

## Hardware measurements

Use [UART Tutorial](tutorials/uart.md) with identical model/checkpoint/input. Explicitly flash, record clock/board/firmware identity, send benchmark frames, check all logits against host and retain captures. The service warms up once and measures9 inferences, subtracts minimum timer-read overhead and reports min/median/max. Keep input transfer, preprocessing and adapter initialization separate. Fake-board simulation is only a protocol test; never interpret its cycle fields as CPU performance.

Record stack paint as since-ready high-water, not startup maximum; IRQ-enabled applications need additional analysis/measurement. Compare int4 Flash savings against decode/64-bit-requantization cycle cost only after real captures exist. Do not fill missing measurements with estimates.

## Research results versus public highlights

The [fixed validation plan](validation-plan.md) and [analysis](practicality-report.md) compare widths/rates/epochs/resize/calibration and a separate seed43 repeat. Earlier MLP16/CNN2 tests used all60,000 training examples with no validation; they are not a controlled single-variable comparison with the rows above. README uses only the frozen representative table. Keep exploration results in dated records and update highlights only with reproducible, clearly categorized evidence.
