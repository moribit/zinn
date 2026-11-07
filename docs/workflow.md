# 学習からデプロイまで

## 共通のモデル定義

`examples/xor/definition.zig` の `Structure = zinn.Definition(...)` がshape/activationを定義する。定義だけではパラメータを持たず、`zinn.Trainer(Structure)` にf32パラメータを生成する。`Sample` のinput/targetも定義から固定長配列になる。

`trainEpoch` はbatch MSEと全層逆伝播を計算し、batch平均勾配でSGDを1回更新する。初期化は固定LCGとseed、学習順序は固定。ReLUの微分は0以下で0。XORは2→8→2、seed=42、10,000 epochs、learning rate=0.05。seed=42の2→4→2では3/4に留まったため、8 hidden unitsに変更した。自動的なseed/architecture探索は行わない。

この節のCLIはXOR例。CSV/MNIST/CNN/int4の操作は[データ・MNIST手順](mnist.md)を参照。共通Definition、Trainer、QuantizedFormatはこれらにも使用する。

## 保存・再利用

```sh
zig build train
zig build eval -Dcheckpoint=zig-out/models/xor.zinn
zig build quantize -Dcheckpoint=zig-out/models/xor.zinn
zig build e2e -Dcheckpoint=zig-out/models/xor.zinn
zig build deploy -Dcheckpoint=zig-out/models/xor.zinn
```

checkpointを省略するとBuild graphが自動的に学習する。学習・量子化の出力はキャッシュされ、同じモデルをホストとファームウェアへ接続する。`train`と`quantize`だけでも生成物をzig-out/modelsへ保存する。

保存形式v1は32B header + パラメータ数×4B + 8B checksum。headerはmagic `ZINNf32` + version byte=1、schema tag（u64）、seed（u32）、epoch（u32）、予約8B。パラメータは層ごとoutput-major weights→bias、f32 bit patternのlittle endian。末尾checksumは先行全bytesのFNV-1a。schema tagは入力/各層幅/activationから計算する。float評価/再学習のcheckpointであり、マイコンにロードするモデルではない。

decodeは長さ・magic/version・schema・checksum・finiteを検査し、成功まで元モデルを変更しない。SGDにはmomentum状態やshuffle状態がないため、パラメータ/epochの復元で同条件の学習を再開できる。同じビルド・実行環境で再現性を検証済み。CPUや浮動小数点最適化の異なる環境間でのbyte完全一致は保証しない。

## 量子化と整数ソース

入力および各層出力の最大絶対値/127をactivation scaleとし、重みも層ごとの最大絶対値/127で量子化する。zero pointは0。ゼロだけのテンソルはscale=1/127。biasはinput_scale×weight_scale単位でint32化。`scale_ratio = input_scale*weight_scale/output_scale` をu16 multiplier / 2^shiftへ近似し、相対誤差1e-4以内で表現できなければ失敗する。丸めはties away from zero。

校正はfloatモデルの代表入力から行う単純なpost-training quantization。入力分布の外ではclipping/精度低下があり得る。XORでは全4入力を校正と正解確認に使う。未知データの評価と混同しない。

生成 `xor.zig` は通常の `zinn.Sequential(.{zinn.Dense(...)...})`、schema_tag、input_scale、XOR用入力/独立整数参照Goldenを含む。scale metadataはf32 bit patternを正確に保存する。ホスト側の参照はint64累積と除算式で実装し、生成ソースのcore実行とbit単位で比較する。

## ファームウェアと容量

`firmware-trained` は全4入力の結果、ok、SysTick cycle、および再量子化probeをSWIOへ出す。端末を待つ診断用。`firmware-production` は端末待ち・ログ・probeなし。exportされた `zinn_input` を読み、`zinn_output` を更新する最小組込入口。センサ接続や通信プロトコルはアプリケーションの責務。

`deploy` は本番ELFとflashable binaryを生成し、その最終ELFの容量を検査する。**ハードウェアへの自動書込みは行わない**。物理flashはHAL上流のWCH-LinkE/SWIO手順を使う。Zinn側は未接続の実機を成功扱いしない。

```sh
zig build size
zig build size -Dflash-bytes=16384 -Dram-bytes=2048 -Dstack-bytes=512
```

`Model.parameter_bytes` は重みとbiasの見積り、`activation_bytes` は入出力＋workspace。`comptime { Model.checkBudget(.{}); }` でモデル単体を検査できる。最終ELF検査にはStartup、HAL、compiler-rt、ログも含まれ、配置の隙間とdataのFlash初期値も数える。モデルだけのチェックに合格しても最終ELFが収まる保証はない。

`budget.Target` にはFlash/RAMのoriginとbytes、reserved Flash、stack allowanceがある。現在のファームウェア構成はV003だけ。別容量のCLI指定は検査予算の変更であり、別MCUを動作させる機能ではない。
