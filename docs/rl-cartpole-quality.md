# CartPole control quality: measured export improvements

Baseline commit: **d82c434**. This report adds results; the [original report](rl-cartpole-report.md)
and original experiment files remain unchanged. All measurements below are host
simulator or final-ELF cross-build measurements on macOS arm64, Zig 0.17.0.
No physical control, MCU latency or stack high-water was measured.

## Protocol and frozen choices

The [predeclared protocol](experiments/rl-cartpole/protocol.md) reserves distinct
training, development, calibration and new final-test seed partitions. Original
training seeds 42/43/44 are retained, with 45/46 added. Candidate comparison uses
0x90000000+[0,49], greedy calibration uses 0xa0000000+[0,49], and the new final test
uses **0xe1000000+[0,49]**. The old public test partition is regression-only.
The selected export configuration was frozen before opening the new final partition.

Every comparison below uses the **same original saved float checkpoint** for baseline
and improved export. [SHA-256 provenance](experiments/rl-cartpole/baseline/manifest.json)
checks byte identity for all five checkpoints after improved export. Physics, 500-step
limit, +1 reward, epsilon=0 evaluation, normalized state and LEFT-on-tie are fixed.
The original 4→16 ReLU→16 ReLU→2 learner, Trainer and checkpoint v1 are unchanged.

## Diagnosis and adopted changes

The host [study tool](../examples/rl-cartpole/study.zig) records normalized inputs,
raw Q values, centered scores, integer scores, signed margins, encoded inputs,
per-layer ranges/errors and clipping. It compares policies on both float and integer
trajectories; those counts are separate. Detailed per-state CSV is generated under
`reports/study/`, while [compact aggregates](experiments/rl-cartpole/quantization-analysis/)
are committed. Margin bins are |D| <0.001, <0.01, <0.05, <0.2, <1, and the remainder. Angle/angular-velocity bins use absolute normalized values <0.1, <0.3, <0.7, and the remainder; multiply by the documented divisors for physical units. Tracing is checked against the independent integer reference on every
state. Reported layer errors include propagated upstream error, not just local rounding.

A likely distribution mismatch is visible in the original pipeline: the best saved policy can come from an earlier episode, while baseline calibration uses the final replay ring, potentially collected after online control has deteriorated. Greedy rollout calibration instead follows the saved policy. This is an explanation supported by the pipeline and measured comparisons, not a claim that one source of error was isolated from every other effect.

Baseline development mismatches concentrate at |RIGHT−LEFT| below 0.05. Input and
hidden saturation were absent on the measured baseline float trajectories. Hidden
rounding/weight error and final zero-score ties, rather than saturation alone, are
important. At new-test seed 42, baseline margin MAE is 0.01785 and 9.38% of float-path
states have an integer tie; improved values are 0.00965 and 0.45%.

We compared baseline replay+anchor, representative bounded states, greedy rollout,
and hybrid calibration. [Candidate CSVs](experiments/rl-cartpole/calibration-comparison/)
retain those comparisons. A single shared configuration was selected across seeds:

1. Reservoir-sample 2,048 states from 50 complete greedy development-calibration
   episodes; repeat populated states if fewer exist. This remains deterministic.
2. Equalize each hidden ReLU unit's observed range using a positive gain, bounded
   to [1/8,8]. Multiply its incoming weights/bias by that gain and divide outgoing
   weights by it. ReLU(g×x)=g×ReLU(x), so the real-arithmetic function is preserved.
3. Export the final head as `D = Q_right − Q_left`, subtracting the original output
   weight rows and biases. Positive D selects RIGHT; zero/negative selects LEFT.
   DQN itself still trains two absolute Q outputs. The original centered-head path
   remains available; difference-only export gave identical integer actions in the
   initial comparisons and is a size optimization, not an accuracy claim.
4. Use the existing int8 exporter, then reduce the output scale to 1/8. This reduces
   zero-score ties, intentionally saturating some large margins while retaining sign.
5. Correct each layer's mean preactivation quantization error using calibration
   samples, adjusting integer biases with overflow checks. No runtime operations
   or learned weights are added to the MCU.

For related primary research, see [Nagel et al., weight equalization and bias correction (ICCV 2019)](https://openaccess.thecvf.com/content_ICCV_2019/html/Nagel_Data-Free_Quantization_Through_Weight_Equalization_and_Bias_Correction_ICCV_2019_paper.html). Zinn uses an independently implemented, calibration-driven range/bias variant; it does not claim to reproduce that paper's data-free method or results.

Implementation is confined to [CartPole host export](../examples/rl-cartpole/policy_export.zig).
The shared classification exporter and int8/int4 kernels are unchanged. Finer output
scales trade absolute score fidelity for sign resolution: **margin MAE does not improve
for every seed**. For example seed 44 rises from 0.01144 to 0.05769 because large
margins clip, while action agreement and reward improve. This is not Q-value regression
with preserved absolute returns. The generated value is an action margin only.

Real-arithmetic equivalence is not bitwise float32 equivalence. On new-test float
trajectories, original versus transformed float actions differ at 2/0/2/1/0 near-tie
states for seeds 42–46. Centering/difference alone already show those small floating
cancellation effects. Counts are saved explicitly rather than assuming exact equality.

## New final test (50 episodes per training seed)

Random Policy has mean 18.84, median 17, maximum 63 and 0/50 successes on this partition.
The tables below are paired comparisons on the **same new final seeds**, not a comparison
of historical 4/50 against results from a different seed set.

| Training seed | Float mean | Baseline int8 mean | Improved int8 mean | Baseline → improved success / 50 | Float-path action agreement |
|---|---:|---:|---:|---:|---:|
| 42 | 211.78 | 163.56 | 217.34 | 0 → 0 | 91.44% |
| 43 | 173.10 | 169.82 | 169.92 | 0 → 0 | 96.79% |
| 44 | 465.52 | 322.04 | 426.72 | 11 → 33 | 88.55% |
| 45 | 242.20 | 244.12 | 252.26 | 2 → 3 | 96.72% |
| 46 | 143.02 | 72.34 | 159.44 | 0 → 0 | 91.50% |

All five improved int8 means exceed baseline int8; seed 43's gain is only 0.10 and
should not be overinterpreted. Improved/float mean is at least 91.7% here. The 95%
action-agreement goal is met for only two of five training seeds. A policy can differ
from float and score better or worse: agreement is not control success.

Full mean, median, population standard deviation, min/max, success counts and all
50 rewards are in [per-seed JSON](experiments/rl-cartpole/improved/). A success reaches
500 steps without physical failure; simultaneous physical failure/time limit is a
failure. Success rates across improved policies range 0–66% (0/0/66/6/0%); float
success rates are 0/0/88/0/0%. This is a small fixed-seed study, not a confidence interval.
Input saturation on improved float trajectories is 0, 0, 0.0021%, 0.0041%, 0.0035%
of encoded input components. Integer-path metrics are separately recorded.

Improved-policy reward dispersion (population standard deviation):

| Seed | Median | Std | Min / max | Improved / float mean |
|---|---:|---:|---:|---:|
| 42 | 205.5 | 56.93 | 142 / 361 | 102.6% |
| 43 | 171.0 | 10.99 | 147 / 197 | 98.2% |
| 44 | 500.0 | 106.59 | 192 / 500 | 91.7% |
| 45 | 231.0 | 90.73 | 133 / 500 | 104.2% |
| 46 | 163.0 | 58.94 | 76 / 413 | 111.5% |

## Learning stability and deferred methods

The [isolated stability runner](../examples/rl-cartpole/stability.zig) compares fixed
SGD with rate ×0.25 after 40,000 updates, using development evaluation only.
It improves late development reward for seeds 42/44, but not all five; seed 46
collapses before reaching the decay threshold. It is retained as an experiment,
not adopted in the production learner. Best-development checkpoint selection remains
necessary. [Raw summaries](experiments/rl-cartpole/training-stability/) record both runs.

Double DQN, soft target updates and Huber loss are not implemented in this phase.
The current clipped TD-target MSE is not relabelled Huber. A broad algorithm sweep
would obscure the measured PTQ improvements. QAT feasibility was reviewed: fake
quantization would round float activations/weights during forward, while a
straight-through gradient approximation would carry gradients through rounding.
Matching Zinn's exact integer bias, scale, saturation and rounding would require
additional validation; no QAT change is made to Trainer or MNIST/XOR.

## Firmware and GUI

| Seed-42 CH32V003 final ELF | Baseline | Improved |
|---|---:|---:|
| Flash | 2,040 B | 2,012 B |
| Static SRAM | 44 B | 44 B |
| Model weights + biases | 488 B | 468 B |
| Workspace | 32 B | 32 B |
| Stack allowance (not measurement) | 512 B | 512 B |
| SRAM margin after allowance | 1,492 B | 1,492 B |

All five improved firmware cross-builds are 2,012 B Flash / 44 B static SRAM.
The one-score output is smaller, but linker alignment keeps total static SRAM
unchanged. Generated kernels match all 128 reference vectors for each seed. Final
ELF checks include startup/runtime/application and reject an undersized budget.

The desktop adds FLOAT / INT8 / COMPARE for saved-model observation. COMPARE resets
both worlds to the same initial state, then advances them independently. A finished
world freezes until its pair finishes, then both reset together. Same-state action
matching probes the integer policy on the float world's state; it is not inferred
by comparing actions on two diverged states. These modes use the saved checkpoint
and its generated integer model, while legacy WATCH still observes the current
training best. Learning RNG/model are untouched by comparison controls.

## Reproduce

```sh
zig build --build-file examples/rl-cartpole/build.zig train e2e firmware -Dpolicy-export=improved -Dprogress=plain
zig build --build-file examples/rl-cartpole/build.zig study -Dprogress=off
zig build --build-file examples/rl-cartpole/build.zig study -Dfinal-test=true -Dprogress=off
zig build --build-file examples/rl-cartpole/build.zig stability -Dseed=44
zig build --build-file examples/rl-cartpole/build.zig run -Dpolicy-export=improved
```

[Full five-seed script](../tests/cartpole_study.sh) saves reproducible raw reports and curves. Repeat with `-Dseed=43|44|45|46` and separate `--prefix` paths. Repeating the final
study verifies the frozen choice; it must not become a tuning loop. Native GUI is
macOS-only. Fixed-seed f32 behavior is checked on the same toolchain/host; cross-CPU
bitwise identity is not promised. Improved export is opt-in; default `baseline`
retains the existing two-output model interface and saved calibration behavior.
