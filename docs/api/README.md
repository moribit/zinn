# API reference

Public library entry point: [src/root.zig](../../src/root.zig). Build integration is exported from [build.zig](../../build.zig), implemented in [build_support/project.zig](../../build_support/project.zig); it is not a runtime root.zig function.

| Topic | APIs |
|---|---|
| [Models](models.md) | Definition, ImageDefinition, Shape, Tensor |
| [Training and data](training-data.md) | Trainer, fit, CSV, IDX, gzip, resize |
| [Quantization/export](quantization-export.md) | Params, coefficient, QuantizedFormat, source generation |
| [Inference](inference.md) | Dense, Conv2D, AveragePool2D, Sequential, Workspace, infer, argmax, packed weights |
| [Build/options](build.md) | addProject, artifacts, root CLI, examples |
| [Budgets](budgets.md) | Model estimate, Target, final ELF accounting |
| [UART/adapters](uart.md) | protocol, Service, board callbacks, timing |

Signatures below use the implementation's inferred error sets (`!T`). Listed errors describe semantic failures; allocator, I/O and writer errors may also propagate. Compile-time model validation reports compiler errors, not recoverable runtime errors. Source links provide complete implementation details. [Executable API samples](../../examples/docs/api.zig) are compiled/run by docs-check; snippets marked excerpts require their surrounding build/function context.
