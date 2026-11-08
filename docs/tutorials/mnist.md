# Tutorial 3 — MNIST on CH32V003

Use Zig0.17.0 from the checkout root. This tutorial separates a quick offline integration check from real fitting and physical operations. Default models are MLP16/CNN2, not the larger benchmark candidates.

[Progress controls](../progress.md): -Dprogress=auto|plain|off, or -Dquiet=true. Training reports epoch/batch/loss/validation/lr/best selection without extra forward passes; CSV curves remain unchanged. Cache hits show `cached` and checkpoint/log paths without replaying old epochs. Build training/export logs are saved under reports. Downloads show human-readable byte counts/speeds, stream to validated atomic temporaries, explicitly report cached files and support -Ddownload-force=true. Missing Content-Length is supported without a guessed percentage.

## Offline integration — no board or download

```sh
zig build deploy infer-host simulate-uart -Dproject=mnist -Dmnist-fixture=true -Dmnist-epochs=1 -Dapp-name=mnist-demo
zig build deploy -Dproject=mnist -Dmnist-fixture=true -Dmnist-epochs=1 -Dapp-name=cnn-demo -Dmnist-model=cnn -Dweight-format=int4
```

Synthetic IDX/gzip fixtures exercise loading/fitting/export/reference agreement/cross-build. Their scores are not MNIST accuracy. deploy saves final capacity reports. Common outputs are listed in the [Build reference](../api/build.md#artifacts).

## Real dataset and training — opt in

The following commands download data and perform real fitting; they are not part of documentation validation:

```sh
zig build mnist-download
zig build train -Dproject=mnist -Dapp-name=digits -Dmnist-hidden=32 -Dlearning-rate=0.1 -Dmnist-epochs=20
zig build evaluate -Dproject=mnist -Dapp-name=digits -Dmnist-hidden=32 -Dlearning-rate=0.1 -Dmnist-epochs=20
zig build deploy -Dproject=mnist -Dapp-name=digits -Dmnist-hidden=32 -Dlearning-rate=0.1 -Dmnist-epochs=20 -Dtarget=ch32v003
```

Keep options identical across commands. Data defaults to data/mnist; use -Ddata-dir=/your/path for the four official train/t10k gzip IDX files. Default preprocessing is area28to16_div255. MLP input256 → hidden32/ReLU →10 logits here; CNN uses Conv3×3, average pooling2×2/stride2, Dense10.

Official train60,000 is shuffled with split_seed24301 into55,000 training and5,000 validation. Seed42 controls initialization/training order independently. Mini-batch32, rate0.1 here (default0.05), decay×0.3 every10 epochs. Best validation accuracy selects the checkpoint, with CE as tiebreaker. Calibration uses training only, default1024 samples. Evaluation defaults to validation and does not read official test files. Curves/configuration should accompany the checkpoint.

## Reuse a checkpoint and change weight format

```sh
zig build evaluate deploy -Dproject=mnist -Dapp-name=digits-int4 -Dmnist-hidden=32 -Dweight-format=int4 -Dproject-checkpoint=zig-out/training/digits.zinn
```

Preprocessing, Structure and split/calibration settings must match. A checkpoint alone does not record them. Both formats use int8 activations; int4 saves weight Flash, not activation SRAM. Low-bit decoding has an unmeasured MCU time cost. CNN4 requires -Dmnist-model=cnn -Dcnn-channels=4 and has very little RAM headroom with UART. Always inspect the final memory report.

After freezing the model/configuration, explicitly add -Devaluation-split=test to evaluate the official10,000. Never tune on test accuracy. [Benchmarks](../benchmarks.md) supplies the exact selected seeds/checkpoints and a fixed-study script rather than suggesting a test-driven search.

## Firmware and hardware

Common deploy emits UART production firmware, with no SWIO terminal dependency. The legacy `mnist-firmware` is separately maintained: it embeds a verification image and prints diagnostic SWIO output. Do not describe it as an external-input application. Neither build step writes a board. [UART Inference](uart.md) covers explicit flashing/exchange, with all physical behavior unverified.
