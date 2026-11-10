# Quantization diagnostics

[Study implementation](../../../../examples/rl-cartpole/study.zig) regenerates per-state CSV for baseline/improved policies on both float/integer trajectories. Full CSV stays in Build outputs; committed aggregates retain counts, ranges and errors.

- `summary.csv`: agreement, clipping, ties, original-Q-margin MAE, float-transform disagreement.
- `bins.csv`: absolute Q-margin thresholds 0.001/0.01/0.05/0.2/1; absolute normalized angle/angular-velocity thresholds 0.1/0.3/0.7. Bins are indexed from zero.
- `layers.csv`: float range and propagated mean absolute error in each transformed layer's units. Equalization changes hidden units, so hidden MAE across profiles is not directly comparable.
- `input-ranges.csv`: normalized component min/max; input order x, x velocity, angle, angular velocity.

Input clipping fraction divides clips by 4×samples; layer clips count pre-ReLU upper saturation and lower saturation only for linear outputs. Negative ReLU values becoming zero are activation behavior, not quantization overflow. Final output clipping is intentional in the finer-scale sign policy. Exact reference equality verifies arithmetic, not control reward or float equality.
