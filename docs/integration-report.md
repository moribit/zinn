# External integration verification

Baseline: 1d24f44. Local platform: macOS arm64, Zig 0.17.0.
No new libraries or ch32fun_zig changes. No hardware was flashed.

## Public additions and implementation

- src/infer.zig / package zinn_infer: shared integer layer/quant/workspace APIs.
- addInferenceModule(b,dep,target,optimize): shared consumer-target core Module.
- addModel and ModelOptions: host-only fit/evaluate/calibrate/export/reference
  graph extracted from addProject into build_support/model.zig.
- Model artifacts expose LazyPaths, workflow Steps and createModule /
  createModuleWithCore. Target compilation is distinct from host tool execution.
- addMemoryCheck and MemoryOptions: caller-owned final ELF check with configurable
  origins/limits, stack allowance and ISR allowance; shared with addProject.
- Dependency configuration defaults to library-only; root CLI defaults unchanged.

Existing ProjectOptions/Artifacts, root zinn exports, model definitions, checkpoint
v1, CSV and model JSON are retained. The new project generate step is additive.
Generated source still imports zinn; no generated model schema or numerical change.
No target-side service, heap or float is introduced by the integration helpers.

## Executable examples

See [host-app](../examples/integration/host-app/build.zig),
[existing CH32 app](../examples/integration/ch32-existing-app/build.zig) and
[multi-model](../examples/integration/multi-model/build.zig).
The first uses a normal executable with caller-owned buffers. The second keeps
ch32.addFirmware and GPIO/main-loop ownership, injecting only a generated model.
The third uses independently trained int4 2→8→2 and int8 2→4→2 models, each with
separate workspace and import name. No manual weight copying or UART is required.
The generated model helper shares one core source owner, required by Zig.
The CH32 loop reads exported pseudo-sensor bytes through a volatile pointer so
runtime inference is retained, and initializes the existing system/GPIO HAL.

## Local checks

```sh
zig build test docs-check --summary all
zig build test -Doptimize=safe --summary all
bash tests/integration.sh zig /tmp/zinn-integration
bash tests/progress_cli.sh zig /tmp/zinn-integration-progress
bash tests/progress_pty.sh zig /tmp/zinn-integration-pty
bash tests/cli_consistency.sh zig /tmp/zinn-integration-cli
```

Core Debug/ReleaseSafe checks preserve the 51 numerical/progress tests and 18
compile-failure cases. The 2 documentation API tests and 288 local links (56 Markdown files) pass.
The inference-only package test compares Dense int8/packed int4 and argmax.
Host generated inference checks all stored fixture logits; E2E uses the existing
independent reference. These are synthetic/CSV correctness tests, not accuracy
measurements on MNIST.

The integration script checks unique model artifacts and workflows, repeat/cache
receipts, independent host inference, consumer-only GPIO rebuild without export
rerun, and final ELF rejection at 1024B Flash. Checkpoint, CSV, generated source
and model JSON for the seed42/two-epoch MNIST fixture remain byte-identical to
the earlier baseline artifacts. Existing progress suites exercise modes,
concurrency, interruption and stale journals. No new speed improvement is claimed.

## Capacity and portability

CH32 existing-app: **1560B Flash, 20B static SRAM**, stack 512B plus ISR 64B
allowance, RAM margin 1452B. Its tiny model parameters occupy 56B by type estimate;
workspace 8B, input 2B, output 2B. Final ELF includes startup/application/GPIO and
actual retained model constants. Stack 576B in JSON is the combined budget,
not a static proof or measured high-water. Actual ISR depth must be budgeted by
its application. XOR production remains **1508B Flash /16B static SRAM**.

The legacy full UART CSV preset cross-builds with 3796B Flash/168B static SRAM;
512B stack allowance and 1368B margin. Its larger protocol runtime is a different
application, not an inference-kernel regression.

The portability step compiles Linux x86_64-musl and Cortex-M33 Thumb freestanding
objects containing actual generated inference, without a HAL. This is relevant
to RP2350 ARM portability only; no RP2350 startup/linker/peripherals or board
support is implemented. macOS native runs locally; Linux native execution is
configured in GitHub Actions and must be distinguished from local cross-builds.

## Limits and next work

Hardware inference, GPIO/sensor behavior, cycles, interrupt latency and stack
high-water remain unverified. addMemoryCheck currently reads ELF32 little endian;
ELF64 host executables are outside that MCU checker. UART Service remains optional
and unchanged. Runtime quantization is the caller's responsibility; generated
scales are comptime/host metadata. Separate input/output/workspace or explicit
serialization is required for concurrent/ISR use.

Unique names and explicit prefixes are necessary within an owning Build. Custom
Build scripts should set build_file as documented; the existing presenter option
forwarding limitations still apply. Compile-time parameter estimates are not a
whole-application memory guarantee. No new MNIST accuracy or physical performance
result is reported. See [integration guide](integration.md) and
[audit](integration-audit.md) for usage and source/dependency boundaries.

The new standalone library test, full-zinn compatibility executable, two-model
inference and both portability objects pass locally. The custom ELF label/origin
argument path is also exercised; this is not additional board support.

Legacy/common MLP16/CNN2 × int8/int4 cross-build, host inference and UART simulation
also pass. Final UART capacities remain MLP16 int8 8084B/444B, MLP16 int4
5984B/444B, CNN2 int8 5380B/916B and CNN2 int4 4936B/916B (Flash/static RAM).
These match the preceding phase. Native Linux/macOS suites are configured in CI;
remote status is separate from the completed local macOS checks.
