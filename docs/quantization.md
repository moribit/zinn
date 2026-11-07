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

学習/変換時には実数scale比をこの整数表現へ近似する必要がある。変換ツールはまだなく、現在のXORは整数で手設計したモデル。非ゼロのスケール誤差や精度劣化を自動評価する機能はない。
