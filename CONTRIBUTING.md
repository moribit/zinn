# Contributing

Use Zig **0.17.0** on macOS/Linux. Clone the repository normally: the MIT-licensed board snapshot is included. No Python/ML framework is needed. Follow the existing small, explicit Zig style and keep the portable core independent of HAL imports. Preserve low-level APIs, checkpoint v1 and int8/int4 numerical behavior unless a versioned migration is explicitly discussed.

## Before a pull request

```sh
zig build test
zig build test -Doptimize=safe
zig build docs-check
zig build xor
zig build e2e
zig build e2e -Dweight-format=int4
zig build deploy size
zig build --build-file examples/project/build.zig train evaluate deploy infer-host simulate-uart
```

Formatting (avoid generated Zig in nested zig-out):

```sh
zig fmt --check build.zig build.zig.zon build_support src tests tools examples/xor examples/mnist examples/data_classifier examples/docs examples/project/build.zig examples/project/build.zig.zon examples/project/model.zig
```

CI runs host Debug/ReleaseSafe, compile-fail, MLP/CNN×int8/int4 fixture reference comparisons/cross-builds, capacity rejection and external Build API checks on Linux/macOS. docs-check adds offline link/anchor and executable API checks. See [CI](.github/workflows/ci.yml) for the exact matrix. Real MNIST fitting/download and physical flash are not required for routine contributions. Report which OS/checks you actually ran; configured CI is not evidence it passed remotely.

## Numerical changes and new operators

Define layouts/shapes/zero points/scales/rounding/saturation first. Add unit boundaries, positive/negative/tie cases, overflow proofs/rejections, invalid-shape compile failures, int8/int4 variants and independent-reference **all-logit** tests. Avoid a reference that simply calls the same indexing/arithmetic helper. Train/backprop additions need finite-difference gradients and save/export integration. Keep Golden vectors stable; explain any intentional versioned change rather than regenerating expected values silently.

## Tiny-target review

No MCU heap, recursion, floating-point computation or dynamic model graph. Keep weights constant in Flash and workspace explicit. Include final ELF Flash/static RAM/stack allowance/margin before and after; parameter count alone is insufficient. Discuss any increase and keep negative capacity tests. Do not call static stack estimates or fake-clock simulation hardware measurements. Board changes need clock/package/pin/provenance and actual verification status. Read [budgets](docs/api/budgets.md) and [benchmarks](docs/benchmarks.md).

Document API/build-option changes, add compiled examples where practical, preserve historical evidence, and update both READMEs when claims change. Keep experimental dependencies out of the required toolchain. For design discussion use repository issues; for sensitive defects see [SECURITY](SECURITY.md). Follow the [Code of Conduct](CODE_OF_CONDUCT.md).
