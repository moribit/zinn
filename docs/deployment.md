# Unified project workflow

Use Zig **0.17.0**. The root build defaults to the compatible XOR commands. Select an application explicitly:

```sh
zig build mnist-download
zig build train -Dproject=mnist -Dapp-name=digits -Dmnist-hidden=32 -Dlearning-rate=0.1
zig build evaluate -Dproject=mnist -Dapp-name=digits -Dmnist-hidden=32 -Dlearning-rate=0.1
zig build deploy -Dproject=mnist -Dapp-name=digits -Dmnist-hidden=32 -Dlearning-rate=0.1 -Dtarget=ch32v003
```

Keep the same configuration on each command. Build run-step caching reuses unchanged fitting/export operations. Fitting has separate compile options from export: changing int8/int4 or validation/test does not retrain the float model. An existing checkpoint can be selected with `-Dproject-checkpoint=...`; its preprocessing/split sidecar must match. Checkpoint v1 remains unchanged and does not itself encode preprocessing provenance.

Default evaluation uses 5,000 validation samples separated from official training, never the official test files. Use `-Devaluation-split=test` only after freezing the configuration. `-Dpreprocess=nearest` is available for controlled comparison; default is area28to16_div255. Calibration only uses the training partition. Common training defaults to20 epochs; legacy `mnist-train` defaults to10.

Outputs: `training/<app>.zinn`, `models/<app>-int8|int4.zig`, `firmware/<app>.elf/.bin`, `reports/<app>-training.csv`, `reports/<app>-model.json`, `reports/<app>-memory.json/.txt`, under `zig-out`. JSON records split, accuracy, input scale bits, encoding, layout, model identity and memory allowances. Give distinct app names to configurations whose reports you want to retain. `deploy` requires independent all-logit verification and final ELF memory checks; it never writes hardware. `flash` is explicit and requires optional chzig/WCH hardware.

## Application-owned model

[examples/project](../examples/project/build.zig) is a complete external package using Zinn as a path dependency. Its `model.zig` exports `pub const Structure = zinn.Definition(...)`; ImageDefinition works through the same training/export path.

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

The build script imports `const zinn = @import("zinn");` as in the complete example. Run `zig build --build-file examples/project/build.zig train evaluate deploy infer-host simulate-uart`. For CSV, the supplied Structure determines feature/class counts. With validation_count0, the explicit evaluation CSV is used (and reported as test); do not repeatedly tune on a final test CSV. A positive count reserves a deterministic validation partition from training instead. Dataset files are host-only.

`addProject` also accepts training settings, checkpoint, calibration/evaluation limits, firmware and board_adapter LazyPaths, memory allowances, input_bin, request, sequence and optional step_prefix. Multiple projects need distinct names/prefixes. Model arrays and quantization coefficients are generated. Low-level Dense/Sequential/Workspace/infer contracts remain available unchanged.

## UART production interface

The default adapter uses CH32V003 PD5 TX/PD6 RX, 115200 8N1, common GND and compatible3.3V UART levels. Cross TX/RX. This mapping and register configuration require hardware validation; see the [WCH peripheral source](https://github.com/openwch/ch32v003/tree/main/EVT/EXAM/SRC/Peripheral/src). No SWIO terminal is needed. The application adapter supplies init/read/write/now/highWater/clock_hz at comptime; no runtime graph or heap is introduced. The legacy `mnist-firmware` remains a separate SWIO diagnostic containing a sample image.

```sh
zig build infer-host -Dproject=mnist -Dapp-name=digits -Dmnist-hidden=32 -Dlearning-rate=0.1 -Drequest=benchmark
# Optional: add -Dinput-bin=input.i8 (exactly256 already-quantized bytes).
zig build simulate-uart -Dproject=mnist -Dapp-name=digits -Dmnist-hidden=32 -Dlearning-rate=0.1 -Drequest=benchmark
# Only after explicitly flashing the matching ELF/bin:
sh tools/uart-exchange.sh /dev/ttyUSB0 zig-out/inputs/digits-request.bin response.bin
zig build check-response -Dexpected-json=zig-out/inputs/digits-expected.json -Dresponse-bin=response.bin
```

Use identical options/checkpoint/format when generating firmware and requests. The checker validates model id, sequence, opcode, CRC, class and every logit. A response file is not proof of physical execution; simulation is labeled separately. The optional POSIX shell exchange utility uses stty/dd, not a mandatory serial library. Request/response is stop-and-wait; allow the response to finish before transmitting another request.

MNIST input is HWC16×16×1, area-resized from28×28 and divided by255 (or the explicitly selected nearest variant), quantized with generated input_scale/zero_point0 and the existing rounding/saturation contract. Wire bytes are signed i8 two's-complement. Host request generation applies the generated model encoding; raw input_bin is already quantized. Source/manifest contain input/output scale; all scales must match the generating checkpoint/preprocessing.

## Wire format v1

All multibyte integers are little-endian. Header12B: magic `ZI`, version1, opcode1 infer/2 info/3 benchmark, sequence u16, model id u32, payload length u16. Request payload is exactly input_len bytes (256 for MNIST), or empty for info. Only info accepts model id0 discovery. CRC16-CCITT-FALSE (poly1021, initFFFF) covers header+payload, followed by2B CRC. Model id fingerprints quantized structure/parameters; it is an identity guard, not authentication.

Response opcode is request|80hex; fixed metrics44B followed by signed i8 logits. Metrics offsets: status0/class1/iterations2(u16)/clock_hz4/overhead8/min12/median16/max20/stack_high_water24(u16)/workspace26(u16)/adapter_init28/transfer32/preprocess36/logit_count40(u16)/input_len42(u16). Remaining metrics are u32 ticks. Statuses0..7: ok, bad_version, bad_opcode, bad_length, wrong_model, bad_crc, timeout, uart_error. Invalid or partial frames never infer. Fixed buffers, length checks, idle50ms and total250ms deadlines prevent unbounded reception. Polling UART hardware overruns reset the frame and return an error; no IRQ receive buffer is hidden.

Production infer performs no timing reads around the kernel. Benchmark runs one warmup plus9 inferences, subtracts the minimum of9 timer-read overhead samples (saturating), then reports min/median/max. SysTick runs at CPU frequency; wrapping intervals must be less than one32-bit timer period. Input transfer, adapter init and preprocessing (zero: input is already quantized) are separate fields. Model is const Flash data with no model initialization step. Benchmark includes int64 requantization and int4 decoding; real CPU cost remains unmeasured.

The stack paint starts after board initialization, protects64B below current SP and reports conservative since-ready high-water including that protected setup area. FFFF means unavailable. It does not measure startup peak. Default512B is a budget, never a measurement. Optional `stack-audit -Dobjdump=/path/to/llvm-objdump` computes a normal direct-call static bound and fails on reachable recursion/indirect/dynamic SP. It excludes interrupts and is not a general proof for arbitrary inline assembly or stack-changing loops. LLVM is optional, not a build dependency. GPIO/interrupt/peripheral additions must revisit the remaining RAM and stack assumptions.
