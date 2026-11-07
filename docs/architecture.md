# アーキテクチャ

## 境界

`src/` はMCU非依存。`examples/xor/firmware.zig` だけがHALをimportする。Buildは上流の `ch32Target` / `addFirmware` / `.ch32fun` runtimeを利用する。上流コードには変更を加えていない。

- `Tensor(T, dimensions)` は要素数を検証した固定配列。空形状・ゼロ次元・usize乗算オーバーフローを拒否する。
- `Dense(config)` は型を返す。配列長、量子化、全入力範囲でのint32安全性を検証。重みは `[output][input]` の連続int8、biasはint32でaccumulatorのスケール。
- `Sequential(.{ LayerTypes... })` は接続を検証し、レイヤー呼び出しだけをinline展開。ニューロンループは通常のループで、巨大なcomptime推論は行わない。
- `Workspace` は `2 * max(input_len, each output_len)` B。交互に書き込み、最後に出力へコピー。中間int32テンソルは不要、accumulatorは1個。
- Argmaxは同値なら最初のインデックス、空ならnull。Dense単体は寸法付き配列ポインタを受け取る。カーネルは内部実装で、モデルによる安全性証明を前提とする。

モデルには動的Graph、allocator、実行時shape情報、仮想呼び出しを持たせない。利用されない演算はZigの遅延解析とリンカGCで除去する。定数は通常 `.rodata` に配置され、HALリンカではFlashへ入る。全モデルをRAMにコピーしない。

## 所有権と拡張

入力と出力は相互にalias可能。両者ともworkspaceと重ねてはならない。Dense単体では入力と出力を重ねてはならない。workspaceは呼び出し側所有で再入可能性を明示し、推論コアにグローバル状態を置かない。

将来は同じ `input_len/output_len/input_zero/output_zero/run` 契約を満たす別のレイヤー型を追加できる。Convの多次元形状・scratchやpacked重みの契約はその時点で明示拡張する。int4/int2は重みの型とdecodeを分離し、int8の結果を参照にする。出力スケールは現在レイヤー固有で、接続する実数スケールの一致は利用者の責任（ゼロポイントだけを自動検証）。モデルエクスポート形式と学習器は未実装。

## コンパイル時間

重みを1回走査して各行の絶対値和を計算する。重みごとのコード生成やループ展開はしない。検証のbranch quotaは10,000,000に制限。巨大モデルはこの段階の対象外。
