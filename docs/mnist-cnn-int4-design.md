# 汎用データ・MNIST・CNN・int4の設計

既存Dense定義/API/checkpoint/XORを維持し、DefinitionをDense/Conv2D/AveragePool2Dへ拡張する。ImageDefinition(HWC shape, layers)で画像構造を明示し、学習・校正・整数exportで同じshape/重みlayoutを共有する。Convは正方kernel、stride、対称zero padding。フィルタlayoutは[output channel][kernel y][kernel x][input channel]。poolはvalid averageで、flattenはDense接続時のHWC順序そのものとする。

ホストTrainerにはConv/poolの順伝播・逆伝播、分類用softmax cross entropy、mini-batch学習を追加する。既定MSEを維持する。Dense-onlyのschema tagとcheckpoint v1を維持し、画像構造にはshapeと演算属性を加えて不一致を拒否する。

汎用データAPIはCSV（label + 数値features、引用/欠損なしの明示的subset）とIDX画像/ラベルを厳密に検証する。MNISTのgzipはZig標準ライブラリで展開。28×28→16×16は決定的な面積平均、0..1正規化。学習splitだけを更新/校正に使い、test splitは独立評価に限定する。データをリポジトリへ同梱せず、ダウンロードを明示操作にする。

int4は符号付きtwo's complement nibble、先頭weightを下位nibbleへ格納、奇数末尾の上位nibbleは0。推論coreは-8..7対応、exportは対称-7..7。重みだけpackedでactivationはint8、累積int32。Dense/Conv共にdecode-on-useで、展開用RAMを確保しない。既存int8 APIと丸め仕様は維持する。

MNIST MLPは256→16→10、CNNは16×16×1→Conv3×3(2ch)→AvgPool2×2→Dense10を初期例とする。精度/サイズを実測し、95%や50msを達成したとは仮定しない。int8/int4生成コードをホストの独立参照と比較し、V003へcross-buildして最終ELFを検査する。実機未接続時はcycle/動作成功を主張しない。
