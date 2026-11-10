# Integration audit

Baseline: 1d24f44; Zig 0.17.0. Audit precedes the implementation below.

The inference closure is model.zig, cnn.zig, spatial.zig, packed.zig,
quant.zig, tensor.zig, workspace.zig, kernels/dense.zig and the comptime
budget checks in budget.zig. No HAL, CSV, HTTP or allocator is needed for infer.
root.zig also exports Trainer/fit/data/export/host and optional Service/protocol.
Zig laziness already removes unused host declarations from firmware; an inference
entry point makes the source boundary explicit rather than claiming a size win.

Definition/ImageDefinition describe shape; Trainer and export share that shape.
Host training needs std, train/data/fit/export and host progress. The generated
source imports zinn and exposes Model, scales, model ID and verification vectors.
Scale floats are metadata/comptime checks, not runtime floating point operations.
Service and the CH32 UART adapter belong to the full application layer.

addProject currently interleaves cached host fit/export/verify with addFirmware,
UART framing, stack tooling and final ELF checks. Extract the existing host graph
without changing its tools, numerical options or installed paths. LazyPath is a
source artifact; a consumer-target Module must be constructed separately.

ch32fun_zig 0.1.0 is the vendored MIT snapshot d6524ff375684e127b0d4ae68c0e47b0a8c7823b.
Its addFirmware returns Step.Compile; application imports go on its child app
module, not the runtime root. ch32Target selects the RV32E target, and the HAL
owns startup/linker scripts. No upstream modification is needed.

The package exports a full zinn module but no inference-only module. Its lazy HAL
dependency is only needed when the firmware graph is instantiated. External
packages import the build API through @import("zinn") in build.zig and create a
normal b.dependency for source paths. Host-only integration must not resolve HAL.

Multiple models currently collide on default public train/evaluate/e2e steps.
The extracted API defaults to NAME- step prefixes, requires distinct nonempty
model names, and returns source/checkpoint/metadata plus consumer module creation.
Callers can explicitly share step prefixes only when they avoid duplicate steps.
Journal paths already include model name/operation; native Runs cache file inputs.
A supplied checkpoint avoids fitting for consumers. Generated sources are never
manually copied or edited. addProject retains its existing options and step names.

Final ELF accounting must include the caller application and statics, independent
of model parameter estimates. Reuse size.zig/budget.zig with configurable memory
limits and stack plus ISR allowance; these are budgets, not high-water measures.

## Implementation decisions

The shared graph lives in build_support/model.zig; addProject delegates to it.
The package now returns after library exports when used as a dependency by default,
avoiding its example HAL graph. library-only=false restores complete configuration.
Inference modules share a stable cache key from package path, target triple/CPU,
feature set and optimization. An explicit existing core can be passed instead:
Zig rejects duplicate source ownership even if only one copy's functions are used.
This is a compiler integration constraint, not a numerical/runtime limitation.
The source closure is explicit in src/infer.zig; old root exports still work.
Final ELF checking is shared through build_support/memory.zig, with origins/limits
and separate stack/ISR input allowances. No ch32fun_zig source changed.
