# 初期検証レポート（過去のbaseline）

現行の結果と変更点は[次フェーズ検証レポート](next-phase-report.md)を参照。以下の値は初期コミット時点の記録。

環境: 2026-11-07、macOS aarch64、`zig version` = 0.17.0。ローカルで確認。GitHub Actionsの実行結果はまだない。

## Milestone 1

実装: int8 Dense/int32累積、ReLU、再量子化、Argmax、Tensor、comptime Dense/Sequential、2面workspace。全てPure Zig。

`zig build test --summary all`: 7/7テスト成功（rootのimport testを含む）。`-Doptimize=safe`も7/7成功。さらに期待した診断で失敗するcompile-fail 5ケースに成功: 重みshape、int32 overflow、multiplier=0、層間shape、層間zero point。

数値テストは正負の半端値、int32両端からの再量子化、最大multiplier、shift=31、飽和、非ゼロzero point、ReLU、Argmaxの同値/空を確認。再量子化は8 shifts × 2001 inputsを独立した除算式と比較。Denseはseed=42の256入力でint64参照累積・除算式と一致。多層XORの全4入力、workspace再利用、幅の変わる層、入出力aliasも確認。

`zig build xor`: 4/4 golden vector一致、workspace=4B。出力logitsは00→[1,0]、01→[0,1]、10→[0,1]、11→[1,0]。実機も同じmodel.zigを使用する。

`zig build benchmark`: fast最適化、100,000回、208,375ns合計、整数表示2ns/推論、checksum=50,000（単回観測）。volatile入力書き込み/出力読み出しを含む。非常に小さいホスト向けに最適化されたモデルの参考値であり、MCU性能や一般Dense性能を表さない。測定値にはループ・入力選択・checksum・timerのoverheadを含み、繰返しで変動する。

制限: int8/per-tensorのみ。i64再量子化のソフトウェア演算はモデル次第でサイズ/時間を増やす。スケール互換性は利用者責任。モデルexport、学習、MNIST精度は未評価。

## Milestone 2（実機なしの範囲）

`zig build firmware`: RV32EC/freestanding/eabi small、Startup/vector/HAL込みELF成功。`zig build size`: Flash=3172B、static RAM=12B、stack allowance=512B、RAM予算合計524B。詳細と静的stack見積りは [memory-budget.md](memory-budget.md)。再ビルド時はこのコマンドの最新値を正とする。

実機は使用していない。推論成功、ホストとの実機一致、実測Flash書き込み、stack high-water、MCU cycle数、推論msは未検証。クロスビルドの成功を実機動作の成功として扱わない。

## 実機で次に行う手順

1. ELFをZig objcopy等でbinaryへ変換して、上流ch32fun_zigのWCH-LinkE/SWIO手順で書き込む。今回書き込みは行っていない。
2. `chzig minichlink -T` を起動。smallでもSWIO logging有効。端末接続までwaitForTerminalで待機する。
3. 全4行のlogitsと `ok=1` を照合する。`cycles` はSysTickのwrapping差分。compiler memory barrierで推論を計測区間内に保持する。割込みは有効化しない。
4. 48MHz設定を実機で確認して cycles/48000 をmsへ換算。空区間のread overheadを別途測り、複数回のmin/median/maxも記録する。今回のサンプルは各入力1回のみ。
5. stack watermarkを追加してStartup・推論・ログを含む最大値を確認する。割込みを有効化する場合は別予算にする。

次の課題は実機での再現性と計測。その後、int4とPure Zig学習/exportを段階追加する。
