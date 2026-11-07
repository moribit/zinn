# Zinn

A tiny, dependency-free neural network inference framework written in Zig for resource-constrained microcontrollers.

Zig **0.17.0**。Pure ZigでCSV/MNISTを学習・保存・評価し、int8/int4整数推論用Zigソースを生成できます。Dense、Conv2D、AveragePoolと共通モデル定義を実装しています。推論はint8/int32、固定ワークスペース、ヒープ・再帰・浮動小数点演算なし。CH32V003へクロスビルドできます。**実機動作・サイクル値は未検証です。**

## 最短のフロー

共通の学習・評価・本番UARTファームウェア生成:

```sh
zig build mnist-download
zig build train -Dproject=mnist -Dmnist-hidden=32 -Dlearning-rate=0.1
zig build evaluate -Dproject=mnist -Dmnist-hidden=32 -Dlearning-rate=0.1
zig build deploy -Dproject=mnist -Dmnist-hidden=32 -Dlearning-rate=0.1 -Dtarget=ch32v003
```

既定評価はtraining splitから分離したvalidationです。構成確定後だけ`-Devaluation-split=test`で最終評価します。外部アプリ向け`addProject`、CSV入力、UART交換、成果物とキャッシュは[開発・デプロイ手順](docs/deployment.md)と[最小プロジェクト](examples/project/build.zig)を参照してください。`deploy`は書き込みません。物理書き込みは明示的な`flash`です。

従来の専用コマンドも維持しています:

```sh
zig build test                 # 数値・勾配・保存・export・compile-fail
zig build e2e                  # 学習→保存→再読込→量子化→ソース生成→整数推論
zig build deploy               # XOR本番ELF・binary生成と容量検査（物理書込みはしない）
zig build mnist-download       # 明示的に公式データを取得
zig build mnist mnist-firmware # MNIST学習→評価→生成core全test参照一致→V003 cross-build
```

モデル定義は学習・量子化・生成ソースで共通です。

```zig
const zinn = @import("zinn");
const Structure = zinn.Definition(2, &.{
    .{ .units = 8, .activation = .relu },
    .{ .units = 2 },
});
const Training = zinn.Trainer(Structure);
var model = Training.init(42);
// _ = try model.trainEpoch(samples, 0.05);
// const checkpoint = model.encode();
```

利用者が通常のフローで重み・量子化係数を書く必要はありません。[実行可能な共通定義](examples/xor/definition.zig)と[手順・保存形式](docs/workflow.md)を参照してください。

## 操作

| コマンド | 出力・用途 |
|---|---|
| `zig build train` | seed=42で学習し `zig-out/models/xor.zinn` を保存 |
| `zig build eval` | 保存モデルのfloat評価。未指定なら自動学習 |
| `zig build quantize` | 校正・int8化し `zig-out/models/xor.zig` を生成 |
| `zig build e2e` | 生成ソースをコンパイルし全4入力で独立整数参照と照合 |
| `zig build firmware-trained` | 生成モデルのSWIO診断版ELF |
| `zig build firmware-production` | 生成モデルのログなし本番組込用ELF |
| `zig build deploy` | 本番ELF＋`zig-out/firmware/zinn-trained-production.bin` |
| `zig build size` | 全3種類の最終ELFのFlash/SRAM予算検査 |
| `zig build xor` / `firmware` | 既存の手書きXOR Golden／診断版を維持 |
| `zig build benchmark` | 既存XORのホスト参考ベンチマーク |

`eval`・`quantize`・生成モデルのビルドには `-Dcheckpoint=zig-out/models/xor.zinn` で既存checkpointを指定できます。Flash/SRAM/スタック予算は `-Dflash-bytes=16384 -Dram-bytes=2048 -Dstack-bytes=512 -Dreserved-flash-bytes=64` で検査できます。これらは容量検査値であり、HALのMCU選択やリンカ配置を変更しません。

## MNIST・CNN・int4

```sh
zig build mnist-train mnist mnist-firmware -Dmnist-model=cnn
zig build mnist mnist-firmware -Dmnist-model=cnn -Dweight-format=int4 \
  -Dmnist-checkpoint=zig-out/models/mnist-cnn.zinn
```

validationで構成を固定した最新評価（train55,000/validation5,000/test10,000）では、MLP32 int8=**96.59%**／int4=94.90%、CNN4 int8=97.07%／int4=95.21%。4構成とも全test入力・全logitが独立整数参照と一致し、UART本番版をV003容量内でクロスビルド済みです。CNN4は512Bスタック予算込みのRAM余裕128Bで、追加機能には再検査が必要です。実機の動作・50ms・stack最大使用量は未検証です。[条件・比較・容量](docs/practicality-report.md)。前フェーズのMLP16/CNN2の結果は履歴として残しています。

汎用CSVは `zig build data-train -Dfeatures=... -Dclasses=... -Dcsv-train=... -Dcsv-test=...`。詳細は[データ・MNIST手順](docs/mnist.md)、[実測レポート](docs/mnist-report.md)、[CNN/int4設計](docs/mnist-cnn-int4-design.md)。

## 低レベルAPI

手書き `Dense/Sequential/infer` も継続利用できます。重みはoutput-major、biasはaccumulator単位。

```zig
const Model = zinn.Sequential(.{
    zinn.Dense(.{
        .input = 2, .output = 2,
        .weights = &.{ 1, -1, -1, 1 },
        .bias = &.{ 0, 0 },
        .activation = .relu,
    }),
});
var workspace: Model.Workspace = undefined;
var output: [Model.output_len]i8 = undefined;
Model.infer(&.{ 0, 1 }, &output, &workspace);
```

生成モデルには実数scaleのcomptime metadataが入り、係数・隣接scaleを検証します。legacyのmetadata未指定モデルでは従来の整数契約を維持します。入力・出力はworkspaceと重ねず、workspaceを同時使用しないでください。

Python、外部Cライブラリ、MLランタイムは不要です。HALだけに `ch32fun_zig` の未改変・固定スナップショットを使用します。[出典と公開許可](vendor/ch32fun_zig/UPSTREAM.md)。

詳細: [設計](docs/developer-experience.md)、[アーキテクチャ](docs/architecture.md)、[数値仕様](docs/quantization.md)、[容量](docs/memory-budget.md)、[最新検証](docs/practicality-report.md)、[初期調査](docs/research.md)。

学習器はDense/Conv2D/AveragePool/ReLU、MSEまたはsoftmax CE、mini-batch SGD。量子化は対称int8/int4のmin/max校正です。QAT、自動量子化探索、Depthwise、CH32V006は未実装です。XORの4/4は真理値表の検証であり汎化精度ではありません。
