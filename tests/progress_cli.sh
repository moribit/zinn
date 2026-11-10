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
journal=".zig-cache/zinn-progress/$name-training"
mkdir -p "$journal"
printf 'STALE_PROGRESS_MUST_NOT_REPLAY\n' > "$journal/live.log"
printf '{"kind":"failed","name":"STALE_PROGRESS_MUST_NOT_REPLAY"}\n' > "$journal/events.jsonl"
printf '00000000000000000000000000000000' > "$journal/session"
printf 'stale' > "$result_dir/out/reports/$name-training-receipt.txt"
"$zig_bin" build "${common[@]}" -Dprogress=plain > "$result_dir/cached.stdout" 2> "$result_dir/cached.log"
grep -q "cached $name" "$result_dir/cached.log"
if grep -q '^epoch ' "$result_dir/cached.log"; then echo 'Cached execution replayed stale epochs'; exit 1; fi
if grep -q 'STALE_PROGRESS' "$result_dir/cached.log"; then echo 'Stale journal replayed'; exit 1; fi
if grep -q 'Training elapsed:' "$result_dir/cached.log"; then echo 'Cached fit displayed an execution time'; exit 1; fi
cmp "$result_dir/expected.receipt" "$result_dir/out/reports/$name-training-receipt.txt"
for mode in auto off; do
    CI=true TERM=dumb LC_ALL=C "$zig_bin" build "${common[@]}" "-Dprogress=$mode" > "$result_dir/$mode.stdout" 2> "$result_dir/$mode.log"
    cmp "$result_dir/expected.zinn" "$result_dir/out/training/$name.zinn"
    cmp "$result_dir/expected.csv" "$result_dir/out/reports/$name-training.csv"
    cmp "$result_dir/plain.stdout" "$result_dir/$mode.stdout"
done
test ! -s "$result_dir/off.log"
test -s "$result_dir/auto.log"
for mode in plain auto off; do
    CI=true TERM=dumb "$zig_bin" build evaluate e2e -Dproject=mnist -Dmnist-fixture=true -Dmnist-epochs=2 "-Dapp-name=$name" "-Dproject-checkpoint=$result_dir/out/training/$name.zinn" --prefix "$result_dir/out" "-Dprogress=$mode" > "$result_dir/export-$mode.stdout" 2> "$result_dir/export-$mode.log"
    cp "$result_dir/out/reports/$name-e2e-summary.json" "$result_dir/reference-$mode.txt"
    if [ "$mode" = plain ]; then
        cp "$result_dir/out/models/$name-int8.zig" "$result_dir/expected.zig"
        cp "$result_dir/out/reports/$name-model.json" "$result_dir/expected.json"
    else
        cmp "$result_dir/expected.zig" "$result_dir/out/models/$name-int8.zig"
        cmp "$result_dir/expected.json" "$result_dir/out/reports/$name-model.json"
        cmp "$result_dir/export-plain.stdout" "$result_dir/export-$mode.stdout"
        cmp "$result_dir/reference-plain.txt" "$result_dir/reference-$mode.txt"
    fi
done
"$zig_bin" build "${common[@]}" -Dprogress=plain > "$result_dir/concurrent-1.stdout" 2> "$result_dir/concurrent-1.log" &
first_pid=$!
"$zig_bin" build "${common[@]}" -Dprogress=plain > "$result_dir/concurrent-2.stdout" 2> "$result_dir/concurrent-2.log" &
second_pid=$!
wait "$first_pid"
wait "$second_pid"
grep -q "cached $name" "$result_dir/concurrent-1.log"
grep -q "cached $name" "$result_dir/concurrent-2.log"
parallel_name="$name-fresh"
parallel=(train -Dproject=mnist -Dmnist-fixture=true -Dmnist-epochs=2 "-Dapp-name=$parallel_name" --prefix "$result_dir/out" -Dprogress=plain)
"$zig_bin" build "${parallel[@]}" > "$result_dir/fresh-1.stdout" 2> "$result_dir/fresh-1.log" &
first_pid=$!
"$zig_bin" build "${parallel[@]}" > "$result_dir/fresh-2.stdout" 2> "$result_dir/fresh-2.log" &
second_pid=$!
wait "$first_pid"
wait "$second_pid"
test "$(grep -h -c "^completed $parallel_name$" "$result_dir/fresh-1.log" "$result_dir/fresh-2.log" | awk '{sum += $1} END {print sum}')" = 1
test "$(grep -h -c "^cached $parallel_name$" "$result_dir/fresh-1.log" "$result_dir/fresh-2.log" | awk '{sum += $1} END {print sum}')" = 1
cmp "$result_dir/expected.zinn" "$result_dir/out/training/$parallel_name.zinn"
if LC_ALL=C grep -q $'\033' "$result_dir/auto.log"; then echo 'ANSI escape in CI output'; exit 1; fi
if "$zig_bin" build train -Dproject=mnist -Dmnist-fixture=true -Dmnist-epochs=0 "-Dapp-name=$name" --prefix "$result_dir/out" -Dprogress=plain > "$result_dir/failed.stdout" 2> "$result_dir/failed.log"; then
    echo 'Invalid training unexpectedly succeeded'; exit 1
fi
if grep -q "cached $name" "$result_dir/failed.log"; then echo 'Failed training reported cached'; exit 1; fi
grep -q 'InvalidTrainingOptions' "$result_dir/failed.log"
"$zig_bin" build "${common[@]}" -Dseed=43 -Dprogress=plain > "$result_dir/invalidated.stdout" 2> "$result_dir/invalidated.log"
grep -q "completed $name" "$result_dir/invalidated.log"
if cmp -s "$result_dir/expected.zinn" "$result_dir/out/training/$name.zinn"; then echo 'Changed seed incorrectly reused checkpoint'; exit 1; fi
"$zig_bin" build "${common[@]}" -Dprogress=plain > "$result_dir/restored.stdout" 2> "$result_dir/restored.log"
grep -q "cached $name" "$result_dir/restored.log"
cmp "$result_dir/expected.zinn" "$result_dir/out/training/$name.zinn"
"$zig_bin" build "${common[@]}" -Dquiet=true > "$result_dir/quiet.stdout" 2> "$result_dir/quiet.log"
test ! -s "$result_dir/quiet.log"
cmp "$result_dir/expected.zinn" "$result_dir/out/training/$name.zinn"
echo "Progress CLI: live/cached, auto/plain/off, concurrency; identical checkpoint/CSV/source/JSON/reference ($result_dir)"
