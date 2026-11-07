# Quality review / Milestone 1

数値仕様、既存低レベルAPI、checkpoint v1は維持。Dense/Conv/Pool、signed int4、全入力範囲でのint32安全性、int64丸め/飽和、zero/scale、HWC/stride/paddingをレビューした。新たに空間index helperを共有しない独立HWC oracleで128入力×12 logitsをint8/int4と照合する。

ELF検査には開始位置だけを判定する不足があり、修正した。PT_LOADのvirtual memory span全体、Flash LMA全体、reserved Flash、RAM、zero fill、alignment、virtual/load overlap、実行可能RAM、write+execute、invalid target rangeを拒否する。実際のサイズ算出は配置の隙間も含む。単体テストで境界を跨ぐ配置を検証する。

容量レポートはreports/*-memory.json（schema_version=1）とhuman-readable textを保存。static_ram/stack_allowance/marginを分離しhardware_measured=falseを付す。512Bは許容量であり実測ではない。

optional `stack-audit -Dobjdump=/path/to/llvm-objdump` は最終ELFのdisassemblyから通常経路のstatic SP調整と直接callを集計する。未解決callee、間接call、dynamic SP、recursive graphが通常経路にあればunknownとして失敗させる。割込み/NMIと動的制御の一般的証明は対象外。過大評価を許す保守的なcall-chain見積りであり実機high-waterではない。LLVMはこの補助auditだけの任意ツールで、test/core/firmwareの必須依存にはしない。

CIはLinux/macOS、Debug/Safe、compile-fail、MLP/CNN×int8/int4、全fixture logit一致、cross-build、capacity rejectionを維持。test textとmemory JSON、学習/精度レポートをartifactへ保存する。これ以降の変更も同じ検証へ接続する。
