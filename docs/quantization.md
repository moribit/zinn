# 数値仕様 v1

入力・重み・出力はint8全範囲。重みzero pointは0固定。入力zero point `zi`、出力zero point `zo` はint8。

```text
acc = bias[o] + sum((i32(input[i]) - zi) * i32(weight[o,i]))
y = clamp_i8(round_away_on_tie(acc * multiplier / 2^shift) + zo)
relu(y) = max(y, zo)
```

multiplierは1..65535、shiftは0..31。正のスケールのみ。biasは補正済み入力と重みの積と同じスケール。per-tensorのみ。`ReLU`は実数のゼロに相当するzoで下限を取る。TFLite/CMSISのQ31 multiplierや二段丸めとのbit互換性は主張しない。

Dense累積はint32で行う。comptimeで `abs(bias)+max(127-zi,128+zi)*sum(abs(w)) <= 2147483647` を各行に要求する。これにより途中の和も安全。境界は保守的で、例えばbias=-2147483648単独も拒否する。入力範囲を狭く仮定せず、オーバーフローはwrap/saturateで隠さない。

再量子化だけはi64中間積を用い、int32最小値もi64へ昇格してから絶対値を取る。最大の積と丸めoffsetを足してもi64範囲内。非負の絶対値にhalfを加え右シフトし、符号を戻す。負の算術右シフトの丸め方向に依存しない。例: +3/2→+2、-3/2→-2、-2/2→-1。shift=0ではhalf=0。最後にzoを加え[-128,127]へ飽和してからint8化する。

## Scale metadataと生成モデル

`Params`へoptionalなinput_scale/weight_scale/output_scaleを追加した。全て未指定ならlegacyの整数契約を維持する。一部だけの指定は拒否。指定する場合は正有限値を要求し、input_scale×weight_scale/output_scaleとmultiplier/2^shiftの相対誤差が1e-4以下か検査する。隣接するoutput_scale/input_scaleは完全一致を要求する。metadataのある層とない層の接続も拒否する。

係数の近似を許容する一方、接続scaleには許容誤差を設けない。exporterは前層のscaleをそのまま次層へ渡し、f32 bit patternをZigソースへ出す。利用者が手書きする場合も同じscale定数を共有する。

Pure Zigの校正/exportを追加し、XORを学習してint8モデルへ接続できる。対称zero=0、per-layer weight scaleとactivation scale、int32 bias、min/max校正。詳細は[workflow](workflow.md)。legacyモデルではscaleの情報自体がないので実数scale整合性を証明できない。生成モデルではmetadataを必ず付け、コンパイル時に検査する。


## Packed int4

Dense/Conv2Dの `format=.int4, packed_weights=&.{...}` を使用する。順序は既存int8と同じ、先頭weightを下位nibble、次を上位nibbleへ格納する。row境界でpaddingせず連続格納、奇数末尾の未使用上位nibbleは0を要求。two's complementで-8..7をdecodeする。exportは対称-7..7、weight_scale=max_abs/7を使用。activationはint8、bias/accumulatorはint32のまま。decode-on-useで展開バッファを持たない。

Convのweights layoutは[output channel][kernel y][kernel x][input channel]、activationはHWC。paddingは実数ゼロ（input_zero）に相当するためaccumulationをskipする。AveragePoolはsum(input-zero)を面積でties-away-from-zeroへ丸め、zeroを戻す。poolのinput/output scaleは同じ値を継承し、独立したrequantization係数は持たない。
