#!/usr/bin/env bash
# Offline integration: actual cached Build Runs, not a renderer simulation.
set -euo pipefail
zig_bin="${1:-zig}"
result_dir="${2:-$(mktemp -d)}"
mkdir -p "$result_dir"
name="progress-cli-$$"
common=(train -Dproject=mnist -Dmnist-fixture=true -Dmnist-epochs=2 "-Dapp-name=$name" --prefix "$result_dir/out")
"$zig_bin" build "${common[@]}" -Dprogress=plain > "$result_dir/plain.stdout" 2> "$result_dir/plain.log"
grep -q "completed $name" "$result_dir/plain.log"
grep -q 'epoch=1 epochs=2' "$result_dir/plain.log"
cp "$result_dir/out/training/$name.zinn" "$result_dir/expected.zinn"
cp "$result_dir/out/reports/$name-training.csv" "$result_dir/expected.csv"
cp "$result_dir/out/reports/$name-training-receipt.txt" "$result_dir/expected.receipt"
"$zig_bin" build "${common[@]}" -Dprogress=plain > "$result_dir/cached.stdout" 2> "$result_dir/cached.log"
grep -q "cached $name" "$result_dir/cached.log"
if grep -q '^epoch ' "$result_dir/cached.log"; then echo 'Cached execution replayed stale epochs'; exit 1; fi
cmp "$result_dir/expected.receipt" "$result_dir/out/reports/$name-training-receipt.txt"
for mode in auto off; do
    CI=true TERM=dumb LC_ALL=C "$zig_bin" build "${common[@]}" "-Dprogress=$mode" > "$result_dir/$mode.stdout" 2> "$result_dir/$mode.log"
    cmp "$result_dir/expected.zinn" "$result_dir/out/training/$name.zinn"
    cmp "$result_dir/expected.csv" "$result_dir/out/reports/$name-training.csv"
    cmp "$result_dir/plain.stdout" "$result_dir/$mode.stdout"
done
test ! -s "$result_dir/off.log"
test -s "$result_dir/auto.log"
if LC_ALL=C grep -q $'\033' "$result_dir/auto.log"; then echo 'ANSI escape in CI output'; exit 1; fi
if "$zig_bin" build train -Dproject=mnist -Dmnist-fixture=true -Dmnist-epochs=0 "-Dapp-name=$name" --prefix "$result_dir/out" -Dprogress=plain > "$result_dir/failed.stdout" 2> "$result_dir/failed.log"; then
    echo 'Invalid training unexpectedly succeeded'; exit 1
fi
if grep -q "cached $name" "$result_dir/failed.log"; then echo 'Failed training reported cached'; exit 1; fi
grep -q 'InvalidTrainingOptions' "$result_dir/failed.log"
echo "Progress CLI: plain/live, cached, auto/CI, off; identical checkpoint/CSV/stdout ($result_dir)"
