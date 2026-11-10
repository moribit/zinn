# Zinn RL Lab — CartPole

A Pure Zig DQN example: train without a display, inspect the learned policy in
mimoc-ui, and cross-build an integer-only CH32V003 firmware. Zig 0.17.0 is required.
No Python, Gymnasium, physics engine, or external ML library is used.

## Headless first

Run from the Zinn repository root (macOS or Linux):

```sh
zig build --build-file examples/rl-cartpole/build.zig test
zig build --build-file examples/rl-cartpole/build.zig train -Dprogress=plain
zig build --build-file examples/rl-cartpole/build.zig evaluate
zig build --build-file examples/rl-cartpole/build.zig e2e
zig build --build-file examples/rl-cartpole/build.zig firmware
```

`train` runs 1,000 episodes and saves the best development policy. `evaluate`
displays the saved final evaluation, without retraining or repeating evaluation.
`e2e` compares all integer scores against an independent reference on 128 calibration
states; this is not a reward measurement. `firmware` also checks the final ELF;
it does **not** flash hardware. Unchanged training/export steps use the Build cache.
Use `-Dprogress=auto|plain|off` for the existing host progress presenter.

Artifacts under `examples/rl-cartpole/zig-out/`:

| Path | Content |
|---|---|
| `training/cartpole.zinn` | Best original float Q network; checkpoint v1 |
| `reports/curve.csv` | Exploration rewards, mean100, development scores, loss, counts |
| `reports/report.json` | All 50 held-out rewards per policy and agreement counts |
| `reports/calibration.csv` | Label-first baseline calibration; improved profile regenerates greedy rollouts |
| `models/policy.zig` | Generated int8 centered action-score model and reference vectors |
| `reports/policy.json` | Input/output scales, normalization and model identity |
| `reports/cartpole-policy-memory.json` | Final ELF budget report |
| `firmware/cartpole-policy.elf`, `.bin` | Integer-only CH32V003 application |

See [measured results](../../docs/rl-cartpole-report.md). The three tested training
seeds improve on random play; int8 quality varies and remains below float quality.

## Configuration

| Build option | Default | Meaning |
|---|---:|---|
| `episodes` | 1000 | Training episodes |
| `seed` | 42 | Model, exploration and replay seed |
| `rate` | 0.005 | Mini-batch SGD learning rate |
| `gamma` | 0.95 | Discount factor |
| `epsilon-start`, `epsilon-end` | 1, 0.05 | Linear exploration bounds |
| `epsilon-steps` | 10000 | Environment steps to minimum epsilon |
| `replay-capacity` | 10000 | Ring capacity; 480,000 bytes on 64-bit hosts |
| `batch` | 32 | Samples per update, maximum 128 |
| `train-every` | 1 | Environment steps per SGD update |
| `target-interval` | 100 | SGD updates between target copies |
| `reward-scale` | 1 | Bellman reward multiplier |
| `flash-bytes` | 16384 | Final ELF Flash budget, including 64 B reservation |
| `check-improvement` | false | Evaluation fails if float ≤2×random or int8 ≤random |

Warmup is 512 transitions; the clipped TD residual is ±1, and |Q| above 100
fails training. These are `zinn.rl.dqn.Options` defaults, not additional CLI flags.
Small episode counts are useful for smoke tests but do not demonstrate learning.

Reuse a checkpoint and its calibration set without training:

```sh
zig build --build-file examples/rl-cartpole/build.zig train e2e \
  -Dcheckpoint=examples/rl-cartpole/zig-out/training/cartpole.zinn \
  -Dcalibration=examples/rl-cartpole/zig-out/reports/calibration.csv
```

Use a separate `--prefix` when retaining multiple runs. A checkpoint stores policy
parameters/seed, **not** replay, target network, RNG or optimizer/session state;
loading evaluates/exports the policy and does not resume training. Without a supplied
calibration CSV, loading generates random-rollout calibration states, so int8
results may differ. The saved label is ignored for calibration.

## Desktop (macOS)

```sh
zig build --build-file examples/rl-cartpole/build.zig run
zig build --build-file examples/rl-cartpole/build.zig test-gui -Doptimize=safe
```

The first build produces a saved policy through the headless pipeline. The desktop
then starts a fresh automatic training session; no human action selection is needed.
The 640×400 monochrome logical surface uses mimoc-ui's existing centered buttons
and pixel font. The AppKit window has a 960×600-point minimum content size and
scales/letterboxes when enlarged. Native GUI support is currently macOS only.

- **TRAIN:** return to the preserved training session; restart if already completed.
- **PAUSE / RESUME:** freeze/resume the current mode.
- **RESET:** reset model, replay, seeds, environment and reward history; retain speed.
- **WATCH:** suspend training and run greedy actions from its current best development
  policy, or the saved headless checkpoint before the first development evaluation.
- **SPEED:** cycle 1× / 8× / 64× simulated time. No exploration or training setting changes.

Physics always advances by 0.02 simulated seconds. A bounded synchronous scheduler
consumes training steps separately from rendering; frame count and input timing
are not RNG inputs. Speeds change throughput, not the sequence of training updates
for an equal number of steps. Long frames cap admitted wall time; no real-time speed
is guaranteed. Development evaluations can briefly block the UI. No worker thread,
background synchronization or per-frame heap allocation is needed. GUI sessions
are in-memory only; use headless training to persist checkpoints and curves.

Render a deterministic saved-policy snapshot without opening a window:

```sh
zig build --build-file examples/rl-cartpole/build.zig
./examples/rl-cartpole/zig-out/bin/zinn-rl-lab --snapshot cartpole.pbm
./examples/rl-cartpole/zig-out/bin/zinn-rl-lab --snapshot-compare cartpole-compare.pbm
```

## Environment and deployment

State: cart position/velocity and pole angle/angular velocity. Actions: LEFT/RIGHT.
Reward: +1 per step, including the final failure step; limit: 500. Physical failure
and time-limit truncation are distinct, with bootstrap only across truncation.
[Physics, RL API and quantization details](../../docs/rl.md) describe normalization,
loss, calibration and the centered output representation.

The firmware's exported `cartpole_input[4]` holds **already quantized normalized**
state; `cartpole_scores[2]` and `cartpole_action` expose results for a debugger or
application adapter. It contains no simulator, replay, learning, UART service or
floating-point preprocessing. Divide the physical state by metadata's divisors,
clamp to [-1,1], then use the generated input scale and Zinn's signed rounding/
saturation convention on the host or an appropriate fixed-point application adapter.
Do not feed raw physical values to the integer input. Left wins tied scores.

Flash/RAM reports are cross-build results; cycles, latency, stack high-water and
physical control are **not measured**. This simulator is not a real actuator controller.

## Improved export and policy comparison

Default `-Dpolicy-export=baseline` retains the two-score interface. Select
`-Dpolicy-export=improved` for rollout calibration, positive ReLU equalization,
calibration bias correction and a one-score RIGHT−LEFT output. The saved original
Q checkpoint, training defaults and input normalization stay unchanged. Use
`Model.output_len` when allocating output: improved output length is one. Its
positive score means RIGHT; zero/negative means LEFT. See the [controlled quality
report](../../docs/rl-cartpole-quality.md) for measured improvements and unmet goals.

```sh
zig build --build-file examples/rl-cartpole/build.zig train evaluate e2e firmware -Dpolicy-export=improved
zig build --build-file examples/rl-cartpole/build.zig run -Dpolicy-export=improved
zig build --build-file examples/rl-cartpole/build.zig study
zig build --build-file examples/rl-cartpole/build.zig study -Dfinal-test=true
zig build --build-file examples/rl-cartpole/build.zig stability -Dseed=44
```

`study` compares only development candidates by default. `-Dfinal-test=true`
evaluates the frozen baseline/improved pair on the new held-out seed partition;
it does not select another candidate. Detailed diagnostics and compact JSON are
installed in `reports/study/`. `stability` is an isolated fixed/step-decay experiment;
it never changes normal training settings. Real-arithmetic transform equivalence
does not guarantee identical float32 decisions at exact/near ties.

New **FLOAT**, **INT8**, **COMPARE** buttons use the saved checkpoint and its integer
export. COMPARE starts both worlds from the same state and advances independent
trajectories, freezing an ended world until the pair ends. Its same-state match
label probes int8 on the float state; it does not equate two diverged states.
Legacy WATCH still uses the current training best. Training is paused during all
watch modes. Integer scores are margins/scores, not absolute return Q values.
The logical screen is now 640×400; snapshots follow that size. Buttons remain
standard mimoc-ui widgets. The native initial/minimum content size is 960×600 points.

Beginner explanations: [English DQN](../../docs/tutorials/en/05-cartpole-dqn.md) /
[日本語・CartPole DQN](../../docs/tutorials/ja/05-cartpole-dqn.md).
