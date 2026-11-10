# Add a model to an existing CH32 application

Follow [integration](../integration.md) for dependency and model setup. This
walkthrough builds without hardware; it never invokes a flash tool.

1. Open [the independent Build script](../../examples/integration/ch32-existing-app/build.zig).
   The application owns ch32.addFirmware, its main file and GPIO options.
2. Add the model to the runtime's app module using trained.createModule with
   ch32.ch32Target and .small. This preserves startup, linker and main-loop ownership.
3. In [main.zig](../../examples/integration/ch32-existing-app/main.zig), reserve
   static input/output/workspace and call Model.infer. The pseudo-sensor values
   are already quantized in exported sensor_input; the application/debugger may
   replace them. Volatile reads preserve runtime inference. GPIO reflects the
   integer classifier output.
4. Attach addMemoryCheck to the application's install step. The example reserves
   512B stack and 64B ISR allowance, in addition to the statically linked RAM.

```sh
zig build --build-file examples/integration/ch32-existing-app/build.zig sensor-generate sensor-e2e
zig build --build-file examples/integration/ch32-existing-app/build.zig
zig build --build-file examples/integration/ch32-existing-app/build.zig -Dled-pin=2
```

The last command changes only application GPIO configuration. Model generation
retains its native cache. reports/existing-app-memory.json reports complete ELF
capacity; sensor-model.json is model metadata, not firmware capacity.

```sh
zig build --build-file examples/integration/ch32-existing-app/build.zig -Dflash-bytes=1024
```

This intentionally fails the final ELF budget. It should not emit a success result.
The GPIO example is cross-compiled only; no physical sensor or LED behavior is
claimed. Hardware flashing belongs to the existing application's own workflow.
