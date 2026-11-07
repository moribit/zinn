# 初期調査（2026-11-07）

## ch32fun_zig

対象: [MimocWorks/ch32fun_zig](https://github.com/MimocWorks/ch32fun_zig/tree/aa799feb7026e7769373e8cee9102ecbf28d7e3e)、commit `aa799feb7026e7769373e8cee9102ecbf28d7e3e`。以下はREADMEだけでなく当該ソースを読んで確認した。

| 項目 | 実装と制約 |
|---|---|
| 公開Build API | `ch32Target(b)`, `halModule(pkg)`, `addFirmware(b, dep, options)`。Optionsはname/root_source_file/optimize/linker_script/runtime。HALはappへ自動import |
| ターゲット | riscv32 generic_rv32、c/e追加、i除去、freestanding/eabi。V003のRV32EC。M乗算なし、必要な乗算はZig compiler-rt |
| リンカ | `src/runtime/linker.ld`。Flashは実行alias 0x0、16320B。末尾0x3fc0の64BはUSER_DATA。RAMは0x20000000から2048B |
| セクション | reset/vector/text/rodata→Flash、data→RAM（Flash LMA）、bss→RAM。stack_topはRAM末尾。上流スクリプト単体ではstack衝突assertなし |
| Startup | naked resetでgp/sp設定→bssゼロ→dataコピー→machine state/mtvec→HCLK SysTick有効→app.main。完全ベクタ39エントリ。MIEは無効で起動 |
| Runtime | `.ch32fun`を採用。`.application`は利用者が全初期化を所有するlegacy方式なので本サンプルでは使用しない |
| 時間 | `time.nowCycles()`はSysTick CNTのu32読み出し。差はwrapping減算。core clock設定に依存。48MHzなら約89秒以内の区間で使う。計測自体の読み出し等のoverhead込み |
| 出力 | `swio_log`をsmallでも明示有効化、init/waitForTerminal/info。上流READMEの `chzig minichlink -T` で検証。UART HALもあるが今回採用せず |
| ホストテスト | HALをimportしない独立root moduleとしてZinnをテストする。上流のdisplay testはZinnの前提にしない |
| V006 | 当該Build API/リンカ/レジスタはV003固定。CH32V006選択や別リンカは提供されない。名前だけ差し替えて動作を主張できない |

上流変更は不要。Zinnの責務はカーネル、形状/数値検証、モデル、workspace、検証。reset、clock、peripheral、ベクタはHALの責務。

この環境のZig 0.17.0では `zig fetch` と `zig build` のアーカイブ処理でハッシュ/ルート階層の不一致を観測した。ビルド時にネットワークを要求しない固定path依存を採用し、上流のsrc/build manifests/READMEを未改変で収録。上流にLICENSEファイルはないが、2026-11-07にプロジェクト所有者が自身の管理下であることを確認し、Zinnのpublicリポジトリへの同梱公開を許可した。ZinnのMITは上流へ適用しない。

## 先行実装

[BitNetMCU documentation](https://github.com/cpldcpu/BitNetMCU/blob/main/docs/documentation.md) / [README](https://github.com/cpldcpu/BitNetMCU/blob/main/readme.md) / [GPL-3.0](https://github.com/cpldcpu/BitNetMCU/blob/main/LICENSE)を確認。コードや重みはコピーしていない。

16×16入力、複数Dense層、低bit重みと活性、QATの組合せを検討している。重みを32bitワードへpacked exportし、活性バッファを節約。binary/ternary/2bit/4bit/8bitを比較し、乗算器のないCPUでは符号・shiftを使う方式もある。FP1.3.0は符号と2のべき指数で重みを表すため、通常の線形int4とは異なる。Zinnではまずint8の数値仕様と独立した参照一致を固める。小さい256→16→10モデルで同等精度になる根拠はなく、95%は学習後の評価が必要。

READMEの近年のCNN精度報告は4KB RAMの条件を含む。初期のV003/2KBの結果と混同しない。Python/PyTorchの学習・C export pipelineは採用せず、将来の学習/変換もZigで独立実装する。

[TFLite Micro](https://github.com/tensorflow/tflite-micro)（Apache-2.0）: [arena管理](https://github.com/tensorflow/tflite-micro/blob/main/docs/memory_management.md)のhead/temporary/tailとscratch寿命を参考にする。Zinnの初期Sequentialは2面固定配列で十分であり、interpreterやallocatorは持たない。

[CMSIS-NN](https://github.com/ARM-software/CMSIS-NN)（Apache-2.0）: int8カーネル、requantization、丸め設定の区別を参考にする。Arm向け最適化でありRV32ECへリンクしない。Zinnの丸め規則は別仕様で、bit互換を仮定しない。

他の極小事例 [BitNetPDK](https://github.com/cpldcpu/BitNetPDK) では8×8入力など問題を縮小している。異なる入力条件や精度の数字は直接比較しない。いずれもZinnへのソース移植はしていない。

## V006の次段階で確認する事項

[WCH公式製品ページ](https://www.wch.cn/products/CH32V006.html)と[公式データシート入口](https://www.wch.cn/downloads/CH32V006DS0_PDF.html)を参照先とする。型番を固定し、Flash/RAM構成、RV32EmCの乗算命令範囲、割込みABI、clock、GPIO/UART/SWIOのレジスタ差分をデータシート本文で確認してからHALを拡張する。今回はV006用コード・リンカ・容量の適合性を検証していない。
