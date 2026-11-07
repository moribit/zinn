# Practicality phase report — 2026-11-07

Zig0.17.0/macOS arm64で実行。追加の必須ライブラリなし、vendored HAL未変更。Linux/macOS CIを拡張したが、この作業環境でのLinux実行・リモートCIは未確認。接続USBデバイスにWCH/UARTを確認できず、書き込み・実機実行は実施していない。

## 実装

- `src/budget.zig`：全PT_LOADのVMA/LMAを範囲全体で検査。Flash予約、RAM、alignment、file/memory長、重複、実行可能RAM、不正配置を拒否。`budget_tests`に境界・不正ELFを追加。
- `src/fit.zig`・`train.zig`・MNIST dataset/pipeline：固定validation分割、CE/精度のepoch曲線、学習率減衰、最良validation checkpoint保持、testの明示選択。保存形式v1は維持。
- `build_support/project.zig`・`build.zig`：addProject、共通train/evaluate/deploy/flash、学習キャッシュ分離、成果物・JSONレポート、外部パッケージ例。
- `protocol.zig`・`service.zig`・`targets/ch32v003_uart.zig`：固定バッファUART本番推論、CRC/長さ/model identity/timeout、全logit応答、差替え可能adapter。診断SWIO版は維持。
- `benchmark.zig`・`stack_audit.zig`・host tools：9回min/median/max、タイマー読出し補正、stack paint、任意の静的逆アセンブル解析、入力フレーム生成・ホストsimulation・応答照合。
- CI：Debug/ReleaseSafe、compile-fail、既存Golden、MLP/CNN×int8/int4診断＋UARTクロスビルド、simulation、容量超過拒否、外部Build API、比較用成果物保存。数値カーネルの仕様は変更していない。

## 分析とvalidation比較

[事前計画・最終構成固定](validation-plan.md)。train60,000の固定split_seed24301で55,000/5,000に分離。batch32、CE、SGD、学習率10epochごと×0.3、seed42。calibration1024はtraining partitionのみ。各行はvalidation最良epochのcheckpointを評価。公式testは比較・校正に使用しない。[学習曲線CSV](experiments/validation/)を保存。

| 構成 | epochs上限 | rate | f32 validation | int8 validation |
|---|---:|---:|---:|---:|
| MLP16 area | 10 | .05 | 92.60% | 92.50% |
| MLP16 area | 30 | .05 | 93.30% | 93.30% |
| MLP32 area | 20 | .05 | 94.78% | 94.60% |
| MLP32 area（主候補） | 20 | .1 | 95.36% | 95.14% |
| MLP32 nearest | 20 | .05 | 94.20% | 94.08% |
| CNN2 area | 20 | .05 | 93.10% | 93.10% |
| CNN4 area | 20 | .05 | 96.32% | 96.32% |
| MLP32 area seed43（別反復） | 20 | .1 | 96.24% | 96.16% |

小さい幅と学習条件がf32段階の主な制約だったと推定できる。MLP16のepoch延長より幅32とrate.1が有効で、nearestはareaより低かった。CNNのchannel2→4でf32が3.22ポイント上昇。ただし同一split、seed2件のみで統計的有意性・一般的優位性を主張しない。seed43をtestで選別せず、主候補seed42を固定。

主MLPのcalibration256/1024/4096ではint8 validation95.22/95.14/95.14%、最大logit誤差2.072/1.245/.640。int4の1024/4096は93.58/93.46%、最大誤差6.307。少数件の精度差より一貫した1024設定を採用。per-channel/QAT/clipping探索は未実装。int4低下は量子化段階に残る。

## 固定後の公式test・本番ELF

公式10,000件。MLP32はrate.1/最大20epochの最良epoch13、CNN4はrate.05/最大20epochの最良epoch19。いずれもseed42/area。int8/int4は同じfloat checkpoint、calibration1024。MLP f32=96.62%、CNN f32=97.06%。[機械可読モデル・容量レポート](experiments/final/)を保存。

| 本番UART版 | test精度 | パラメータB | Flash B | 静的RAM B | workspace B | 静的stack推定B | 512B予算後RAM余裕B |
|---|---:|---:|---:|---:|---:|---:|---:|
| MLP32 int8 | **96.59%** | 8680 | 12408 | 460 | 32 | 252 | 1076 |
| MLP32 int4 | 94.90% | 4424 | 8184 | 460 | 32 | 256 | 1076 |
| CNN4 int8 | 97.07% | 2052 | 6436 | 1408 | 980 | 224 | 128 |
| CNN4 int4 | 95.21% | 1054 | 5496 | 1408 | 980 | 224 | 128 |

パラメータはweight+bias配列で、Flash全体にはstartup/runtime/整数演算helper/UART/CRC/benchmark/metadata等も含む。Flash16,384Bのうち64BはHAL予約（検査上限16,320B）。静的RAMはreceiver/input/workspace/output/tx/samples/HAL等込み。stack512Bは独立予算で、静的推定はnormal call pathのみ・IRQ除外。実測high-waterではない。CNN4の128B余裕ではアプリ追加を無条件に許容できず、既定CNN2は変更していない。MLPも既定幅16を維持し幅32を明示選択する。

前フェーズ（全train60,000、10epoch、validationなし）のtestはMLP16 int8/int4=94.23/93.27%、CNN2=93.09/90.74%。今回は幅・学習率・学習期間・分割が異なるため、単一要因の改善値としては比較しない。MLP int8の95%目標は達成、int4は未達。50ms目標は未検証。

## 再現

```sh
ZIG=/path/to/zig-0.17.0 sh tools/validation-study.sh /path/to/mnist
zig build deploy infer-host simulate-uart -Dproject=mnist -Ddata-dir=/path/to/mnist \
  -Dproject-checkpoint=zig-out/models/val-mlp32-lr1-e20-s42.zinn \
  -Dmnist-hidden=32 -Dapp-name=final-mlp-int8 -Devaluation-split=test -Drequest=benchmark
```

CNNはcheckpointをval-cnn4-e20-s42.zinn、`-Dmnist-model=cnn -Dcnn-channels=4`に変更。int4は`-Dweight-format=int4`と別app-nameを使う。任意の`stack-audit -Dobjdump=/path/to/llvm-objdump`も実行した。変更のないformat切替ではfloat fittingがcachedになることをfixtureで確認。

## 検証範囲・残課題

ホストDebug/ReleaseSafeは各38/38単体テスト＋18件のcompile-fail検証を通過。既存XOR Golden4/4、学習済みXOR int8/int4全logit一致、外部CSVプロジェクトのtrain/evaluate/deploy/infer-host/simulate-uartを通過。合成IDXのMLP/CNN×int8/int4各16件について、専用診断経路と共通UART経路の参照照合・cross-buildを通過。意図的Flash1024B指定は予算検査で失敗した。既存XORのFlash/static RAMは手書き3148/12B、学習済み本番1508/16B、診断4188/24Bで維持。

全4構成の全test10,000件で、生成整数coreの全logitが独立int64/除算参照と完全一致。4構成のdeploy/infer-host/simulate-uart/stack-auditを実行し成功。UART simulationのサイクル値は人工clockで、性能値ではない。UART配線/受信/CRC recovery/実機logit/サイクル/min中央値max/stack watermarkを物理デバイスで検証する手順は[deployment](deployment.md)に記載。

実機未検証：電気的UART、推論成功、CPU時間、int64 helperのサイクル費用、int4 decodeの速度差、startupを含むstack最大値。堅牢なproduction運用にはtimeout値・通信再試行・アプリ全体の割込みstackを実機で決める必要がある。ホストresponse checkerは物理実行を証明しない。

次は実機で4構成を同一入力・同一clockで測定し、MLP int4精度とCNN RAM余裕の改善を評価する。per-channel/QAT、大規模探索、CH32V006はこの段階では未実装。保存形式v1では前処理・split設定をsidecarと共に保管する必要があり、自己記述形式の追加は将来のversioned拡張とする。
