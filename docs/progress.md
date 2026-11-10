# Host progress reporting

Zig0.17.0, standard library only. This is host tooling, not part of MCU inference. Existing inference APIs, numerical rules and checkpoint v1 are unchanged.

## Controls and output

```sh
zig build train -Dprogress=plain
zig build evaluate -Dquiet=true
zig build mnist-download -Dprogress=plain
zig build mnist-download -Ddownload-force=true
```

Root Build options: progress=auto|plain|off (default auto), quiet=true overrides it. External addProject accepts `.progress=.plain` or `.off`. Individual host CLIs accept --progress=auto|plain|off and --quiet; ZINN_PROGRESS supplies their default. Reports/errors remain enabled by quiet: it disables progress, not machine-readable results.

The standalone examples/project build exposes the same -Dprogress/-Dquiet options, using the Build module's additive ProgressMode enum. Other application builds can expose it explicitly or set Options.progress directly.

All Zinn rendering uses **stderr**. Existing stdout CSV/JSON/reports are preserved. In auto, recognized ANSI-capable TTYs use an ASCII progress bar on one updating line. Model/configuration and filename/file-count headers remain above it. Each redraw uses carriage return and ANSI erase-line; the actual terminal width is queried on every draw, leaving one column to prevent wrapping. Widths40/60/80/120 are covered by PTY tests. Narrow displays omit lower-priority metrics. No colours, raw input, hidden cursor or alternate screen are used. Unknown/dumb terminals, non-TTYs and CI use the existing plain logs, with no ANSI escapes; off disables Zinn progress.

Training bars show epoch/batch progress, latest loss, validation accuracy, best validation accuracy and ETA as space permits. `L` means training loss, `V` validation accuracy, `Best` the highest observed validation accuracy, `E` epoch and `B` batch. At40 columns, epoch/overall bar/loss take priority. Validation values persist between epochs; batches do not cause extra evaluation passes. Downloads show file counts in their header and byte progress, human-readable speed and ETA in the bar. Short files still receive a persistent100% completion line; reused files receive a cached summary, without simulated transfer progress. See [visual progress verification](visual-progress.md) for actual captures and limitations.

Ordinary redraws are capped at5Hz; lifecycle/epoch boundaries can force an update. Plain log updates remain at once per5 seconds, with epoch summaries at most twice per second and first/last epochs always shown. Saved logs retain their plain format even when the terminal is visual.

## Zig Build integration and caching

Zig0.17's cacheable Run steps pipe stderr into the build runner. Printing success progress there as ordinary diagnostics produces misleading command diagnostics. Zinn therefore captures training/export stderr into **reports/NAME-training-progress.log** and **NAME-export-progress.log**; legacy XOR has xor-training-progress.log/xor-export-progress.log. Legacy CSV has classifier-progress.log. Legacy MNIST uses its run-name/model prefix. Memory-stage text remains in NAME-memory.txt. A cached task reuses its prior log: it is not evidence of a new run.

Common train/evaluate/e2e/deploy operations and the legacy training aliases run a small host presenter. It invokes a named internal build step using the same compiler, local cache, install prefix and CLI project options. The actual fitting Run stays cacheable, with captured stdout/stderr. A separate, throttled journal is tailed to stderr while fitting runs; an additional build-only receipt distinguishes an executed fit from a cache hit. A cache hit prints `cached`, checkpoint and log paths without replaying stale epochs. The receipt does not modify checkpoints, source exports, CSV or JSON. Its session token is not a cache input. Unchanged commands demonstrably reuse the fitting Run. Same-project presenters are serialized by a file lock.

The numerical process writes live-TOKEN.log and its captured plain progress log. A separate internal events-TOKEN.jsonl carries throttled borrowed Event snapshots and model configuration to the presenter. The presenter retains validation/best values across batch updates, and owns all visual drawing. In visual mode, child-build diagnostics use a separate file relay so the active bar is finalized before errors are printed. These journal files live under the local cache; they are not checkpoint/export schemas or fitting cache inputs.

The presenter and downloader disable their Zig Progress IPC bridge; the child build is plain, avoiding two competing progress UIs. Common evaluation, reference verification and capacity checks use the same presenter and saved typed summaries. Implicit fitting remains cacheable; an explicit train afterwards reuses the same producer. Legacy diagnostic commands retain their captured logs/native Build behavior.

Compiler/firmware/objcopy stages use the native Zig build graph. `--summary all` shows success/failure/cached status. No fabricated compiler/write percentage is calculated. deploy never flashes. quiet disables Zinn rendering/IPC, not the parent Zig build system's own UI (`--color off`, summary options etc. are Zig controls). Changing display environment/options may invalidate a Run cache entry; unchanged settings reuse it.

The presenter adds a child build/cache lookup and a polling delay of up to100ms; it does not promise zero launch overhead. Build scripts named build.zig (including the standalone CSV example), CLI scalar/list options, release mode, custom prefix and local cache are supported. Other parent scheduler/watch/web UI/compiler diagnostic flags are not forwarded to the child; its scheduling is independent. Custom build-script filenames are supported through Options.build_file (root delegation: -Dproject-build-file). Runtime terminal capabilities are inherited instead of frozen into a configure-time environment. Display options are passed as CLI flags. Programmatic map/LazyPath options retain the previous direct cached training path with captured logs. Linux TTYs and physical hardware require separate testing.

## Events and measurement

Public host namespace: `zinn.host.progress` ([source](../src/host/progress.zig)). Observer holds a context pointer and optional synchronous callback. Event carries name, kind(started/updated/epoch/completed/failed), done, optional total, unit, borrowed named numeric metrics and detail. Do not retain slices or mutate training from a callback. A default Observer is disabled and needs no clock/renderer. `Observer.task(name,total)` supplies update/finish/fail lifecycle; finish completes known totals, failure retains partial counts and terminal transitions are idempotent.

`measure(event,start_ns,now_ns)` is pure: fraction, elapsed, average completed-units/sec and warmed-up ETA; unknown totals keep fraction/ETA unknown. Zero work is0% until completed, then100%; zero elapsed/work has no speed estimate. ETA requires at least one second, one percent, and min(32, max(2, total/100)) completed units. Short or unknown-total tasks have no ETA. The renderer smooths sampled rates using an exponential moving average (25% new / 75% previous). Percentages and bar cells both round down; completed known totals reach 100%. `Gate.allow` is pure interval gating. Renderer owns monotonic time, bounded ASCII formatting and best-effort stderr writes. Broken output disables further rendering rather than modifying/failing numerical training. It uses8 bounded task slots, no per-update allocation; more than8 interleaved names may evict old timing state. Use one Renderer per CLI process; its optional std.Progress bridge owns that process's global progress instance. Call deinit on normal unwinding.

Additive numerical hooks:

- fit.Options.observer/model_name: global batch counts plus epoch/batch/loss/lr metrics; epoch summaries provide validation accuracy/loss and best=1 when the in-memory best model changes. The file checkpoint is written by CLI after fitting, not after every best event. No additional forward pass, validation evaluation or RNG call is introduced. Mini-batch loss is the existing trainBatch result.
- Trainer.evaluateObserved(samples,loss_kind,observer); old evaluate/evaluateWithLoss remain disabled-observer wrappers.
- QuantizedFormat.calibrateObserved(model,samples,observer); old calibrate remains compatible. Evaluation/calibration/reference notifications are chunked, not per-sample terminal draws.
- CLI loading/export/budget phases report stage lifecycle when a meaningful total is unavailable.

## Download safety

Download requests stream64KiB chunks to a standard-library atomic temporary, bounded to32MiB compressed. The saved temporary is validated before replacement: gzip CRC/length/no trailing data, exact IDX dimensions/count (train60,000/test10,000, images28×28), and labels0..9, bounded64MiB decompression. Correct existing files are reused; invalid ones are diagnosed and redownloaded. --force / -Ddownload-force=true explicitly bypass reuse, but an old destination is still replaced only after a complete valid transfer. Known Content-Length gives bytes/percentage/ETA; missing length gives bytes/rate without invented totals.

Failures/cancellation never publish a partial canonical .gz file. Normal error unwinding cleans the temporary; abrupt SIGINT/process termination can leave an unreferenced random-name temporary, never treated as a completed dataset. Concurrent invocations have separate temporaries; no arbitrary stale-file deletion/resume is attempted. A valid replacement remains atomic on supported filesystems. The downloader also pins the four published compressed-file MD5 digests from [torchvision's MNIST resource list](https://github.com/pytorch/vision/blob/main/torchvision/datasets/mnist.py), checked2026-11-08. These are reference facts, not an executable dependency. This prevents reusing a different dataset with the same IDX dimensions/counts. MD5 is a legacy identity/integrity check, **not authentication or adversarial tamper protection**. Downloads use the [CVDF mirror](https://github.com/cvdfoundation/mnist).

## Verification and overhead

The current consistency checks and limitations are in [CLI consistency report](cli-consistency-report.md). Earlier counts and captures below are historical. The commands below remain current. The 43-test regression summary, raw-byte
download excerpt and paired overhead measurements later in this section describe
the initial `67206c4` implementation. See the [CLI quality report](progress-cli-report.md)
for the current 45-test suite, human-readable output and cache-hit checks.

```sh
zig build test
zig build test -Doptimize=safe
zig build progress-demo -Dprogress=plain
zig build progress-tools
./zig-out/bin/progress-demo --quiet
./zig-out/bin/progress-demo --progress=plain --fail
zig build progress-benchmark
bash tests/progress_cli.sh zig /tmp/zinn-progress-cli
bash tests/progress_pty.sh zig /tmp/zinn-progress-pty
```

The final failure example intentionally exits nonzero. --wait keeps the fixture running for manual Ctrl+C checks. No terminal mode/cursor changes need restoration; SIGINT need not execute Zig defers and may leave a partial line. No false success is promised after interruption.

Tests use an in-memory HTTP reader: Content-Length/unknown EOF/chunked bodies, truncated/disconnected bodies, gzip corruption, count mismatch, HTTP error, file reuse and old destination retention; no network required. Core tests cover unknown/zero totals, completion, interval gating, failure/off, human-readable download formatting at40/60/80 columns and checkpoint+CSV equality with/without observation. CI additionally checks actual fresh/cached training Runs, unchanged receipts on cache hits, identical checkpoints/CSV/stdout across modes, non-TTY auto output and failure exit status. See the [CLI quality verification](progress-cli-report.md) for this phase's actual before/after captures and platform limits.

Recorded regression checks:43 core tests in Debug/ReleaseSafe plus18 compile-fail cases; MLP/CNN×int8/int4 offline fixture deploy/evaluate/train with16/16 all-logit reference matches per configuration; existing XOR int8/int4 Golden/integration paths; standalone CSV project; documentation links/API samples. A CLI plain/quiet fit produced byte-identical checkpoint and curve CSV, with an empty quiet progress log. Final XOR production remains1508B Flash/16B static RAM; symbol inspection found no progress/renderer/download symbols in its ELF. No physical inference or actual network interruption was measured. Real cached MNIST files were reused after validation without a network transfer; additionally fresh and explicit-force four-file HTTPS downloads from CVDF into a temporary directory succeeded, including gzip/IDX/MD5 checks and atomic publication. Disconnect/error cases remain mocked in offline tests.

Example captured from the one-epoch synthetic fixture (not a digit-accuracy result; times/rates vary):

```text
epoch progress-sample training 100% 1/1 ... epoch=1 epochs=1 loss=2.32248 lr=0.05000 val_acc=0 val_loss=2.22746 best=1
completed progress-sample training 100% 1/1 ... selected_epoch=1 best_val_acc=0 best_val_loss=2.22746
```

Ellipses omit measured time/rate fields here. Complete original lines are in the generated reports/*-training-progress.log, separate from CSV/JSON.

Historical download excerpt from the initial implementation (superseded by the human-readable layout in the [CLI report](progress-cli-report.md); network rate is not inference performance):

```text
completed train-images-idx3-ubyte.gz 100% 9912422/9912422 elapsed=1.5s eta=0.0s rate=6473580.0B/s
completed MNIST files 100% 4/4 elapsed=3.6s eta=0.0s rate=1.1items/s
```

Host measurement2026-11-08, macOS arm64/Zig0.17.0/safe: synthetic256→16→10 model,512 samples,6 epochs,batch32,seed42, five paired trials with alternating order. Disabled median33.356ms (min32.556,max39.335), plain median33.341ms (min32.795,max38.372); [raw summary](experiments/progress-overhead.csv). Difference≈-0.05%, within run noise; **not a speedup or zero-cost guarantee**. All trial checkpoint bytes matched. The benchmark intentionally compares off/plain rendering regardless of outer Build display mode. Long jobs/slow terminals and IPC can differ; the limits above bound draw frequency. No new MNIST accuracy claim or physical timing was measured.
