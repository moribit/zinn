# CLI consistency verification

## Scope and compatibility

Baseline: `2fa87dd`. Verified locally on macOS arm64 with Zig **0.17.0**.
No inference kernels, checkpoint v1 fields, public numerical APIs or model JSON
schema were changed. The new host-only summary sidecars are separate artifacts.
No hardware was flashed or benchmarked. Linux/GitHub Actions checks are configured;
their remote result must be checked independently after publication.

## Command audit and changes

See [audit](cli-audit.md) and [CLI reference](cli.md). Previously `e2e
-Dproject=mnist` ran XOR, while MNIST/CSV evaluation also verified integer logits.
Now train/evaluate/e2e/deploy/flash consistently select xor, mnist or csv.
Default e2e remains XOR; explicit legacy MNIST commands remain available.
Evaluation reports classification accuracy; E2E verifies every integer logit.
A supplied project-checkpoint skips fitting for consuming commands.

Changed implementation areas:

- build.zig, build_support/project.zig and build_support/progress.zig: dispatch,
  shared cached producers, custom build-file forwarding and operation presenters.
- src/host/progress.zig, progress_format.zig, training_display.zig and new
  summary.zig: conservative ETA, consistent bars and typed result formatting.
- tools/train_watch.zig: isolated journals, startup receipt tokens, successful
  child validation and cached summaries; tools/size.zig: saved deployment metadata.
- examples/mnist/{pipeline,verify}.zig and examples/xor/{pipeline,verify_trained}.zig:
  authoritative summary data without additional training/evaluation for display.
- examples/project/build.zig and custom.build.zig: independent custom entry point.
- tests/progress_cli.sh, progress_pty.sh, new cli_consistency.sh and CI: cache,
  dispatch, sessions, artifacts, errors, TTY widths and custom options.
- README/README_ja, Getting Started, API Build reference, tutorials and progress
  documents: consistent roles, migration and measurement limitations.

## Actual display and ETA

The reported problematic baseline was:

```text
updated Integer reference verification
0% 1/5000 elapsed=0.5s eta=2586.9s
```

Verification now starts after dataset loading/calibration. A local real MNIST
5,000-sample run using the existing ux-real checkpoint printed:

```text
started Integer reference verification 0% 0/5000 elapsed=0.0s
completed Integer reference verification 100% 5000/5000 elapsed=0.0s rate=240764.2items/s
completed real-verify-consistency
Operation: e2e
Result: PASS
Samples: 5000
Samples with all logits matched: 5000
Mismatches: 0
Parameters: 4360 B
Workspace: 16 B
Note: Exact reference matching is not classification accuracy.
```

This is host verification, not MCU performance or a new classification accuracy.
The elapsed display has one decimal precision. No speculative ETA was emitted.
ETA requires one second, one percent and an adaptive minimum of 2..32 units.
Rates are exponentially smoothed. Known-total bars and percentages round down;
1/5000 is an empty0% bar, full completion is100%. Unknown totals stay unknown.

Real PTY captures use ASCII bars (representative training frame):

```text
E1/2 B1/1 [##########----------] 50% L2.322 V0.0% Best0.0%
E2/2 B1/1 [####################] 100% L2.297 V0.0% Best0.0%
```

A repeated command prints cached plus saved metrics/artifact paths, without
replaying epochs or claiming a new Training elapsed value. Plain/off/quiet keep
stdout machine data separate from stderr. Failed children never read an old PASS
sidecar. No artificial wait was added to numerical tasks.

## Verification record

Passed locally: 51 core numerical/progress tests in Debug and ReleaseSafe, 2 compiled documentation API tests, 262 resolved local links and 18 expected
compile failures, documentation links/API samples, XOR/MNIST/CSV int8/int4 E2E,
explicit checkpoint reuse, and custom external Build options. Synthetic MNIST
fixtures are correctness checks, not digit-accuracy measurements.

The CLI suites additionally exercise cached/uncached operations, stale journal
and receipt files, same-model concurrent builds, seed invalidation, quiet output,
failed children and replacement of the session marker during active training.
The producer retains its original startup token. Per-launch journal names avoid
mixing another launch or unmonitored producer into the current display.

PTY tests cover40/60/80/120 columns, resize, SIGINT, failure, cached training,
plain/off/dumb terminals and runtime TTY detection after CI/dumb configuration.
Download tests use offline fixtures; no new public-network test is claimed here.
CI runs the suites on Linux and macOS and uploads logs/reports.

Checkpoint, training CSV and generated Zig source for the same seed42/two-epoch
MNIST fixture compare byte-for-byte with the baseline. The mode comparison suite
also compares model JSON, checkpoint, CSV, source and integer verification across
auto/plain/off. These checks preserve reproducibility rather than retraining a
model merely to print a summary.

## Capacity and remaining limits

CH32V003 XOR production remains1508B Flash /16B static SRAM. Its512B stack
allowance is a budget, not a measured maximum. A two-channel synthetic CNN int4
production build uses4936B Flash /916B static SRAM,512B stack allowance and620B
RAM margin. Target limit includes the existing64B reserved Flash region.
These are cross-built ELF measurements, not physical execution measurements.
CLI code remains host-only. No new MNIST accuracy result is claimed.

The presenter performs a child-build cache lookup and polls at up to100ms;
startup cost is distinct from measured training time. Different operations may
serialize their shared native producers through Zig cache locks. Separate
projects sharing one terminal have no global terminal lock. Parent watch/web UI
and all scheduler flags are not forwarded. Programmatic map/LazyPath options
retain the compatible captured-log path. Abrupt termination may leave temporary
journal files; launch isolation prevents replay. SIGINT can leave a partial line.
Remote CI, Linux terminal behavior and physical UART/cycles/stack high-water
remain subject to their own execution results; local macOS PTY checks do not
establish those results.

## Reproduction

```sh
zig build test docs-check --summary all
zig build test -Doptimize=safe --summary all
bash tests/progress_cli.sh zig /tmp/zinn-progress-check
bash tests/cli_consistency.sh zig /tmp/zinn-cli-check
bash tests/progress_pty.sh zig /tmp/zinn-pty-check
zig build deploy -Dprogress=plain
```

Each script saves raw stdout/stderr, summary sidecars and comparison artifacts
in its specified output directory. cli_consistency uses offline fixtures and
checks6 project/format combinations. The real5,000-sample run above used
`e2e -Dproject=mnist -Ddata-dir=/tmp/zinn-progress-download-test
-Dproject-checkpoint=zig-out/training/ux-real.zinn
-Dapp-name=real-verify-consistency -Dprogress=plain`; those local data and
checkpoint paths must be replaced with equivalent prepared artifacts elsewhere.

UART production cross-builds (synthetic fixture, one epoch, test split):

| Model | Format | Flash B | Static SRAM B | Stack allowance B | RAM margin B |
|---|---|---:|---:|---:|---:|
| MLP16 | int8 | 8084 | 444 | 512 | 1092 |
| MLP16 | int4 | 5984 | 444 | 512 | 1092 |
| CNN2 | int8 | 5380 | 916 | 512 | 620 |
| CNN2 | int4 | 4936 | 916 | 512 | 620 |

These UART builds include the board/protocol runtime; the smaller XOR production
build uses a different application. Firmware sizes are not directly comparable
as kernel-only benchmarks. Legacy diagnostic verification checks 16/16 complete
logit vectors for each of the four configurations.
