# CartPole quality experiment protocol

Baseline: d82c434. Old published JSON/CSV files remain unchanged.
Training seeds: 42, 43, 44 (regression), 45, 46 (additional).
Physics, 500-step limit, +1 reward, epsilon=0 evaluation, normalized inputs and
LEFT-on-tie semantics remain fixed. All training environment seeds have bit31=0.

Seed partitions fixed before running candidate comparisons:

- Original policy development/selection: 0x80000000 + [0,49].
- New candidate comparison: 0x90000000 + [0,49].
- Greedy calibration: 0xa0000000 + [0,49].
- New final test: **0xe1000000 + [0,49]**. Do not execute until export choices freeze.
- Old published test: 0xc0000000 + [0,49], regression only; never selection.

Compare the same saved float checkpoint under baseline replay+anchor calibration,
representative bounded states, greedy rollout and hybrid calibration; compare
centered two-output versus right-minus-left one-output export. Candidate choice
uses only new development rewards/agreement, preferring a single strategy across
training seeds over seed-specific tuning. Final test results are not fed back into
selection. Additional learning changes are separate experiments, not silent model
replacements. PTQ comes first; QAT only if a small compatible implementation is justified.

Keep aggregate JSON/CSV in Git. Detailed per-state diagnostic CSV can be regenerated
and is installed in Build outputs, avoiding large trajectory dumps in the repository.

Development diagnostics show small-margin inversions without hidden saturation.
Add one host-only candidate: positive ReLU activation-range equalization, scaling
incoming weights/bias by g and outgoing weights by 1/g (g clamped 1/8…8).
It preserves real-arithmetic predictions and adds no MCU operations. Compare
with/without it, using calibration data only; measure f32 equivalence explicitly.

## Frozen export choice (before final evaluation)

Development comparison over training seeds 42–46 selects one shared configuration:
greedy rollout calibration (0xa0000000+[0,49]), positive hidden-unit equalization,
mean preactivation bias correction, right-minus-left output and output scale ×1/8.
No seed-specific strategy selection. Normalization and original float checkpoint
remain unchanged. Difference-only export matched centered decisions exactly in the
initial comparisons; it is retained for a smaller output head, not an accuracy claim.
Development int8 means: 227.70 / 171.74 / 422.98 / 250.80 / 178.58.
Do not revise this configuration based on the new final results.

The isolated step-decay experiment helps seeds 42/44 but does not consistently
stabilize all five seeds. Keep production learning fixed; no Double DQN, soft target,
Huber, or QAT implementation is adopted in this phase. Existing best-development
checkpoint selection remains necessary. Preserve all experimental results separately.
