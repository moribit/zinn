# アーキテクチャ

`src/`はMCU非依存。HAL importはfirmwareだけ。`ch32fun_zig`のaddFirmware/ch32Target/Startupを未改変で利用する。

| 層 | 役割 |
|---|---|
| Definition | 入力/各層の形状、Dense/Conv2D/AveragePool、activation、parameter layout、schema tag |
| Trainer | 同じ定義を使うホストf32 Dense/Conv/Pool、MSE/softmax CE、backprop/SGD、評価、checkpoint |
| export_model.Quantized | 代表入力校正、対称int8/int4化、整数係数計算、Zigソース生成 |
| Dense / Sequential | 従来の低レベルAPI＋Conv/Pool、comptime検証、ヒープなし整数実行 |
| budget | モデル見積りと最終ELFのターゲット容量検査 |

Trainer/exportのコードは遅延解析され、推論ファームウェアから呼ばれない。生成ソースのscale metadataはcomptime専用。推論でf32を計算せず、外部Cライブラリも使わない。

Tensorは空shape・ゼロサイズ次元・要素数乗算overflowを拒否する固定配列。Denseはoutput-major weightsとint32 bias、正しい配列長、int32累積安全性、quantizationを検証する。Sequentialはshape、zero point、指定されたscaleの接続を検証する。実数scaleなしのlegacy同士は従来動作を維持し、metadata付きとの混在は拒否する。

## ワークスペース

2層以上では入力を直接最初のDenseへ渡し、最後のDenseは直接outputへ書く。中間出力について偶数・奇数層ごとの最大幅を計算し、必要な2配列だけを確保する。2層なら中間1面だけ。元のXORは4B→2B、学習XORは旧方式16B相当→8B。入力幅は中間バッファサイズに影響しない。

単層の場合は入出力の重なりをアドレスで検出し、alias時のみworkspaceへ入力を退避する。alias保証のためinput_lenの領域を確保する。複数層も入力を使い終わってから出力へ書くため、従来の入出力aliasを維持する。入力/出力とworkspaceの重複、同じworkspaceの同時利用は禁止。Workspace内部のフィールドではなく型とworkspace_bytesを利用する。

モデルにはGraph interpreter、allocator、実行時shape、仮想呼び出しを持たせない。レイヤー呼び出しだけを展開し、ニューロンループは通常のループ。未使用演算は遅延解析とリンカGCで除去。定数はFlashのrodata、累積は1個のint32で、中間int32テンソルを持たない。

ImageDefinitionのHWC shapeを学習・量子化・生成で共有する。Conv/Poolは直接演算しim2col bufferを確保しない。int4はFlash上のpacked重みを演算時にdecodeし、workspaceはint8のまま。既存Dense定義のcheckpoint IDは維持し、画像定義には空間shape/演算属性を追加して誤ロードを拒否する。
