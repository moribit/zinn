# MNIST・CNN・int4検証レポート

2026-11-07、macOS aarch64、Zig 0.17.0、hostはsafe、firmwareはsmall/RV32EC。実データを実際にダウンロードして学習・評価した。Python等の外部ML環境は使用していない。

## 固定した条件

公式train60,000件を10 epochs、seed42、mini-batch32、SGD rate0.05、softmax cross entropy。28×28→16×16 area resize、/255。校正はtrain先頭1024件。独立test10,000件で評価。MLP=256→16(ReLU)→10、CNN=Conv3×3/2ch(ReLU)→AvgPool2/stride2→Dense10。testに合わせたarchitecture/seed/epoch探索はしない。

| モデル | float正解/10000 | int8正解/10000 | int4正解/10000 |
|---|---:|---:|---:|
| MLP | 9428 (94.28%) | 9423 (94.23%) | 9327 (93.27%) |
| CNN | 9307 (93.07%) | 9309 (93.09%) | 9074 (90.74%) |

int8/int4の各4構成で、生成されたcoreと独立int64累積/除算参照が**test全10,000件の全logitで完全一致**した。先頭16件のGoldenも生成物へ含める。これは実機での一致検証ではない。

95%以上の目標には未達。MLPはfloatの時点で94.28%なので、主要課題はfloatモデル/学習設定の段階にあると推測できる。capacity不足と10 epochsの最適化不足の切分けには、trainからvalidationを分離した追加実験が必要。int8化の損失はMLPで0.05ポイント。int4化ではMLPがfloat比1.01ポイント、CNNが2.33ポイント低下し、単純per-tensor min/max PTQの限界を観測した。QAT/per-channel/validationによる検討は未実装。

最大logit誤差（dequantized対float）はMLP int8=3.914845/int4=5.371709、CNN int8/int4=4.668995。平均精度だけでは一部のclipping/外れ値を見落とすため、この値もreportに保存する。

## V003診断版の最終ELF

| モデル | format | weights+bias | workspace | Flash | 静的SRAM | SRAM+stack allowance512B |
|---|---|---:|---:|---:|---:|---:|
| MLP | int8 | 4360 B | 16 B | 7980 B | 288 B | 800 B |
| MLP | int4 | 2232 B | 16 B | 5880 B | 288 B | 800 B |
| CNN | int8 | 1046 B | 490 B | 5012 B | 760 B | 1272 B |
| CNN | int4 | 547 B | 490 B | 4564 B | 760 B | 1272 B |

Startup、vectors、HAL、compiler-rt、SWIO、最初のtest入力/参照結果を含む。Flashは16KB中64B予約を考慮。packed int4は展開用RAM不要で、activationはint8のままなのでSRAMは減らない。モデルのweight削減量がそのままFlash削減量にはならず、decodeコード等も含まれる。

実機の推論成功、cycle/ms、stack high-waterは未検証。512Bはスタックの予算であり、実測最大値ではない。50ms目標の達成を主張しない。SWIOのcycles計測を次の実機確認で使う。

## 回帰・入力検査

Debug/SafeともUnit/Golden 25/25成功、compile-fail 18ケース成功。さらに、CNN全パラメータの有限差分勾配、large logitsの安定CE、不正targetによる無更新、HWC/stride/padding/zero point、poolの負数tie、int4全16符号値/奇数末尾、CSV、IDX、gzip CRC/size/展開上限/末尾データを検証。shape/overflow/int4 padding/scale等のcompile-failも維持・追加した。

既存手書きXORのlogits/Flash3148B/SRAM12B/workspace2Bを維持。学習XORもint8/int4全4入力で参照一致。本番学習XORのFlashは前フェーズ1500Bから1508Bへ8B増加（int4対応後のコード生成差）、SRAM16Bは不変。診断版4188B/SRAM24Bも予算内。

CIはオフライン合成IDXで4構成を実行する。今回の変更のGitHubリモートCIは未実行。ローカルの実データ評価と合成fixtureの検証を区別する。

## 残る制限

Dense/標準Conv2D/valid AveragePoolのみ。Depthwise、groups、dilation、max pool、per-channel、QAT、自動量子化探索、MNIST用の本番入力転送、生画像のMCU前処理、CH32V006は未実装。CSVは引用符のないsubsetで、時系列/ストリーミングは未対応。データはホストで上限付きメモリ読込し、超大規模学習にはstreaming/batchingのIO改善が必要。

次はvalidation splitを用いた学習分析と、実機でのint4 decode/int64 requantizeのcycle・stack測定。容量達成を理由に精度/時間達成を推定しない。
