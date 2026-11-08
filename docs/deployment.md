# Deployment documentation

The unified workflow is now documented by topic rather than repeated here:

- [Getting Started](getting-started.md): host-only XOR and firmware generation.
- [Custom CSV Classifier](tutorials/csv-classifier.md): application-owned addProject package.
- [MNIST](tutorials/mnist.md): validation, quantization and production firmware.
- [UART Inference](tutorials/uart.md): simulation, wiring and explicit physical operations.
- [Build/options/artifacts](api/build.md), [memory budgets](api/budgets.md), [canonical wire protocol](api/uart.md).

`deploy` generates/checks firmware; `flash` is explicit physical writing. Keep model/checkpoint/preprocessing/format options consistent. Hardware execution/timing remains unverified. The previous phase's results remain in the [dated report](practicality-report.md).
