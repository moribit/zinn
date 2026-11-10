# CLI reference

Tested with Zig0.17.0 (`zig version`). Host tools stay native on macOS/Linux;
the implemented firmware preset is CH32V003. Other0.17 snapshots are not claimed
without running the checks. No additional libraries are required.

## Common workflow

`-Dproject=xor|mnist|csv` applies to all five common commands; default is xor.

| Command | Work and saved result |
|---|---|
| train | Fit floats, select best validation checkpoint where available, save checkpoint/curve |
| evaluate | Float/integer classification evaluation, quantization/export and evaluation report |
| e2e | Compare every integer output logit with the independent integer reference |
| deploy | Reuse export/reference checks, emit ELF/BIN, inspect final memory budgets |
| flash | Explicit physical write after successful deploy; requires chzig/device |

Without a selected checkpoint, consumers can fit once through the shared cached
producer. With `-Dproject-checkpoint=path.zinn`, evaluate/e2e/deploy use that file
and do not fit. Explicit train always trains its configured structure; the
checkpoint override is for consumers. Source/definition/preprocessing/calibration
and split settings must match the checkpoint. Checkpoint v1 is unchanged.

```sh
zig build train
zig build evaluate
zig build e2e
zig build deploy
zig build e2e -Dproject=mnist -Dmnist-fixture=true -Dmnist-epochs=2
zig build e2e -Dproject=csv -Dcsv-train=examples/data_classifier/train.csv -Dcsv-test=examples/data_classifier/test.csv
```

The first four commands are the small XOR demo; the MNIST example is synthetic,
not a digit-accuracy benchmark. `flash` is deliberately absent from host examples
and CI. deploy does not write hardware. See [MNIST](tutorials/mnist.md),
[CSV](tutorials/csv-classifier.md) and [Build options](api/build.md).

XOR retains its fixed seed42/10,000-epoch truth-table demonstration. MNIST/CSV
training flags are model-specific. Unknown project values are errors. A wrong
checkpoint/structure, missing data or failed capacity check fails the build;
it is never treated as cached success or routed to an unrelated project.

## Results and terminology

Human summaries/progress go to stderr. Existing CSV, generated model JSON and
source formats remain unchanged. Additional `reports/NAME-OP-summary.json`
sidecars store presentation data; OP is training/evaluate/e2e/deploy. They are
separate from `NAME-model.json` and checkpoint schemas.

- Train: structure, selected best epoch/validation accuracy when a validation
  split exists, final epoch training loss, measured fitting time for a newly
  executed fit, checkpoint/log paths. Final loss comes from the existing final
  curve row, without evaluating the model again. XOR/CSV without a validation
  partition report validation as n/a.
- Evaluate: dataset/split/source path, count, float and quantized classification
  accuracy, float MSE and quantization format, evaluation report path. Training
  curve loss is cross-entropy; evaluation MSE is explicitly labelled.
- E2E: PASS/FAIL, samples, samples whose **entire logit vector** matched,
  mismatches, parameter bytes and workspace bytes. Exact reference agreement is
  **not classification accuracy**. Failure stops at the first mismatch; no
  successful summary is installed/read for a failing child.
- Deploy: actual target, Flash/usable limit, static SRAM, stack **allowance**,
  RAM margin, installed ELF/BIN paths, and an explicit not-flashed statement.
  Stack allowance is not stack high-water or a measurement.
- Download: completed file count, newly downloaded and validated/reused counts.
  File cache reuse does not invent transfer speed or a new network measurement.

Completed means the operation's native producer executed for this launch. Cached
means its saved producer result was reused; no old elapsed time or old progress
is replayed as a new run. Upstream producers may run for another requested
operation: for example deploy can perform verification first, then a subsequent
e2e correctly reports cached. Summaries describe successful artifacts; their
stored elapsed_ns is the original producer measurement, not a cache-hit timing.

## Display and ETA

`-Dprogress=auto|plain|off` defaults to auto. Auto detects the current stderr TTY,
TERM capability and CI environment at runtime, not from an earlier cached build
configuration. Plain keeps line logs; off and `-Dquiet=true` suppress Zinn's
console progress/summaries while still generating results. Errors remain enabled.
Direct CLIs also accept --progress/--quiet and the ZINN_PROGRESS default.

ETA requires at least1 second, at least1% progress, and2..32 completed units
(adapted to the total). It uses an exponential rate average after warm-up.
Short/unknown-total tasks omit ETA rather than showing a speculative number.
Integer verification starts its clock **after** loading/splitting/calibration.
No production sleep or extra inference is used to stabilize the display.

Percentages round down; bar cells use the same fractional progress and floor
rule. 1/5000 is0% with an empty known-total bar;4999/5000 is99%, not100%.
Completion is100% for a known total; unknown totals keep an explicit done state
without an invented percentage. Failure prints failed, not a100% success bar.
See [progress details](progress.md) and [verification record](cli-consistency-report.md).

## Cache, concurrency and custom builds

The presenter is always-run display code; the fitting/export/verification/size
producers remain normal cached Run steps. It reads sidecars after child success.
Private operation names are not inherited by producers or added to their cache
keys. Display settings are forwarded as CLI flags, retaining runtime environment
inheritance. Changing source/data/options legitimately invalidates work.

Journal filenames contain a launch token captured when the producer starts.
Receipt uses that same snapshot even if another process replaces the session
marker. Old/unmonitored journals are not read as a current launch. A lock
serializes presenters of the same model/operation; normal completion removes
only that launch's temporary journals. Captured canonical logs remain available.
Interruptions/failures cannot display a prior PASS summary as current success.

An independent addProject application gets the same train/evaluate/e2e/deploy/
flash steps (with its configured prefix). For a nonstandard filename set
`Options.build_file=b.path("custom.build.zig")`; see the executable
[custom entry point](../examples/project/custom.build.zig). Root custom scripts
that delegate to Zinn's build function can use `-Dproject-build-file=filename`.
Only options exposed by the owning build script are accepted/forwarded.

Scalar/list CLI options, release mode, install prefix and local cache are
forwarded. Parent scheduler/watch/web UI/diagnostic flags are not all forwarded.
Programmatic map/LazyPath options keep the compatible direct cached path with
captured logs. Independent processes/projects sharing one TTY are not protected
by a global cross-process terminal lock. No physical benchmark is implied.

## Legacy commands and migration

| Command | Meaning |
|---|---|
| e2e without project | XOR as before |
| e2e -Dproject=mnist/csv | **Now the selected project**, previously incorrectly XOR |
| xor-e2e / xor-train / xor-evaluate | Explicit XOR workflow |
| eval / quantize / xor | Legacy XOR evaluation/export/hand-authored Golden checks |
| mnist / mnist-train / mnist-eval / mnist-firmware | Explicit legacy MNIST graph/paths; not selected by project |
| data-train | Legacy standalone CSV tool |
| size / firmware* | Legacy firmware budget/build collection |

`-Dcheckpoint` remains a legacy checkpoint alias; `-Dproject-checkpoint` takes
precedence and works for all projects. `-Dmnist-checkpoint` is retained for the
legacy MNIST path (and common MNIST/CSV compatibility fallback). Prefer the
canonical project-checkpoint flag in new workflows. Console text is clearer and
may differ; use existing machine reports or the new summary sidecars for tooling.
