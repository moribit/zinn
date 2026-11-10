# Add a generated model to a Zig application

The independent [host-app](../../examples/integration/host-app/build.zig) package
shows model generation without firmware or HAL ownership.

```sh
zig build --build-file examples/integration/host-app/build.zig sensor-train
zig build --build-file examples/integration/host-app/build.zig sensor-generate sensor-e2e run
```

The model definition and CSV files belong to that package. addModel produces a
cached source LazyPath; createModuleWithCore wires it to the caller's target.
The application owns workspace and validates all fixture outputs. There is no
UART protocol, service or custom event loop requirement.

Run the two-model package to use independently trained int4 and int8 models:

```sh
zig build --build-file examples/integration/multi-model/build.zig run sensor-generate other-generate sensor-e2e other-e2e
```

The two import names and workspaces are independent. The helper shares the
immutable inference Module while preserving separate generated sources and
metadata. See [integration](../integration.md) for full API usage, installed
artifact paths, input quantization and concurrency rules.
