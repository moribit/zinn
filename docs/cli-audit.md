# CLI audit and implementation plan

Baseline: 2fa87dd. Audit performed before the consistency changes.

## Findings

| Command | Baseline behavior | Intended common behavior |
|---|---|---|
| train | Dispatches XOR/MNIST/CSV | Keep dispatch and native fitting cache |
| evaluate | Dispatches; MNIST/CSV also verify integers | Evaluate/classify and save reports |
| e2e | Always XOR, ignoring project | Dispatch; verify every integer logit |
| deploy | Dispatches; checks ELF budgets | Keep, add saved-result summary |
| flash | Missing for XOR | Explicit selected-project write only |
| mnist / mnist-eval | Separate legacy MNIST graph | Retain as explicit MNIST legacy commands |

Integer reference verification currently starts timing before dataset loading and
calibration, then reports progress after sample 1. Its average rate charges all
setup time to one sample, generating a spurious multi-thousand-second ETA.
Rate/ETA have no warm-up thresholds. Percentage rounding and discrete bar cells
are computed independently. Completed unknown-length downloads need an explicit
done state without inventing a total.

Training already has a cache-preserving presenter, native cached Run, journal
and receipt. It retains plain logs and visual Event frames. However, its nested
build hardcodes build.zig, and receipt tokens are read at completion. An implicit
producer already running when a presenter starts can therefore consume the new
session marker. Unscoped live/event files can mix old/concurrent progress.

Evaluation/verification/memory tools have the authoritative data required for
summaries; the build should expose saved summaries instead of re-running work to
print it. Existing model JSON/checkpoints/CSV must not change schema.

## Design

1. Add project-dispatched e2e, separate evaluation from reference verification,
   retain XOR defaults and legacy commands. Share producer LazyPaths throughout
   the graph, so train/export/verification are not duplicated.
2. Start verification progress after setup; gate ETA by elapsed time, progress
   count and fraction. Use conservative estimates and consistent discrete bars.
3. Use an additive host-only summary sidecar and shared formatter for training,
   evaluation, verification and capacity checks. Preserve existing stdout files.
4. Reuse the existing presenter mechanism for cacheable operations. Scope journals
   to a launch token captured at producer startup. Never show previous elapsed
   measurements as the current cached execution. Check child status before
   reading or presenting saved successful summaries.
5. Add an explicit optional build_file Build API setting for nonstandard scripts;
   keep the existing default. Test scalar/list option forwarding and independent
   projects. Programmatic non-CLI options retain the compatible direct path.
6. Extend offline/PTY tests, compare numerical artifacts against the baseline,
   document command migration, and distinguish local macOS checks from pending
   Linux/remote CI/hardware verification.

The installed compiler version and supported build flags are checked locally.
Only the tested Zig 0.17 compiler is claimed; no untested 0.17 snapshots are
implicitly supported. No additional ML/runtime libraries will be introduced.

## Implemented decisions

The installed compiler reports exactly0.17.0. See [verification](cli-consistency-report.md)
for the resulting graph, display and test outcomes. Progress flags now use CLI
arguments rather than cloning configure-time environment maps, preserving runtime
TERM/CI detection even after a cached help/configuration invocation. Absolute and
relative supplied checkpoint paths use cwd-relative LazyPaths.
