# Build API and command options

[Root build](../../build.zig), [implementation and complete Options](../../build_support/project.zig), [external example](../../examples/project/build.zig).

## addProject

```zig
pub fn addProject(b:*std.Build, dependency:?*std.Build.Dependency, options:Options) ?Artifacts
```

Import the Zinn **dependency build module** in your build.zig (`const zinn=@import("zinn");`), obtain `b.dependency("zinn",.{})`, then pass that dependency. null is for Zinn's own build root. Returns generated LazyPaths and step pointers; null means the lazy board dependency is not ready in this build configuration. Invalid names/settings fail build compilation/panic or downstream validation; there is no runtime inference error return. Package manifests must include required files, including examples/mnist pipeline sources; the provided Zinn package paths do.

Required options: name (letters/digits/hyphen/underscore), model:LazyPath exporting Structure, dataset:.csv{training,evaluation,header=false} or .mnist{directory,fixture=false}. See [CSV tutorial](../tutorials/csv-classifier.md) for the tested full build script.

Host display: addProject Options.progress=.auto/.plain/.off. Root CLI adds -Dprogress=auto|plain|off, -Dquiet=true and -Ddownload-force=true. Cached training/export logs are separate from CSV/JSON and native firmware-build progress; see [progress integration](../progress.md).

| Option | Default / meaning |
|---|---|
| training | epochs20,batch32,rate.05,seed42,split_seed24301,validation_count=null,decay_every10,decay.3,limit60000 |
| format / evaluation | .int8 / .validation; evaluation=.final_test explicitly reads test |
| validation_count=null | CSV0 uses explicit evaluation CSV; MNIST5000 reserves from training |
| checkpoint | null means fit automatically; existing float checkpoint otherwise |
| build_file | null defaults to build.zig; set a LazyPath for a nonstandard script filename |
| calibration_limit / evaluation_limit | 1024 / 10000 |
| nearest | false; MNIST area resize default |
| target | .ch32v003 (only implemented board) |
| firmware / board_adapter | optional LazyPath overrides of production application/transport |
| flash_bytes / reserved_flash_bytes / ram_bytes / stack_bytes | 16384 / 64 / 2048 / 512; accounting limits, not linker/board reconfiguration |
| input_bin / sample_index / sequence / request | null /0 /1 /.infer; request=.info/.benchmark also available |
| step_prefix | empty; set distinct prefixes/names for multiple projects |
| objdump | llvm-objdump; optional stack-audit only |
| builtin_cnn,hidden,channels,features,classes | false,16,2,2,2; options passed to supplied model module; custom Structure is authoritative |

Steps: train, evaluate, e2e, deploy, flash, infer-host, simulate-uart, stack-audit (prefixed if configured). evaluate exports/classifies but does not run reference verification. e2e reuses the export and compares all integer logits; deploy reuses that verification and checks the final ELF budget. These paths share cached producers. flash explicitly invokes `chzig flash --no-build --bin <generated>` after deploy; never call it in host CI. LLVM/chzig/POSIX serial tools are optional, not mandatory build dependencies.

## Artifacts

Under the application's zig-out (root CLI or external package):

| Path | Content |
|---|---|
| training/NAME.zinn | Float checkpoint; explicit train installs it even with selected checkpoint override |
| models/NAME-int8 or int4.zig | Quantized inference source |
| firmware/NAME.elf and NAME.bin | Startup/HAL/application/model, and raw image |
| reports/NAME-training.csv | Training/validation curve, also installed by an implicit fit |
| reports/NAME-model.json | Evaluation split/count/correct, scales/format/schema/identity/preprocessing |
| reports/NAME-memory.json/.txt | Final load footprint, static RAM, stack allowance/margin |
| reports/NAME-training/evaluate/e2e/deploy-summary.json | Host-only saved presentation data, separate from model/checkpoint schemas |
| inputs/NAME-request.bin / NAME-expected.json | Host replay frame and all expected logits |
| reports/NAME-simulated-response.json/.bin | Host fake-board check, never hardware timing |

Artifacts struct exposes checkpoint/source/metadata/elf/bin LazyPaths and train/evaluate/deploy/flash/infer_host/stack_audit/simulate step pointers. Its additive e2e field is optional (default null for compatible struct construction), and is non-null in addProject's result. checkpoint points to the fitting output even when options.checkpoint selects another model for evaluation. Consumers with an existing checkpoint skip fitting; explicit train still produces its configured fit. Training and export are separate cached run artifacts: format/test selection does not refit floats. Source/configuration changes legitimately invalidate caches. Use different names to retain different reports.

For custom script names, set `.build_file=b.path("custom.build.zig")`. The [custom entry point](../../examples/project/custom.build.zig) demonstrates a standalone addProject application, including option inheritance. Script-exposed scalar/list CLI options, release mode, install prefix and local cache are forwarded to presenter child builds. Other parent scheduler/watch/web UI/diagnostic flags are not all forwarded. Programmatic map/LazyPath options retain the previous direct cached path.

## Root CLI

`zig build --help` is authoritative for all options. Root common `-Dproject=xor|mnist|csv` defaults to xor and consistently routes train/evaluate/e2e/deploy/flash. e2e without a project retains XOR compatibility; e2e with MNIST/CSV now selects that project. Dedicated mnist*, eval/quantize/xor/data-train commands remain explicit legacy paths. -Dtarget=ch32v003 is an accepted alias, and host tools remain native. For MNIST/CSV, -Dmodel selects a custom module and -Dapp-name selects artifact names. See the [CLI reference/migration](../cli.md).

| Group | Options |
|---|---|
| Input/configuration | -Ddata-dir, -Dmnist-fixture, -Dcsv-train, -Dcsv-test, -Dcsv-header, -Dfeatures, -Dclasses, -Dhidden |
| Model | -Dmnist-model=mlp/cnn, -Dmnist-hidden=16, -Dcnn-channels=2, -Dweight-format=int8/int4 |
| Training | -Dmnist-epochs (common20/dedicated10), -Dcsv-epochs=2000, -Dbatch-size=32, -Dlearning-rate=0.05, -Dseed=42 |
| Validation | -Dvalidation-count=5000, -Dsplit-seed=24301, -Ddecay-every=10, -Ddecay=0.3, -Devaluation-split=validation/test, -Dpreprocess=area/nearest |
| Limits/checkpoints | -Dtrain-limit=60000, -Dtest-limit=10000, -Dcalibration-limit=1024; canonical -Dproject-checkpoint works for all projects; -Dcheckpoint/-Dmnist-checkpoint remain compatibility aliases; -Drun-name is legacy MNIST |
| Presenter | -Dprogress=auto/plain/off, -Dquiet=true, -Dproject-build-file for custom root scripts |
| Memory | -Dflash-bytes=16384, -Dreserved-flash-bytes=64, -Dram-bytes=2048, -Dstack-bytes=512 |
| UART/check | -Dinput-bin, -Dsample-index=0, -Dsequence=1, -Drequest=infer/info/benchmark, -Dexpected-json, -Dresponse-bin |

Root common CSV currently uses explicit CSV evaluation and disables rate decay (validation_count0); use external addProject for a CSV training validation partition. Dedicated legacy commands/output paths are explained in [Getting Started](../getting-started.md) and historical notes; do not assume their XOR output paths match common projects. Standard optimize spelling is -Doptimize=safe in Zig0.17.0. docs-check is an offline link/API sample check.

## Lightweight model generation

`addModel(b:*std.Build, dependency:?*std.Build.Dependency, options:ModelOptions) ModelArtifacts`
creates only host fit/export/reference tools. It never requests a HAL, creates a
firmware, attaches Service or flashes. The actual return type is defined in
[model.zig](../../build_support/model.zig); fields/methods below are public.

ModelOptions shares the existing project fields: name/model/dataset, training,
format, evaluation, checkpoint, calibration_limit/evaluation_limit, preprocessing
and built-in shape settings, progress and build_file. Defaults match addProject.
Its optional step_prefix defaults to NAME- instead of the project default empty
prefix. Names must be nonempty and unique within the owning Build.

| Result | Purpose |
|---|---|
| source: LazyPath | Generated integer Zig source in native Build cache |
| checkpoint / selected_checkpoint: LazyPath | Configured fit output / actual consumer checkpoint |
| metadata: LazyPath | Existing model JSON report |
| format: Format | int8 or int4 |
| train / evaluate / generate / e2e: *Step | Explicit model-only workflow steps |
| createModule(b,target,optimize) *Module | Consumer-target generated module, using shared inference core |
| createModuleWithCore(b,core) *Module | Generated module using an existing zinn/inference source owner |

The graph's host_core/host_generated and backend fields support addProject; they
are not target modules to reuse in MCU firmware. Source LazyPaths automatically
carry tool/data/checkpoint dependencies into consumer compilation. generate runs
evaluation/calibration/export; it does not also run independent verification.
e2e performs that verification using the shared exported source.

Errors follow normal Build failure propagation: bad model structure/quantization
at compile time, malformed data/checkpoint or fitting/export errors at host Run
time. Numerical formats and captured stdout remain unchanged.

`addInferenceModule(b,dependency,target,optimize) *std.Build.Module` returns a
shared integer core for the consumer target. Use the same Module with
createModuleWithCore if the app imports the core too. The dependency also exports
zinn_infer as a native/default package module. Dependency builds default to
library-only=true; root checkout workflows retain their full configuration.

## Final ELF checks for caller-owned firmware

`addMemoryCheck(b,dependency,options:MemoryOptions) Check` accepts name and elf
LazyPath, flash_bytes=16384, ram_bytes=2048, reserved_flash_bytes=64,
stack_bytes=512, isr_bytes=0, flash_origin=0, ram_origin=0x20000000,
target_name="CH32V003" and progress=.auto. Origins/limits support ELF32 little
endian memory maps; the label alone does not establish board support.

Check exposes step:*Step, json/text:LazyPath and run:*Run (for shared preset
integration). Attach step to the caller's install/check graph. It inspects all
load segments of the **final application ELF** and fails on invalid placement,
Flash/RAM overflow, overlapping regions or arithmetic-invalid allowances.
The existing JSON stack allowance field combines stack_bytes+isr_bytes; neither
is measured. No firmware/runtime/objcopy/flash step is created by this function.

See [integration](../integration.md), [host tutorial](../tutorials/host-integration.md)
and [CH32 tutorial](../tutorials/ch32-integration.md) for complete executable builds.

## Externally produced models (including RL)

`addModel` accepts optional `Options.generated: ?Generated` without changing its
existing supervised path. The caller supplies `source`, `checkpoint`, `metadata`
LazyPaths and `generate`, `verify` Step pointers. This branch creates the named
train/evaluate/generate/e2e aliases without launching supervised tools. `model`
and `dataset` remain required descriptive inputs for source compatibility; the
caller owns actual calibration, evaluation and verification in this branch.

The returned `ModelArtifacts.createModule(b, target, optimize)` and `attach`
retain their existing behavior, compiling generated source for the consumer's
target. This does not introduce firmware ownership or a runtime model interpreter.
The [CartPole build](../../examples/rl-cartpole/build.zig) uses this path, followed
by the existing `addMemoryCheck` on the full CH32 ELF.

`ProgressBuild` also exposes the existing host Build progress helper module for
custom producers. Its `configure`/`operation` functions attach the existing
Journal/Receipt/presenter workflow. Model producers remain cached; the presenter
reports completed/cached status without rerunning training for display purposes.
The CartPole example demonstrates the required summary/receipt protocol. This is
an advanced host Build integration API; no host presenter enters target modules.
