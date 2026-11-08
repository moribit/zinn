# 開発体験の設計（次フェーズ）

> Historical design rationale. Current public API and options are documented in the [API reference](api/README.md).

## 現行APIの分析と互換性

既存Denseは重み・bias・整数係数をcomptimeで受け取り、Sequentialはshapeとzero pointだけを検証していた。学習用shapeも実数scaleも持たず、入出力を2面workspaceへコピーしていた。Tensorは実装ではゼロ次元を許すが文書では拒否と記述され不一致。CIのtee pipelineは明示的なpipefailを持たない。

低レベル `Dense/Sequential/infer/Workspace` と既存XOR logitsは維持する。workspaceの内部配置とbytes値は最適化対象で、呼び出し側はopaqueなWorkspace型を使う。Tensorはゼロサイズ次元を拒否する仕様へ揃える。

## 統一定義

`Definition(input, &.{ .{ .units=8, .activation=.relu }, .{ .units=2 } })` がshape/activationを唯一の定義とする。`Trainer(Definition)` は同じ層情報を使うホスト専用f32モデル。整数exportもその定義からDense配列を生成する。既存手書きDenseは独立して利用可能。学習器やファイルIOは推論実行経路に含めない。

初期学習器は固定seedの初期化、Dense/ReLU、MSE、全層逆伝播、SGD、分類評価。XOR全4入力は真理値表の動作検証であり、未知データの汎化精度ではない。保存形式はversion/schema識別子/float32パラメータをlittle endianで持ち、不一致・非finite・破損を拒否する。学習は再現可能な固定epoch数とする。

## 量子化と生成物

ホストで代表入力から各層activationを校正し、対称int8/zero=0、重みscale、int32 bias、multiplier/shiftを計算する。校正は単純なmin/max方式で、自動探索/QATではない。生成物は通常のZigソースで、構造・重み・係数・実数scale metadataを含む。コンパイラが配列shapeとint32安全性を再検証する。

低レベル量子化へoptional input/weight/output scaleを追加する。legacyは全て未指定で従来の整数契約。metadataを使うモデルでは全層で指定し、正有限値、整数係数との近似誤差、隣接scaleの完全一致を検査する。新旧metadataの混在も拒否。metadataはcomptime専用でMCUの浮動小数点演算を増やさない。

## SRAMとデプロイ

2層以上は入力から直接最初の中間配列へ書き、最後は出力へ直接書く。中間層の偶奇別最大幅だけを確保する。単層の入出力alias互換にはworkspace経由のfallbackを持つ。入力・出力とworkspaceの重複は禁止。

Build graphは `train → 保存 → eval/quantize → Zig生成 → host integer検証/firmware`。生成ファイルはcache/outputへ置き、手編集不要。`zig build` の各操作は同じ保存形式と定義を共有する。診断版はSWIOとcycle出力、本番版はログなし。deployはまず書込み可能なbinaryを生成し、物理flashは明示操作に限定する。

ターゲット予算はFlash origin/容量、RAM origin/容量、reserved Flash、stack予算を持つ。ELFのロード配置でStartup/runtime/weights/data/bssを含めて検査する。モデル単体の見積りと最終ELF計測を区別する。V003以外はユーザー指定予算の検査までで、V006 HAL実装は後段階。

## 検証方針

各段階で既存Goldenと数値境界、compile-fail、学習収束・勾配・保存復元・破損拒否、量子化後の全4入力、生成物の同一性、ホスト/MCU共通ソース、診断/本番の容量を確認する。実機がなければcross-buildだけを成功と記録。int64のサイクルは実機測定が必要で、ホストの時間から推測しない。
