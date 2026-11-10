#!/usr/bin/env bash
set -euo pipefail
zig_bin="${1:-zig}"
results="${2:-$(mktemp -d)}"
mkdir -p "$results"
for project in xor mnist csv; do
    for bits in int8 int4; do
        name="workflow-$project-$bits-$$"
        args=(-Dproject="$project" -Dweight-format="$bits" -Dprogress=plain --prefix "$results/out")
        if [ "$project" = mnist ]; then
            args+=(-Dmnist-fixture=true -Dmnist-epochs=2 -Devaluation-split=test "-Dapp-name=$name")
        elif [ "$project" = csv ]; then
            args+=(-Dcsv-train=examples/data_classifier/train.csv -Dcsv-test=examples/data_classifier/test.csv "-Dapp-name=$name")
        else
            name=xor
        fi
        "$zig_bin" build e2e "${args[@]}" > "$results/$project-$bits.stdout" 2> "$results/$project-$bits.log"
        grep -q 'Result: PASS' "$results/$project-$bits.log"
        grep -q 'not classification accuracy' "$results/$project-$bits.log"
        report="$results/out/reports/$name-e2e-summary.json"
        grep -q '"kind":"e2e"' "$report"
        if [ "$project" = mnist ]; then grep -q '"samples":16' "$report"; else grep -q '"samples":4' "$report"; fi
        "$zig_bin" build e2e "${args[@]}" > "$results/$project-$bits-cached.stdout" 2> "$results/$project-$bits-cached.log"
        grep -q "^cached $name$" "$results/$project-$bits-cached.log"
    done
done
# Supplied checkpoints must work even when new training is deliberately invalid.
# The canonical project-checkpoint option applies to XOR too.
for project in xor mnist csv; do
    reuse=(e2e -Dproject="$project" -Dweight-format=int4 -Dprogress=plain --prefix "$results/reuse-$project")
    if [ "$project" = xor ]; then
        checkpoint="$results/out/models/xor.zinn"
        reuse+=("-Dproject-checkpoint=$checkpoint")
    else
        checkpoint="$results/out/training/workflow-$project-int4-$$.zinn"
        reuse+=("-Dproject-checkpoint=$checkpoint" "-Dapp-name=reuse-$project-$$")
        if [ "$project" = mnist ]; then reuse+=(-Dmnist-fixture=true -Dmnist-epochs=0); else reuse+=(-Dcsv-epochs=0 -Dcsv-train=examples/data_classifier/train.csv -Dcsv-test=examples/data_classifier/test.csv); fi
    fi
    "$zig_bin" build "${reuse[@]}" > "$results/reuse-$project.stdout" 2> "$results/reuse-$project.log"
    grep -q 'Result: PASS' "$results/reuse-$project.log"
    if [ "$project" = xor ]; then test ! -e "$results/reuse-xor/models/xor.zinn"; fi
done
if "$zig_bin" build e2e -Dproject=xor "-Dproject-checkpoint=$results/out/training/workflow-mnist-int4-$$.zinn" -Dprogress=plain --prefix "$results/out" > "$results/wrong-checkpoint.stdout" 2> "$results/wrong-checkpoint.log"; then echo 'Wrong checkpoint succeeded'; exit 1; fi
if grep -q 'Result: PASS' "$results/wrong-checkpoint.log"; then echo 'Failed child reused a PASS summary'; exit 1; fi
# An evaluate invocation may fit implicitly, but must not verify integer logits.
# The subsequent explicit train must reuse that same cached fitting producer.
name="shared-producer-$$"
shared=(-Dproject=mnist -Dmnist-fixture=true -Dmnist-epochs=2 "-Dapp-name=$name" -Dprogress=plain --prefix "$results/out")
"$zig_bin" build evaluate "${shared[@]}" > "$results/shared-evaluate.stdout" 2> "$results/shared-evaluate.log"
if grep -q 'Integer reference verification' "$results/shared-evaluate.log"; then echo 'Evaluate unexpectedly ran E2E'; exit 1; fi
"$zig_bin" build train "${shared[@]}" > "$results/shared-train.stdout" 2> "$results/shared-train.log"
grep -q "^cached $name$" "$results/shared-train.log"
if "$zig_bin" build e2e -Dproject=unsupported > "$results/invalid.stdout" 2> "$results/invalid.log"; then echo 'Unknown project succeeded'; exit 1; fi
"$zig_bin" build --build-file examples/project/custom.build.zig train evaluate e2e -Depochs=2001 -Dprogress=plain --prefix "$results/custom" > "$results/custom.stdout" 2> "$results/custom.log"
grep -q '"optimizer_steps":2001' "$results/custom/reports/sensor-model.json"
grep -q 'Result: PASS' "$results/custom.log"
"$zig_bin" build --build-file examples/project/custom.build.zig train -Depochs=2001 -Dprogress=plain --prefix "$results/custom" > "$results/custom-cached.stdout" 2> "$results/custom-cached.log"
grep -q '^cached sensor$' "$results/custom-cached.log"
# A session marker changed after producer startup must not change its receipt.
name="session-snapshot-$$"
cache="$results/snapshot-cache"
journal="$cache/zinn-progress/$name-training"
"$zig_bin" build train -Dproject=mnist -Dmnist-fixture=true -Dmnist-epochs=10000 -Ddecay-every=0 "-Dapp-name=$name" -Dprogress=plain --cache-dir "$cache" --prefix "$results/snapshot-out" > "$results/snapshot.stdout" 2> "$results/snapshot.log" &
snapshot_pid=$!
changed=false
for ((attempt=0; attempt<12000; attempt++)); do
    if [ -f "$journal/session" ]; then
        token="$(cat "$journal/session")"
        if [ -f "$journal/events-$token.jsonl" ] && grep -q "\"name\":\"$name training\"" "$journal/events-$token.jsonl"; then
            printf '00000000000000000000000000000000' > "$journal/session"
            changed=true
            break
        fi
    fi
    if ! kill -0 "$snapshot_pid" 2>/dev/null; then break; fi
    sleep 0.01
done
wait "$snapshot_pid"
test "$changed" = true
grep -q "^completed $name$" "$results/snapshot.log"
test "$(cat "$results/snapshot-out/reports/$name-training-receipt.txt")" = "$token"
echo "CLI consistency: XOR/MNIST/CSV int8/int4, shared producer cache, custom script/options ($results)"
