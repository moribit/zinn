# Zinn

**小さなニューラルネットワークをPure Zigで。ホスト学習からマイコン向けファームウェア生成まで。**

[English](README.md) · [Getting Started](docs/getting-started.md) · [文書一覧](docs/README.md)

Zinnは極小マイコン向けの機械学習推論フレームワークです。Zig **0.17.0**でモデルを定義・学習・評価し、整数推論用ZigコードとCH32V003向けファームウェアを生成します。

## 特徴

- Pure ZigによるDense/CNN学習、CSV/IDX/gzip入力、checkpoint、校正、ソース生成。
- int8 activation、int32累積、int8/packed int4重み。MCU推論ではヒープ・浮動小数点演算・動的Graph Interpreterを使いません。
- comptimeによる形状・量子化契約の検証と、呼び出し側が所有する静的workspace。低レベルAPIによる明示的な制御も維持。
- zig buildによる学習キャッシュ、独立整数参照との照合、最終ELFの容量検査。
- Python・外部MLフレームワーク・Cライブラリは必須ではありません。同梱ch32fun_zigはMITライセンスでボードサポートだけに使います。

## 対応状況

| 対象 | 状況 |
|---|---|
| macOS / Linux | ホストAPI・ツール。両OSのCIを設定 |
| CH32V003 / RV32EC | クロスビルド・容量検査済み。**実機動作は未検証** |
| CH32V006 / 他MCU | 今後の対応。推論コアはMCU非依存 |

## 代表結果

構成固定後の公式MNIST test 10,000件、16×16面積縮小入力。精度はホスト評価、容量はCH32V003向けUART版クロスビルドの値です。

| モデル | 整数精度 | Flash | 静的SRAM |
|---|---:|---:|---:|
| MLP32 int8 | **96.59%** | 12,408B | 460B |
| MLP32 int4 | 94.90% | 8,184B | 460B |
| CNN4 int8 | 97.07% | 6,436B | 1,408B |
| CNN4 int4 | 95.21% | 5,496B | 1,408B |

全10,000件の全logitが独立整数参照と一致。容量はstartup/runtime/通信を含み、**512Bのスタック予算は別枠**、Flash16KB中64Bを予約します。CNN4の予算後RAM余裕は128Bです。実機サイクル・時間・stack high-waterは未測定。既定はMLP16/CNN2です。[再現条件](docs/benchmarks.md)と[記録](docs/practicality-report.md)を参照してください。

## Quick Start — 実機不要

```sh
git clone https://github.com/moribit/zinn.git
cd zinn
zig version                    # 0.17.0であること
zig build test
zig build train                # XORの短い学習
zig build evaluate             # float/整数の分類評価
zig build quantize             # 整数推論用Zigソース生成
zig build e2e                  # ホスト整数推論・参照照合
zig build deploy               # XOR ELF/bin生成・容量検査。書き込みはしない
```

成果物の詳細は[Getting Started](docs/getting-started.md)。標準の技術文書は英語です。

ホストの進捗表示はstderrに出力します。autoでは対応端末でASCIIバーを更新し、`-Dprogress=plain`でログ表示、`-Dquiet=true`で無効化できます。学習中はEpoch／Batch進捗を表示し、plain形式のログも保存します。キャッシュ利用時は`cached`と成果物の場所を表示します。ダウンロードはファイル名、KiB／MiB単位の転送量・速度、ETAを表示します。[設定とBuildの制約](docs/progress.md)を参照してください。

## 共通モデル定義

<!-- zinn-api-sample -->
```zig
const zinn = @import("zinn");
pub const Structure = zinn.Definition(2, &.{
    .{ .units = 8, .activation = .relu },
    .{ .units = 2 },
});
```

この例は[コンパイル検証](examples/docs/model.zig)しています。通常、重みや量子化係数はツールで生成します。CNNは[ImageDefinition](docs/api/models.md)、細かな制御は[低レベルAPI](docs/api/inference.md)を使えます。

## アプリの学習・評価・デプロイ

独立パッケージ[examples/project](examples/project/build.zig)は、モデル・CSV・addProjectを使うbuild.zigを含みます。

```sh
zig build --build-file examples/project/build.zig train evaluate e2e deploy infer-host simulate-uart
```

.zinn、生成.zig、.elf、.bin、入力フレーム、JSONレポートを出力します。deployは生成・検査だけです。書き込みはchzigと実機が必要な明示的flash操作に分離しています。[CSVチュートリアル](docs/tutorials/csv-classifier.md)と[Build API](docs/api/build.md)を参照してください。

共通のtrain/evaluate/e2e/deploy/flashは`-Dproject=xor|mnist|csv`で一貫して対象を選びます（既定xor）。E2EのPASSは整数参照との全logit一致であり、分類精度ではありません。キャッシュ時のサマリー、checkpoint再利用、旧コマンドからの移行は[CLIリファレンス](docs/cli.md)を参照してください。

## 既存アプリへの組み込み

`addModel()`はファームウェアを作らず、学習・評価・モデル生成だけを行います。
生成モデルは利用先ターゲット用Moduleとして通常の`root_module.addImport()`で追加し、
既存のmainループ・HAL・入出力を維持できます。`addInferenceModule()`は整数推論のみ、
`addMemoryCheck()`は既存アプリ全体の最終ELF容量を検査します。
従来の`addProject()`はUART／デプロイを含む一括ワークフローとして利用できます。

```sh
zig build --build-file examples/integration/host-app/build.zig sensor-generate sensor-e2e run
zig build --build-file examples/integration/ch32-existing-app/build.zig
zig build --build-file examples/integration/multi-model/build.zig run
```

実機や書き込みは不要です。[組み込み方法とBuild例](docs/integration.md)を参照してください。

## 例とドキュメント

- [XOR](docs/tutorials/xor.md)：学習・生成・整数推論とGolden Test。
- [独立CSVアプリ](docs/tutorials/csv-classifier.md)：addProjectの使い方。付属データはXORのfixture。
- [MNIST](docs/tutorials/mnist.md)：MLP/CNN、int8/int4、validation、ファームウェア生成。
- [UART推論](docs/tutorials/uart.md)：外部入力、全logit応答、ホストsimulationと実機操作。
- [一覧](docs/README.md)、[API](docs/api/README.md)、[概念](docs/concepts.md)、[数値仕様](docs/quantization.md)、[結果](docs/benchmarks.md)。

## 状態・コントリビュート

初期段階のOSSです。低レベルAPIとcheckpoint v1を維持し、高レベルツールは今後改善します。実データ精度・ホスト参照一致・クロスビルドを記録済み。実機動作・50ms目標は未検証、per-channel量子化・QAT・int2・CH32V006は未実装です。UARTのCRCは認証・暗号化ではありません。

[CONTRIBUTING](CONTRIBUTING.md)、[行動規範](CODE_OF_CONDUCT.md)、[セキュリティ方針](SECURITY.md)、[CHANGELOG](CHANGELOG.md)を参照してください。

## ライセンス

Zinn本体は[MIT](LICENSE)。同梱ch32fun_zigにも[独立したMIT表記](vendor/ch32fun_zig/LICENSE)があります。[出典](vendor/ch32fun_zig/UPSTREAM.md)を保持してください。データセットの条件はコードのライセンスとは別です。
