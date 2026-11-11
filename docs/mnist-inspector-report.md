# MNIST inspector verification record

2026-11-12. Baseline Zinn `7eb74c6`; mimoc-ui latest main/pin
`5486c9cc4d7a67eeb3c385dee836a2081d112322`. No upstream UI changes required.
The separate [WASM project](https://github.com/moribit/zinn-mnist-web) imports the
same App directly; both source/deploy pipelines were inspected before changes.

## Numerical and UI contracts

- `infer` and `inferTraced` share kernel execution. All 16 bundled samples retain
  every logit and prediction. Hidden trace equals standalone Dense output.
- Reconstructing every hidden activation from inspected weights/bias/quantization
  matches the kernel on all samples. Additional generic tests cover int4 signed
  accessors, single-layer aliasing, four layers, and workspace reuse.
- PLAY below y=32 is pixel-identical to its pre-change first-sample snapshot:
  FNV64 `be7698fae0a7df11`. Only the header adds the mode navigator/active underline.
- NETWORK after the same SAMPLE/navigation/timestamp sequence has identical
  native and WASM framebuffer FNV64 `44d3f2fa2e1667f2`.
- Tests cover real widget mode switching, hidden/output hit tests, bounded stages,
  replay, pause, clear, input preservation, snapshot replacement, deterministic
  strongest-edge selection and absence of extra inference on ticks/navigation.
- The model/checkpoint/generated weights, input normalization, int8/int4 numeric
  specification and export formats are unchanged.

## Host performance

The example `benchmark` step measures five trials, each with 1,000 warm-up and
5,000 measured iterations, retaining output checksums. Host: Apple Silicon macOS,
Zig 0.17.0, ReleaseSafe. Inference includes the original integer kernels;
rendering includes mimoc-ui widget construction and Mono1 framebuffer generation.
These are CPU costs, **not monitor FPS**, not browser compositor latency, and not
MCU measurements. Timings vary with system load; small changes are not speedup claims.

Five-trial median nanoseconds per operation (baseline/current run sequentially):

| Operation | Before | Inspector version |
|---|---:|---:|
| Ordinary integer inference | 3,366 ns | 3,253 ns |
| Traced integer inference | not available | 2,901 ns |
| PLAY framebuffer | 46,480 ns | 45,015 ns |
| NETWORK framebuffer | not available | 57,615 ns |

The traced call being slightly faster than the ordinary call in this run is
measurement/order noise, not an optimization claim. NETWORK generation is about
0.058ms per frame on this host, excluding presentation; actual display FPS and
browser frame times are unmeasured. The fixed native timer/browser RAF schedules
replay independently of inference. The optional benchmark is not linked into the UI.

ReleaseSmall WASM grows from 109,267 B to 118,840 B (+9,573 B); ReleaseSafe is
905,646 B. These are the complete browser module, not the MCU model size.

The browser adapter requests animation frames only while replay is active.
The logical framebuffer stays 16,320 bytes; the app adds a 42-byte trace plus
small selection/timestamp state. Input and workspace remain caller-owned, with
no per-frame heap allocation in Zig. Host-only graph rendering draws at most
30 standard/hidden-focused or 32 output-focused connections.

## Embedded regression

Final-ELF reports before/after are identical:

| Existing CH32V003 artifact | Flash | Static SRAM | Stack allowance |
|---|---:|---:|---:|
| Hand-authored XOR | 3,148 B | 12 B | 512 B |
| Trained XOR production | 1,508 B | 16 B | 512 B |
| Trained XOR diagnostic | 4,188 B | 24 B | 512 B |

Stack allowance is a configured budget, **not a measured high-water value**.
Inspector code is example-only; ordinary inference emits no trace copies.
No hardware execution, device latency or stack high-water is claimed.

## Validation

Local results: core Debug/ReleaseSafe 58/58 tests plus all 18 compile-fail checks;
MNIST component Debug/ReleaseSafe 20/20 tests. Deliberately undersized 1,024-byte
Flash budgets are rejected. Offline Markdown validation checks all local links
and compiles the API example including inferTraced.

Local verification uses these existing steps (offline fixtures are not MNIST
accuracy evaluation):

```sh
zig build test
zig build test -Doptimize=safe
zig build docs-check
zig build e2e -Dprogress=off
zig build e2e -Dweight-format=int4 -Dprogress=off
zig build data-train -Dcsv-train=examples/data_classifier/train.csv -Dcsv-test=examples/data_classifier/test.csv -Dweight-format=int4 -Dprogress=off
zig build --build-file examples/rl-cartpole/build.zig test -Doptimize=safe
zig build --build-file examples/rl-cartpole/build.zig test-gui -Doptimize=safe
zig build size -Dprogress=off
```

MLP/CNN × int8/int4 host reference and cross-build checks use:

```sh
zig build mnist mnist-firmware -Dmnist-fixture=true -Dmnist-epochs=1 -Dmnist-model=mlp -Dweight-format=int8 -Devaluation-split=test -Dprogress=off
```

Repeat with `-Dmnist-model=cnn` and `-Dweight-format=int4` for the other combinations.
All four retain exact 16/16 fixture reference matching. Desktop Debug/ReleaseSafe
and snapshot/benchmark commands are in the [guide](mnist-inspector.md).
The Web project tests both optimization modes, verifies zero WASM imports,
all reference logits, drawn seven, real widgets, animation and framebuffer golden.
CI includes Linux/macOS component tests and macOS PLAY/NETWORK/STEP snapshots;
the separate Pages workflow verifies both OS jobs before publishing.

## Manual platform checks and limits

- macOS real window: launch, original PLAY, keyboard SAMPLE/mode switching,
  staged NETWORK activation/logit reveal observed.
- Chrome on macOS/Retina: original PLAY, mouse SAMPLE, mode buttons, hidden/output
  selection, STEP Pause/Next and animation observed using the actual browser UI.
- Physical phone/tablet touch, other browser engines, arbitrary native window
  resizing, long-running frame pacing and measured display FPS remain unverified.
  Existing pointer capture/cancellation and CSS coordinate mapping are retained.
- Inspector text is English. Japanese documentation is provided; Japanese font/UI
  language selection is not implemented. No new training or accuracy claim.
