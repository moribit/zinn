# Documentation

Start with [Getting Started](getting-started.md), then [an independent CSV application](tutorials/csv-classifier.md). Neither requires hardware or real MNIST training.

## Tutorials

1. [Train XOR](tutorials/xor.md)
2. [Custom CSV Classifier](tutorials/csv-classifier.md)
3. [MNIST on CH32V003](tutorials/mnist.md)
4. [UART Inference](tutorials/uart.md)

## Reference and concepts

- [API reference](api/README.md): models, training/data, quantization/export, inference/workspace, Build API/options, budgets, UART/adapters.
- [Concepts and internals](concepts.md), [numerical contract](quantization.md)
- [Benchmarks and reproducibility](benchmarks.md)
- [Host progress, streaming download and display controls](progress.md)
- [Documentation audit](documentation-audit.md), [documentation verification](documentation-validation.md)
- [Contributing](../CONTRIBUTING.md), [security](../SECURITY.md), [licenses](licenses.md)

## Research and history

These are dated records, largely in Japanese. Current commands are specified by tutorials/reference; historical results describe their original configuration, not today's defaults. Paths are preserved for existing links.

- [Initial research](research.md), [early roadmap](roadmap.md)
- [Architecture notes](architecture.md), [memory notes](memory-budget.md)
- [Original workflow](workflow.md), [developer experience design](developer-experience.md)
- [First training phase](next-phase-report.md)
- [Original MNIST workflow](mnist.md), [CNN/int4 design](mnist-cnn-int4-design.md), [first MNIST results](mnist-report.md)
- [Quality review](quality-review.md), [validation plan](validation-plan.md), [latest experiment record](practicality-report.md)
- [Stored curves and manifests](experiments/README.md)

[Deployment](deployment.md) is a compatibility entry point to the tutorials/reference.

## Learning machine learning

Seven paired chapters for newcomers: [English](tutorials/en/00-machine-learning-basics.md) / [日本語](tutorials/ja/00-machine-learning-basics.md). Each chapter links concepts to code, executable commands and the next chapter. [CartPole export quality](rl-cartpole-quality.md) records the new controlled study separately from the original baseline.
