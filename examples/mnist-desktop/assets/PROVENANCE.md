# Bundled model provenance

- Pure Zig Zinn MLP256→32(ReLU)→10, int8 weights/activations, int32 accumulation.
- Float checkpoint: val-mlp32-lr1-e20-s42, the fixed seed 42 candidate from
  [the practicality study](../../../docs/practicality-report.md).
- Official MNIST training 60000 split into 55000 fitting /5000 validation using
  split seed 24301. Batch 32, SGD/CE, lr 0.1, 20-epoch maximum, decay every 10×0.3.
  The retained checkpoint is best validation epoch 13 (22347 optimizer steps).
- Re-exported using current addModel, area28→16 /255 preprocessing and calibration
  on 1024 training samples. Validation float 4768/5000 (95.36%), int8 4757/5000
  (95.14%). These are validation classification results, **not handwriting UI
  accuracy**. The official test split was not used for this export/calibration.
- Model ID 2368000046, schema tag 86235137184251204, parameter bytes 8680,
  workspace 32B, input 256B/output 10B, input_scale1/127, input zero point 0.
- The source also contains 16 quantized inputs from the validation partition and
  expected logits, emitted by Zinn's normal verification exporter. MNIST source:
  [CVDF mirror](https://github.com/cvdfoundation/mnist), originally the MNIST
  handwritten digit database by Yann LeCun, Corinna Cortes and Christopher Burges.
- Native UI dependency: [moribit/mimoc-ui](https://github.com/moribit/mimoc-ui)
  at aa61a53e63595f764b96a9dfd09b870d7a2f95d5; no upstream changes required.

Reproduce with the `refresh-bundle` command in the [example guide](../README.md),
using this checkpoint, the four official gzip files and Zig 0.17.0. Assets are
updated from cached generated artifacts via std.Build.UpdateSourceFiles, without
manual weight/source editing. model.json retains Zinn's existing schema.

SHA-256 of the bundled artifacts:

```text
model.zinn:
1b3e3746e02191bdeed9f0d8c80dcc97d5813d283eaa9d687ee3589905d4a2df
mnist-mlp32-int8.zig:
46bcb8748d5d7a2b3efb0ecd9c05fc35af4f5b091c77b274a9dd40f2f873f9ec
```
