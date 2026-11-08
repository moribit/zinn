# CLI progress quality verification

2026-11-08, macOS arm64, Zig 0.17.0. Baseline: commit `67206c4`.
These are host CLI checks, not hardware performance measurements.

## Before and after

The baseline invocation below produced **zero stderr bytes on both the first
successful fit and its unchanged cached invocation**:

```sh
zig build train -Dproject=mnist -Dmnist-fixture=true -Dmnist-epochs=2 -Dapp-name=ux-baseline -Dprogress=plain
```

The cause was twofold: cacheable Run steps captured stderr instead of forwarding
it live, and a cache hit did not launch the tool at all. The new presentation-only
launcher tails a separate journal while the child build runs the original cached
fitting step. A build-only receipt detects whether fitting actually executed.
Neither a timestamp nor the random receipt token is a fitting cache input.

An unchanged invocation now prints:

```text
training ux-baseline: checking build cache
cached ux-baseline
  checkpoint: /Users/mimoc/zinn/zig-out/training/ux-baseline.zinn
  log: /Users/mimoc/zinn/zig-out/reports/ux-baseline-training-progress.log
```

For actual MNIST, the following command trained on the official training split,
with the existing default validation partition and seed. It ran three epochs as a
display smoke test; it does not replace the representative accuracy benchmarks.

```sh
zig build train -Dproject=mnist -Ddata-dir=/tmp/zinn-progress-download-test -Dmnist-epochs=3 -Dapp-name=ux-real -Dprogress=plain
```

Actual excerpt (the time/rate fields are host-specific):

```text
training ux-real: checking build cache
started Dataset loading 0/? elapsed=0.0s eta=?
completed Dataset loading 0/? elapsed=0.5s eta=?
started ux-real training 0% 0/5157 elapsed=0.0s eta=?
epoch ux-real training 33% 1719/5157 elapsed=0.6s eta=1.2s rate=2978.7batches/s epoch=1 epochs=3 loss=0.34544 lr=0.05000 val_acc=89.32000 val_loss=0.37727 best=1
epoch ux-real training 67% 3438/5157 elapsed=1.2s eta=0.6s rate=2969.5batches/s epoch=2 epochs=3 loss=0.30100 lr=0.05000 val_acc=89.76000 val_loss=0.33971 best=1
epoch ux-real training 100% 5157/5157 elapsed=1.7s eta=0.0s rate=2977.0batches/s epoch=3 epochs=3 loss=0.26723 lr=0.05000 val_acc=90.66000 val_loss=0.30591 best=1
```

It finishes with `completed ux-real` and checkpoint/log paths; the unchanged next
invocation reports `cached ux-real`. The counters are cumulative mini-batches.
Long epochs also emit the existing `batch`/`batches` metrics at the normal update
interval. Epoch summaries are capped at two per second, always retaining the
first/last epoch, to avoid flooding tiny CSV jobs with thousands of instant epochs.

The baseline download emitted these lines for each of four files:

```text
started HTTP request 0/? elapsed=0.0s eta=?
completed HTTP request 0/? elapsed=0.6s eta=?
```

It also emitted raw speeds such as `rate=646633.6B/s`. A fresh HTTPS download with
the new formatter instead produced:

```text
MNIST: 4 files
download train-images-idx3-ubyte.gz
train-images-idx3-ubyte.gz 9.45/9.45MiB 100% 2.46MiB/s ETA 0s
download train-labels-idx1-ubyte.gz
train-labels-idx1-ubyte.gz 28.20/28.20KiB 100% 108.49KiB/s ETA 0s
```

At 40 columns (PTY resized with `stty columns 40`, rather than only setting
`COLUMNS`), an actual forced re-download in a macOS PTY produced:

```text
MNIST: 4 files
download train-images-idx3-ubyte.gz
train-images-idx3-ubyte.gz
9.45/9.45MiB 100% 3.18MiB/s ETA 0s
download train-labels-idx1-ubyte.gz
train-labels-idx1-ubyte.gz
28.20/28.20KiB 100% 101.53KiB/s ETA 0s
download t10k-images-idx3-ubyte.gz
t10k-images-idx3-ubyte.gz
1.57/1.57MiB 100% 879.20KiB/s ETA 0s
download t10k-labels-idx1-ubyte.gz
t10k-labels-idx1-ubyte.gz
4.44/4.44KiB 100% 17.05KiB/s ETA 0s
MNIST 4/4: 4 downloaded, 0 cached
```

Reused files are explicitly labelled `cached`, e.g.
`cached train-images-idx3-ubyte.gz 9.45MiB`; the final counts distinguish downloaded
and reused files. Validity checks, streaming and atomic replacement are unchanged.
Connecting to HTTP is part of the file's lifecycle, not a separate task.

An 80-column PTY also exercised actual carriage-return updates, for example
`train-images-idx3-ubyte.gz 4.16/9.45MiB 44% 3.95MiB/s ETA 1s`, followed by
the persistent completion line and aggregate summary. These PTYs were created
inside the output proxy using macOS `script`, so terminal detection reached an
actual terminal descriptor. A `COLUMNS`-only change is not sufficient to resize
a PTY; Build configuration may also retain its previously captured environment.

## Reproduction and evidence

```sh
zig build mnist-download -Ddata-dir=/tmp/zinn-download -Dprogress=plain
zig build mnist-download -Ddata-dir=/tmp/zinn-download -Dprogress=plain
zig build mnist-download -Ddata-dir=/tmp/zinn-download -Ddownload-force=true -Dprogress=auto
zig build mnist-download -Ddata-dir=/tmp/zinn-download -Dprogress=off
bash tests/progress_cli.sh zig /tmp/zinn-progress-cli
zig build test
zig build test -Doptimize=safe
zig build docs-check
zig build --build-file examples/project/build.zig train evaluate deploy infer-host simulate-uart
zig build firmware firmware-trained firmware-production deploy e2e -Dprogress=off
zig build size -Dprogress=off
```

- Fresh download, validated reuse and explicit-force download: actual four-file
  HTTPS transfers/reuse on macOS, including a 40-column PTY. Off mode emitted no
  Zinn progress. No network is needed by the CI test suite.
- The offline CLI integration checks actual fresh and cached fits, receipt reuse,
  plain, non-TTY auto with `CI=true TERM=dumb LC_ALL=C`, off, and failed training.
  It compares checkpoint, CSV and stdout bytes, and rejects ANSI escapes/stale
  epoch replay/false cached success. GitHub Actions runs it on Linux and macOS;
  remote Actions execution and a real Linux terminal are not claimed here.
- The pre-change two-epoch fixture checkpoint and CSV were retained outside the
  repository and compared byte-for-byte with the new fit: identical. The normal
  saved stderr progress log remains available. No checkpoint/CSV/JSON schema,
  inference arithmetic or model API changed.
- Download formatter tests cover 40/60/80 columns, known/unknown total, human
  units, reuse and aggregate summaries. Existing mock HTTP tests cover truncated,
  disconnected, chunked, invalid gzip/IDX/digest and atomic replacement behavior.
- The external CSV project completed training, evaluation, all-logit reference
  verification, CH32V003 deployment generation and simulated UART exchange.
- Debug/ReleaseSafe each passed **45 unit tests and 18 compile-fail cases**.
  Documentation verification passed **239 local links**, three mirrored code
  fences and its executable API examples. MLP/CNN × int8/int4 each passed
  **16/16 all-logit reference comparisons** and CH32V003 cross-build/budget checks.
- A warm cached fixture invocation measured **0.31s wall time** with
  `/usr/bin/time -p` on this host (single observation, including the outer build
  and presenter; not a paired performance comparison). The original fit's
  checkpoint and curve remained byte-identical.
- XOR production remained **1508B Flash / 16B static RAM**, diagnostic **4188B /
  24B**, and hand-authored XOR **3148B / 12B**. The **512B stack allowance is a
  budget, not a measurement**. No physical inference, cycles or stack high-water
  were measured.

The synthetic fixture's diagnostic firmware budgets were also checked (these
are not trained MNIST accuracy benchmarks):

| Fixture | Flash | Static RAM | Stack allowance |
|---|---:|---:|---:|
| MLP int8 | 7980B | 288B | 512B |
| MLP int4 | 5880B | 288B | 512B |
| CNN int8 | 5012B | 760B | 512B |
| CNN int4 | 4568B | 760B | 512B |

## Remaining limits

The presenter adds a native child-build cache lookup and up to 100ms polling
latency; model training remains cached. It supports conventional `build.zig`
scripts and CLI scalar/list project options, compiler release mode, install
prefix and local cache. It does not forward parent scheduling/watch/web UI or all
compiler diagnostic flags. Programmatic map/LazyPath options fall back to the
previous cached training path and captured logs; custom script filenames need
further integration. Other export/evaluation steps still rely on
captured logs/native Build status rather than this live plain relay. Switching
display mode/environment may invalidate an existing Run cache entry, as before.

Training log lines can wrap, preserving all metrics. Download layout tests target
40 columns and above; at extremely narrow widths even the minimal byte counter
may wrap. Unknown total/zero elapsed keep ETA/rate unknown. TTY download refresh
is at most 5Hz; plain updates are at most every five seconds plus lifecycle
events. No guessed compiler percentage is shown. Actual Linux TTY rendering,
abrupt interruption of a child build, slow terminal overhead and hardware remain
separate validation work.
