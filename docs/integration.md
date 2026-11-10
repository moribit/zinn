# Integrating Zinn into an existing application

Zig **0.17.0**, standard library only for host training and integer inference.
The application owns input acquisition, scheduling, output and memory. UART,
Service, board setup and flashing are optional application choices.

| Level | Entry point | Who owns the firmware? |
|---|---|---|
| Inference library | zinn_infer or addInferenceModule | Application |
| Model generation | addModel | Application |
| Complete workflow | addProject | Zinn preset, with configurable adapters |

## Add the package

The executable examples are independent packages with a local dependency:

```zig
.dependencies = .{ .zinn = .{ .path = "../../.." } },
```

Use a suitable relative path to your Zinn checkout, or a pinned remote package
obtained with `zig fetch --save`. Do not copy generated weights into source code.
Zinn exports zinn and zinn_infer. Dependency use defaults to library-only
configuration: no example firmware or HAL graph is instantiated. The root Zinn
checkout retains its full workflow. Set library-only=false explicitly if a
specialized dependency build needs the old complete configuration.

## Level 1: inference library

In build.zig, import the Build API and create a module for the consumer target:

```zig
const zinn = @import("zinn");
// Inside build(b), after creating app with the desired target:
const dep = b.dependency("zinn", .{});
const infer = zinn.addInferenceModule(b, dep, target, .safe);
app.root_module.addImport("zinn_infer", infer);
```

For a native default module, dep.module("zinn_infer") also works. The
[inference-only test](../examples/integration/host-app/library.zig) compiles this
package entry point and compares int8/packed int4. See [inference API](api/inference.md).
Existing @import("zinn") remains supported.

## Level 2: train and generate, without creating firmware

The [host application's build script](../examples/integration/host-app/build.zig)
is executable, including native inference and portable object builds. Its core is:

```zig
const trained = zinn.addModel(b, dep, .{
    .name = "sensor",
    .model = b.path("model.zig"),
    .dataset = .{ .csv = .{
        .training = b.path("train.csv"),
        .evaluation = b.path("validation.csv"),
    } },
    .training = .{ .epochs = 2000, .validation_count = 0, .decay_every = 0 },
    .format = .int4,
});
app.root_module.addImport("sensor_model", trained.createModule(b, target, .safe));
```

addModel returns immediately with a Build graph, not a trained model in memory.
Fitting/export run on the host only when needed. createModule creates a consumer
Module from the generated LazyPath; never reuse its internal host_generated
module in firmware. Generated sources retain @import("zinn") internally; the
helper wires that import to inference-only code.

Use **unique nonempty names** for multiple models in one owning Build. The default
steps are NAME-train, NAME-evaluate, NAME-generate and NAME-e2e. Explicit step_prefix
is available when composing a custom graph; it must be unique too. Names may use
letters, digits, hyphens and underscores. Each invocation retains its own
checkpoint/source/metadata/journal. Separate packages use their own local caches.

If the application imports the core itself, share the same Module instance:

```zig
const infer = zinn.addInferenceModule(b, dep, target, .safe);
app.root_module.addImport("zinn_infer", infer);
app.root_module.addImport("sensor_model", trained.createModuleWithCore(b, infer));
```

createModule automatically shares an inference Module for the same package,
target/CPU features/optimization. createModuleWithCore also accepts the existing
full zinn Module. Zig requires one Module owner per source file: do not create
independent full/inference modules for the same source closure in one executable.
A custom core must expose the generated layer APIs and match the consumer target.

```sh
zig build --build-file examples/integration/host-app/build.zig sensor-train
zig build --build-file examples/integration/host-app/build.zig sensor-generate sensor-e2e run
zig build --build-file examples/integration/multi-model/build.zig run other-e2e
```

The examples use the XOR-shaped CSV fixture; their exact-reference checks are
not MNIST accuracy measurements. generate includes evaluation/calibration/export;
e2e separately compares all logits with the independent reference.

Generated LazyPaths are build-cache outputs. Explicit workflow steps install:

- training/NAME.zinn and reports/NAME-training.csv
- models/NAME-int8.zig or NAME-int4.zig
- reports/NAME-model.json plus progress and summary sidecars

Simply compiling a consumer follows source dependencies without installing every
workflow report. Run NAME-generate when installed reports are desired. A supplied
checkpoint option skips fitting for consumers; selected_checkpoint is the actual
input while checkpoint remains the configured training output. Paths and existing
checkpoint v1/CSV/model JSON formats are unchanged.

## Use the generated model

```zig
const generated = @import("sensor_model");
const M = generated.Model;
var workspace: M.Workspace = .{}; // static MCU storage
var input: [M.input_len]i8 = undefined;
var output: [M.output_len]i8 = undefined;
// After the application fills the quantized input:
// M.infer(&input, &output, &workspace);
```

The input is signed int8 with zero point zero for exported models. Match the
training preprocessing exactly, then quantize real values using generated
input_scale: round ties away from zero, saturate to [-128,127]. Host code can use
export_model.quantizeInput. MCU code should receive already quantized bytes or
use application-specific integer preprocessing; do not add runtime float merely
to read scale metadata. Input/output scale and model ID are in generated source
and metadata; quantization format is available as trained.format.

Weights are immutable constants. Inference is reentrant with **separate mutable
input/output/workspace for every concurrent call**. Never share workspace between
an ISR and main loop without serialization. Input/output may overlap as specified
by Sequential, but neither may overlap workspace. Inference time/interrupt latency
is not measured here; schedule work accordingly.

## Existing ch32fun_zig firmware

See the [CH32 integration tutorial](tutorials/ch32-integration.md) and
[complete build script](../examples/integration/ch32-existing-app/build.zig).
The application still calls ch32.addFirmware and retains its main loop, GPIO,
interrupts and initialization. Zinn does not create another firmware or Service.
For the default ch32fun runtime:

```zig
const app_module = firmware.root_module.import_table.get("app").?;
app_module.addImport("sensor_model", trained.createModule(b, ch32.ch32Target(b), .small));
```

For runtime=.application attach directly to firmware.root_module instead. These
are standard root_module.addImport calls, not a HAL-specific attach abstraction.
Multiple models use arbitrary distinct import names; see the
[multi-model sample](../examples/integration/multi-model/build.zig).

## Check the complete application ELF

```zig
const memory = zinn.addMemoryCheck(b, dep, .{
    .name = "existing-app", .elf = firmware.getEmittedBin(),
    .flash_bytes = 16384, .ram_bytes = 2048,
    .stack_bytes = 512, .isr_bytes = 64, .reserved_flash_bytes = 64,
});
b.getInstallStep().dependOn(memory.step);
```

The check reads the final ELF, including caller code, statics, input/output and
workspace actually retained by the linker. Invalid regions and capacity overflow
fail the Build. Custom ELF32 maps can set flash_origin, ram_origin and target_name;
the defaults describe CH32V003 and do not imply other board support. JSON/text reports install under reports/NAME-memory.*. The
stack_allowance_bytes field is **stack_bytes + isr_bytes**, not a measured stack.
RAM margin subtracts this allowance and static RAM. RAM reserved by an application
outside ELF must be included explicitly in allowances or subtracted from limits.
Model.parameter_bytes/activation_bytes/checkBudget are model estimates, not a
replacement for this final ELF check. Model metadata/constant folding/alignment,
runtime and linker retention account for differences.

## Portability and verification

```sh
zig build --build-file examples/integration/host-app/build.zig library-test portability
zig build --build-file examples/integration/ch32-existing-app/build.zig
bash tests/integration.sh zig /tmp/zinn-integration
```

The portability step compiles Linux x86_64 and Cortex-M33 freestanding inference
objects without HAL/startup/linker setup. The latter is relevant to RP2350's ARM
core but **is not an RP2350 board port**. CH32 is cross-built; physical sensor,
GPIO behavior, cycles and stack high-water remain unverified without hardware.
Native Linux execution is covered by CI, distinct from cross-compilation on macOS.
See [verification report](integration-report.md) and [audit](integration-audit.md).

## Level 3: full workflow

Use addProject when you want the existing UART firmware preset, host replay,
capacity checking and explicit flash step. Its options and Artifacts remain
compatible. It delegates training/export/reference verification to the same
addModel implementation. Neither level flashes unless explicitly requested.

For a complete interactive desktop application using a bundled MNIST model, see
the optional [mimoc-ui handwriting example](../examples/mnist-desktop/README.md).
Its UI dependencies do not enter MCU or root-library builds.
