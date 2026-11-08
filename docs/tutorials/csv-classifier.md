# Tutorial 2 — Custom CSV Classifier

Use Zig0.17.0. [examples/project](../../examples/project/build.zig) is an independent Zig package, not an import of the root build script's CLI. Its dependency manifest points to Zinn at `../..`. It is therefore self-contained as a package inside this checkout; when copying it elsewhere, change that path to your Zinn checkout or use a pinned Zig package URL/hash.

## Model and data

[model.zig](../../examples/project/model.zig) exports `pub const Structure`, a Definition with2 input features,8 ReLU hidden units and2 outputs. This same type drives fitting, calibration, source generation and host/reference verification.

CSV rows are `class_index,feature0,feature1`, for example:

```csv
0,0,0
1,0,1
1,1,0
0,1,1
```

Labels are zero-based; features must be finite f32 values. No quoted fields/embedded newlines. Set dataset.csv.header=true for one header row. Feature/class counts come from Structure. Define normalization once and use it for training/calibration/deployment; the CSV API does not normalize automatically.

## Build configuration

The complete, executable [build.zig](../../examples/project/build.zig) uses:

```zig
const dependency = b.dependency("zinn", .{});
_ = zinn.addProject(b, dependency, .{
    .name = "sensor",
    .model = b.path("model.zig"),
    .dataset = .{ .csv = .{
        .training = b.path("train.csv"),
        .evaluation = b.path("validation.csv"),
    } },
    .training = .{ .epochs = 2000, .validation_count = 0, .decay_every = 0 },
    .format = .int4,
    .target = .ch32v003,
});
```

This is a function-body excerpt, not a complete build file. The file imports `@import("zinn")` as its dependency build API. With validation_count0, evaluation uses the explicit second CSV (reported as test). A positive validation_count instead reserves part of training when evaluation=.validation. Separate tuning validation from final test in real applications. The bundled files repeat XOR: no held-out accuracy claim.

## Run the independent package

From the Zinn checkout:

```sh
zig build --build-file examples/project/build.zig train
zig build --build-file examples/project/build.zig evaluate
zig build --build-file examples/project/build.zig deploy
zig build --build-file examples/project/build.zig infer-host simulate-uart
```

Or `cd examples/project` and run the same steps without --build-file. Outputs are relative to that package's zig-out:

| Artifact | Path |
|---|---|
| Float checkpoint | training/sensor.zinn |
| Integer source | models/sensor-int4.zig |
| Firmware | firmware/sensor.elf and sensor.bin |
| Training/accuracy/capacity | reports/sensor-training.csv, sensor-model.json, sensor-memory.json/.txt |
| Reproducible input | inputs/sensor-request.bin and sensor-expected.json |
| Host transport check | reports/sensor-simulated-response.json/.bin |

deploy includes generated-core verification and ELF capacity checks, with no hardware write. simulate-uart uses a fake clock: its timing is not MCU performance. Unchanged fitting/export is cached. Keep a checkpoint's model, preprocessing and split configuration together; v1 alone does not contain that provenance.

For new data, edit Structure, CSV files and options; do not edit generated weight arrays. See [addProject/options](../api/build.md), [memory budgets](../api/budgets.md) and [UART](uart.md).
