# ロードマップ

- M1: int8推論コア、数値仕様、static shape/workspace、unit/golden/compile-fail検証を完了。
- M2: V003 Startup付きXORのクロスビルド、全体サイズ、静的stack確認を完了。実機推論、ホストとの実機一致、cycle/time、stack high-waterは未完了。
- M3: Pure Zig IDX reader、前処理、seed固定f32学習/逆伝播/更新、量子化export、独立した評価セットの精度測定。まずint8、次いでint4。入力16×16、256→16→10の候補から容量/精度を検証。95%、16KB、2KB、50msは未達成の目標。
- M4: 型番別V006 datasheet確認、必要なHAL追加を別責務で実施、同一モデルで結果/時間/容量/乗算差を比較。

今後の優先順は正確性→メモリ→コードサイズ→速度→API簡潔さ。Conv、packed int2/ternary、CPU最適化は上記の検証基盤を維持してから追加する。
