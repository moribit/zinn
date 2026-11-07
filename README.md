# Zinn

A tiny, dependency-free neural network inference framework written in Zig for resource-constrained microcontrollers.

Zig **0.17.0**。推論コアは標準ライブラリのみ。int8 Dense、int32累積、ReLU、固定小数点再量子化、Argmax、comptimeモデル、静的ワークスペースを実装しています。CH32V003向けXORはクロスビルド済みです。**実機動作は未検証**です。

```sh
zig build test                 # unit/golden + expected compile errors
zig build xor                  # host: all 4 XOR cases
zig build firmware             # zig-out/bin/zinn-xor (ELF)
zig build size                 # Pure Zig ELF memory budget check
zig build benchmark            # fast host benchmark
zig build test -Doptimize=safe
```

Python、Cコンパイラ、MLランタイム、外部サイズ計測ツールは必須ではありません。初回もネットワークなしでビルドできます。HALだけに `ch32fun_zig` の固定スナップショットを使用します。[出典と公開許可の記録](vendor/ch32fun_zig/UPSTREAM.md)。

```zig
const zinn = @import("zinn");
const Model = zinn.Sequential(.{
    zinn.Dense(.{
        .input = 2, .output = 2,
        .weights = &.{ 1, -1, -1, 1 }, // output-major
        .bias = &.{ 0, 0 },
        .quant = .{ .multiplier = 1, .shift = 0 },
        .activation = .relu,
    }),
});
var workspace: Model.Workspace = undefined; // firmware: place at file scope
var output: [Model.output_len]i8 = undefined;
Model.infer(&.{ 0, 1 }, &output, &workspace);
const class = zinn.argmax(&output).?;
```

重みとバイアスはcomptimeの定数。接続形状・ゼロポイント・int32安全性をコンパイル時に検証します。推論時のヒープ、再帰、浮動小数点演算はありません。出力はワークスペースとは別の呼び出し側配列に格納します。同じワークスペースを並行使用しないでください。

詳細: [設計](docs/architecture.md)、[量子化仕様](docs/quantization.md)、[調査](docs/research.md)、[メモリ](docs/memory-budget.md)、[検証結果](docs/benchmarks.md)、[ロードマップ](docs/roadmap.md)。

int4/int2、学習器、MNIST、CNN、CH32V006は未実装です。MNIST 95% / 50msの達成は主張しません。
