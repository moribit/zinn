# XOR開発体験フェーズ検証レポート（過去のbaseline）

現行のCNN/MNIST/int4と容量差は[MNIST検証レポート](mnist-report.md)を参照。以下は前フェーズ時点の記録。

2026-11-07、macOS aarch64、Zig **0.17.0**の実体を明示してローカル検証。作業中にPATHのzigが0.17.1へ変更されたため、その後は `/Users/mimoc/.zvm/0.17.0/zig` を使用。CI設定は更新したが、この変更のリモートCI実行は未確認。

## 実装済み

共通Definition、Pure Zig f32 Dense/ReLU/MSE/逆伝播/batch SGD、seed、float評価、version/schema/checksum付きcheckpoint保存・復元、代表入力による対称int8量子化、Zigソース生成、生成コードのhost整数推論、V003診断/本番ELFとbinary、モデル/最終ELFの予算検査。

低レベルDense/Sequential/inferを維持。入力コピーと最終コピーを除去し、中間出力の偶奇別最大幅を確保。単層の入出力aliasも維持。Tensorのゼロサイズ次元は拒否する仕様に統一。scale metadataの正有限値・完全指定・係数近似誤差・層間一致・legacy混在を検証。CIは明示bash/pipefailでpipelineの失敗検出を修正。

## 学習と整数一致

XOR 2→8(ReLU)→2、seed42、10,000 epochs、learning rate0.05。float MSE=5.4013035e-12、全4入力正解。2→4→2では3/4で停滞したため、hidden幅8を採用。自動探索で成功モデルを選んではいない。

| 入力 | 生成モデルのint8 logits | class |
|---|---|---:|
| 00 | [127, 1] | 0 |
| 01 | [0, 127] | 1 |
| 10 | [0, 125] | 1 |
| 11 | [127, -1] | 0 |

全4入力で独立int64参照の除算式と生成コードのcore実行が完全一致。checkpointの再読込から同じZigソースを生成できることもテスト。XOR全4入力は学習/校正/真理値表検証に用いており、独立テストセットでの汎化精度ではない。

既存手書きXORは以前のlogits [1,0]/[0,1]/[0,1]/[1,0]を維持し、workspaceは4B→2B。学習モデルはworkspace8B、重み/bias計72B。

## テストとビルド

- `build test`: Unit/Golden/勾配/保存/校正/ELF/budget tests 14/14成功。compile-fail 13ケースでshape、overflow、zero、scale、係数、Tensor、モデル容量を検証。
- `build test -Doptimize=safe`: 成功。
- `build xor`: 既存4/4成功。
- `build e2e`: 学習→保存→再読込→量子化→生成Zig compile→整数4/4参照一致。
- `build eval -Dcheckpoint=zig-out/models/xor.zinn`: 保存済みモデルを評価成功。
- `build firmware firmware-trained firmware-production deploy size`: 全版cross-build、binary生成、容量検査成功。
- Flash=1024Bの意図的な容量不足: 拒否成功。

## サイズと性能

| Firmware | Flash | 静的SRAM | SRAM＋stack予算512B |
|---|---:|---:|---:|
| 既存XOR診断版 | 3148 B | 12 B | 524 B |
| 学習XOR本番版 | 1500 B | 16 B | 528 B |
| 学習XOR診断版＋probe | 4188 B | 24 B | 536 B |

全てV003の16KB/2KB以内。Flash末尾予約64Bを別途考慮。[メモリ予算](memory-budget.md)にsectionとstackの扱いを記載。

補助的なLLVM symbol検査で、本番版Denseは350B、64bit software multiply helper `__muldi3` は182B。診断版では一般requantize本体210Bと同helperを確認した。Denseにはdot product等も含まれ、この数字をint64再量子化だけの純増と扱わない。float演算helperは観測されず、ホスト学習器はファームウェアに含まれない。

診断版に64回のint64 requantizeとint32 saturationのSysTick計測probeを追加。volatile入力・係数・compiler barrierを使用し、loop/読出しoverhead込みraw cycleを出力する。固定条件のchecksum期待値は-2048/-8192。これは異なる演算の参考比較で、同一スケールの等価カーネルの速度比較ではない。

**実機は使用していない。実機の推論成功、ホストとの実機一致、cycle数、ms、stack high-waterは全て未検証。** USB列挙で利用可能なWCH接続を確認できなかった。cross-build成功を実機成功として扱わない。次回はSWIOで全4入力とprobe checksumを照合し、core clock確認、timer overhead、複数回のmin/median/max、stack paintを測定する。

## 未完成・次の課題

学習CLIはXOR例。汎用データreader、最適化器の拡充、validation/held-out評価、入力正規化のexport、per-channel scale、QAT、自動校正探索、実機flash自動化は未実装。既存metadataなし低レベルモデルの実数scale整合性は証明できない。新しい生成モデルはmetadataを必須で出力する。

floatベースの校正は量子化誤差の蓄積や未観測分布を保証しない。XOR以外は代表校正データと独立評価を用意する必要がある。MNIST、CNN、int4、CH32V006は後段階。まず実機のint64コストとstackを測定し、その結果を基に演算最適化へ進む。
