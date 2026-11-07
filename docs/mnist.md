# データ入力・MNIST・CNN・int4

## 利用手順

Zig 0.17.0のみで実行する。ダウンロードは明示操作で、通常のtest/XORにはネットワーク不要。

```sh
zig build mnist-download
zig build mnist-train mnist mnist-firmware
```

既定は `data/mnist` の公式gzip4ファイル、MLP 256→16→10、学習60,000件/10 epochs/seed42/mini-batch32/rate0.05。`mnist`は学習、checkpoint、train-only校正、held-out評価、Zig export、生成core全評価例の参照一致検査までを実行する。`mnist-firmware`はCH32V003診断ELFの生成と最終容量検査。

```sh
zig build mnist mnist-firmware -Dmnist-checkpoint=zig-out/models/mnist-mlp.zinn -Dweight-format=int4
zig build mnist-train mnist mnist-firmware -Dmnist-model=cnn
zig build mnist mnist-firmware -Dmnist-model=cnn -Dmnist-checkpoint=zig-out/models/mnist-cnn.zinn -Dweight-format=int4
```

`-Ddata-dir=/path/to/mnist`、`-Dtrain-limit`、`-Dtest-limit`、`-Dcalibration-limit`、`-Dmnist-epochs`、`-Dbatch-size`、`-Dlearning-rate`、`-Dseed`を指定できる。既定校正数1024、既定test数10000。limitを小さくした値を全データ精度として報告しない。

出力は `zig-out/models/mnist-{mlp|cnn}.zinn`、`mnist-{mlp|cnn}-{int8|int4}.zig`、`*-report.txt`、明示train時の`*-training.txt`。ELFは `zig-out/bin/zinn-mnist-{mlp|cnn}-{int8|int4}`。checkpointはfloatなのでint8/int4で共通。firmwareは先頭test画像の符号化済み入力をFlashに持ち、SWIOでreference_ok/class/cyclesを出す。生画像の取込み・前処理はこのfirmwareでは実装していない。

モデル/データ/ELFはgitignore対象であり、ビルドから再生成する。`mnist-firmware`は物理flashしない。実機の動作/速度は未検証。

## 共通画像定義

```zig
const Structure = zinn.ImageDefinition(.{ .height=16, .width=16, .channels=1 }, &.{
    .{ .kind=.conv2d, .units=2, .kernel=3, .activation=.relu },
    .{ .kind=.average_pool2d, .kernel=2, .stride=2 },
    .{ .units=10 },
});
```

Conv出力は14×14×2、pool出力は7×7×2。DenseはHWC配列をそのままflattenする。Convはsquare kernel/stride/symmetric padding、標準Convのみ（depthwise/group/dilationなし）。poolはvalid、channel維持、同じactivation scaleを維持。comptime shape、接続時の空間shape、weights/bias、int32安全性を検証する。

学習は同じDefinitionでConv/pool/Denseのforward/backpropを行う。共有フィルタの勾配は全空間位置で加算し、poolの勾配は面積で配分。分類では安定化したsoftmax cross entropyを利用し、最終層をlogits（activation none）にする。既存TrainerのMSE/trainEpochは維持する。`epochs`というcheckpoint fieldは既存互換のためoptimizer update数であり、学習データを何巡したかはtraining logに記録する。

## 汎用CSV入力

```sh
zig build data-train -Dfeatures=2 -Dclasses=2 -Dhidden=8 -Dcsv-epochs=2000 \
  -Dcsv-train=examples/data_classifier/train.csv \
  -Dcsv-test=examples/data_classifier/test.csv -Dweight-format=int4
```

1行=`class_index,feature0,...`、0始まりclass、finiteなf32を受け付ける。空白/CRLF/空行は許容。列数違い、欠損、範囲外label、NaN/Infは拒否。引用符や埋込改行のCSVは対象外として明示的に拒否。headerがある場合は`-Dcsv-header=true`。正規化は呼出し側で固定し、学習/校正/本番で同じ処理を使う。

ライブラリAPIは `zinn.data.csv(TrainerType, allocator, bytes, header)`。ファイルIOとallocatorはホストだけ。CLIはtrain CSVで学習/校正、test CSVでfloat/int評価、checkpoint/source生成、生成coreと独立参照の先頭16件以内の一致検証を行う。出力はmodels/classifier.zinn/classifier.zig。例のCSVはXOR真理値表のfixtureで、未知データに対する汎化精度の評価ではない。

## MNISTの検証と前処理

データは [CVDF公式ミラー](https://github.com/cvdfoundation/mnist) のtrain/t10k IDXを使う。ダウンロード先は `https://storage.googleapis.com/cvdf-datasets/mnist/` の4ファイル。IDXのbig-endian magic/count/shape/正確なpayload長、画像label件数、全label 0..9を検証。gzipはZig標準ライブラリで展開し、CRC32/展開長/上限/末尾データも検証する。raw IDXもdata APIで読めるが、Buildの既定ファイル名は.gz。

前処理は28×28→16×16の面積平均と/255。整数グリッドでoverlap面積を求め、0..1へ正規化する。classはone-hot。trainだけを固定seedでshuffleし、mini-batch SGDで更新。校正はtrainファイルの先頭1024件。testは学習・校正・モデル選択に使わない。このフェーズのパラメータ設定を固定して評価し、test精度を見ながら最適化する探索は実施していない。

`mnist`はcheckpointを読み直し、train校正から独立int64/除算参照を再構築して、生成coreを全test件数で比較する。float/量子化精度だけでなく、各logitの完全一致を検査する。

## オフラインCI

```sh
zig build mnist mnist-firmware -Dmnist-fixture=true -Dmnist-epochs=1 -Dmnist-model=cnn -Dweight-format=int4
```

合成IDX/gzip（train32、test16）をPure Zigで生成し、読込/学習/export/整数一致/cross-buildの統合を検証する。MLP/CNN×int8/int4の4構成をCIに追加。合成データの値はMNIST精度ではない。fixture生成物は `mnist-fixture-*` という別名で保存し、実データのcheckpoint/report/ELFを上書きしない。

既知の制限と実データの結果は[検証レポート](mnist-report.md)を参照。
