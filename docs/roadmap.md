# ロードマップ

> Historical planning notes; some milestones below are now implemented. Current status and verification boundaries are in the [README](../README.md).

- 実装済み: int8/int4 Dense、Conv2D、AveragePool、静的workspace、shape/scale/overflow検証。
- 実装済み: 共通Definition/ImageDefinition、Pure Zig f32学習/MSE/softmax CE/SGD、checkpoint、CSV/IDX/gzip、MNIST前処理、量子化/export。
- 検証済み: XOR、MNIST MLP/CNN×int8/int4、独立参照一致、V003 cross-buildと容量検査、オフラインfixture CI設定。
- 未達: MNIST 95%（今回MLP int8=94.23%）、実機50ms、実機stack/結果一致。
- 次: trainからvalidationを分離し、モデル容量と最適化の不足を分析。実機でpacked decode/int64 requantizeのcycle/stackを測定する。
- 将来: per-channel/QAT、Depthwise、int2/ternary、streaming dataset、V006型番別HAL/容量/乗算比較。

速度だけでなく正確性、メモリ、コードサイズ、再現性を優先する。
