# メモリ予算

Zig 0.17.0 / small / RV32EC。`zig build size` はPure ZigのELF32 section parserでALLOCセクションを集計する。FlashはNOBITSを除きdata初期値も加える。RAMはRAM領域のALLOC（data/bss）を加える。debug情報やELFファイル自体のサイズをFlashと誤認しない。

| 項目 | 初期XOR実測 |
|---|---:|
| reset | 20 B |
| vectors | 156 B |
| text + rodata（モデル・runtime・SWIO込み） | 2996 B |
| data / Flash初期値 | 0 B |
| bss（HAL状態含む） | 12 B |
| Flash合計 | 3172 / 16320 B |
| HAL予約USER_DATA | 64 B |
| モデルworkspace（bssに含む） | 4 B |
| スタック予算 | 512 B |
| 静的RAM + スタック予算 | 524 / 2048 B |

RAM input/outputは各2B。コンパイラのalias/lifetime最適化があるため、単純な宣言サイズ合計とELFのbssは必ずしも一致しない。重み8Bとbias16BはFlash。Flashにはsoftware multiplyやSWIO整数フォーマットのcompiler-rtも含まれる。

`zig build size` は16320B Flash / (2048-512)B静的RAMを超えたら失敗する。512Bは実測値ではなく、スタックの許容量。上流リンカのRAM/Flash領域チェックに加えて予算を確認する。

## スタックの静的確認

今回のELFをLLVM objdumpで確認（補助検証のみ。ビルド必須依存ではない）。debug symbolsを残してもロード対象サイズは不変。

| 関数 | frame B |
|---|---:|
| reset C / runtime main | 各4 |
| app main | 72 |
| Dense | 36 |
| SWIO writeAll / writeUnsigned | 12 / 48 |
| compiler-rt muldi3 / udivmoddi4 / divwide | 48 / 52 / 44 |

通常経路で到達する上表の全フレームを合計した保守的上限320B（相互排他的な呼び出しも加算）。推論経路は4+4+72+36=116B、mulsi3はフレーム0。再帰・動的フレームなし。通常経路の320Bは512B以内。これはこのELFの静的確認で、一般のモデルやコンパイラ版への保証ではない。

割込みはこのサンプルでは有効化しない。HALにあるIRQ入口はそれぞれ64Bを別途使う。割込み有効化、ネスト、別ログ処理、モデル変更時はcall chainを再調査する。実機のstack paint/high-water計測は未実施。ELF予算チェックだけでは実際のstack overflowを証明できない。

## 継続比較

初期baselineはFlash=3172、static RAM=12、workspace=4 B。CIで毎回 `size-report.txt` とELFを保存し、PR前後の差を比較できる。最大容量超過は自動失敗。baselineからの増分は設計判断のためレビューする。モデルだけでなくStartup/ログ込みの同条件で比較する。
