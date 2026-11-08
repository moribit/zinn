# メモリ予算（過去の設計・検証記録）

> Historical/design notes. Current English contract: [budgets](api/budgets.md); representative ELF/stack evidence: [benchmarks](benchmarks.md). Allowances are not hardware measurements.

CNN/MNISTの4構成は[MNIST検証レポート](mnist-report.md)を参照。

Zig 0.17.0 / small / RV32EC、CH32V003向け。`zig build size` の最終ELF計測値。

| Firmware | Flash | 静的SRAM | workspace（SRAMに含む） | SRAM＋stack予算512B |
|---|---:|---:|---:|---:|
| 既存手書きXOR診断版 | 3148 B | 12 B | 2 B | 524 B |
| 学習XOR本番版 | 1508 B | 16 B | 8 B | 528 B |
| 学習XOR診断版（quant probe込み） | 4188 B | 24 B | 8 B | 536 B |

Flash物理容量16384BのうちHALが末尾64Bを予約し、ロード可能容量は16320B。RAMは2048B。全版が予算内。旧手書きXORは初期baselineの3172Bから24B減、静的RAMは12Bで同じ。workspaceは4→2Bだが、セクションの4B alignmentにより最終RAMが2B減るとは限らない。

学習モデルはint8 weights32B＋bias40B＝parameter_bytes72B、input/output各2B。診断版のdata8Bはprobe値と係数、bss16Bはworkspace/入出力/HAL状態。全体にはStartup、vector table156B、runtime、compiler-rt、ログ（診断版のみ）が含まれる。

## 検査

`Model.parameter_bytes/activation_bytes/checkBudget(Target)` はモデル単体の概算。生成モデルのファームウェアでcomptime検査する。最終ELF検査はPure ZigのPT_LOAD parserを用い、Flashはphysical address＋file sizeの最大到達位置、RAMはvirtual address＋memory sizeの最大到達位置で計算する。配置の隙間、dataのFlash LMA、bssも含め、debug sectionやELFファイルサイズを容量と誤認しない。

`zig build size` は既定でV003予算を検査する。`-Dflash-bytes/-Dram-bytes/-Dstack-bytes/-Dreserved-flash-bytes` は検査値だけを変更する。`budget.Target`自体はFlash/RAM originも指定可能。V006など別MCUのHAL対応を意味しない。

容量超過時はFlashBudgetExceeded/SramBudgetExceededと使用量を報告し失敗する。モデル単体の超過は分かりやすいcompile error。意図的なFlash=1024Bで拒否を検証した。CIは明示的なbash/pipefailでteeの上流失敗を保持する。毎回レポート/ELF/binary/checkpoint/生成Zigをartifactへ保存し、継続比較する。

## スタック

512Bは許容量であり、実機high-waterの測定値ではない。現在のELFを補助的にLLVM逆アセンブルして通常経路を確認した。

本番版: startup C=4B、runtime main=4B、app=28B、Dense=60B、muldi3=48B、mulsi3=0B。最大call chainの静的見積り144B。診断版はapp=80B、Dense=60B、requant=20B、probe=40B、SWIO writeUnsigned=48B、writeAll=12B、muldi3=48B、udivmod=52B、divwide=44B。startup/runtimeを加え、相互排他的な呼出しも全て加算した保守的上限412Bで512B以内。

今回のサンプルは割込みを有効化しない。HALのIRQ入口には各64B frameがあるため、有効化・ネスト・モデル・コンパイラ変更時は再計算する。再帰・動的stack配列は使わない。実機stack paint/high-waterは未実施であり、一般のユーザーモデルへ上記値を適用できない。
