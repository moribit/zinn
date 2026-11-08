# Experiment evidence

MNIST records below date from2026-11-07; these are preserved data artifacts, not automatic measurements of the current build.

- validation/: eight fixed-study learning curves, including separate seed43 repeat. Configuration and selection are in [validation-plan](../validation-plan.md).
- final/: model/accuracy manifests and corresponding UART firmware ELF memory accounting for frozen MLP32/CNN4×int8/int4. See [benchmarks](../benchmarks.md) for interpretation.
- [progress-overhead.csv](progress-overhead.csv):2026-11-08 synthetic host paired-fit overhead summary; [conditions and limitations](../progress.md#verification-and-overhead).

The Japanese [practicality report](../practicality-report.md) is the full dated analysis. No response/cycle values here attest hardware execution. Re-run the fixed script only when intentionally doing a training study; offline CI uses synthetic fixtures instead.
