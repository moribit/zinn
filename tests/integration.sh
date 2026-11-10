#!/usr/bin/env bash
set -euo pipefail
zig_bin="${1:-zig}"
results="${2:-$(mktemp -d)}"
mkdir -p "$results"
for app in host-app multi-model; do
    "$zig_bin" build --build-file "examples/integration/$app/build.zig" run sensor-generate sensor-e2e --prefix "$results/$app" > "$results/$app.stdout" 2> "$results/$app.log"
    grep -q 'Integration inference: PASS' "$results/$app.log"
    grep -q 'Result: PASS' "$results/$app.log"
    if [ "$app" = multi-model ]; then
        "$zig_bin" build --build-file "examples/integration/$app/build.zig" other-generate other-e2e --prefix "$results/$app" > "$results/other.stdout" 2> "$results/other.log"
        grep -q 'Result: PASS' "$results/other.log"
        test -f "$results/$app/reports/other-model.json"
    fi
    cp "$results/$app/training/sensor.zinn" "$results/$app-checkpoint.zinn"
    cp "$results/$app/reports/sensor-training.csv" "$results/$app-curve.csv"
    cp "$results/$app/reports/sensor-training-receipt.txt" "$results/$app-receipt.txt"
    "$zig_bin" build --build-file "examples/integration/$app/build.zig" sensor-train --prefix "$results/$app" > "$results/$app-cached.stdout" 2> "$results/$app-cached.log"
    grep -q '^cached sensor$' "$results/$app-cached.log"
    cmp "$results/$app-checkpoint.zinn" "$results/$app/training/sensor.zinn"
    cmp "$results/$app-curve.csv" "$results/$app/reports/sensor-training.csv"
    cmp "$results/$app-receipt.txt" "$results/$app/reports/sensor-training-receipt.txt"
done
"$zig_bin" build --build-file examples/integration/host-app/build.zig library-test compatibility portability --summary all > "$results/portability.stdout" 2> "$results/portability.log"
fw=(--build-file examples/integration/ch32-existing-app/build.zig --prefix "$results/firmware")
"$zig_bin" build "${fw[@]}" install sensor-generate custom-map-memory > "$results/firmware.stdout" 2> "$results/firmware.log"
cp "$results/firmware/reports/sensor-evaluate-receipt.txt" "$results/fw-export-receipt.txt"
cp "$results/firmware/models/sensor-int4.zig" "$results/fw-model.zig"
"$zig_bin" build "${fw[@]}" install sensor-generate -Dled-pin=2 > "$results/fw-rebuild.stdout" 2> "$results/fw-rebuild.log"
grep -q '^cached sensor$' "$results/fw-rebuild.log"
cmp "$results/fw-export-receipt.txt" "$results/firmware/reports/sensor-evaluate-receipt.txt"
cmp "$results/fw-model.zig" "$results/firmware/models/sensor-int4.zig"
if "$zig_bin" build "${fw[@]}" -Dflash-bytes=1024 > "$results/undersized.stdout" 2> "$results/undersized.log"; then echo 'Undersized firmware unexpectedly passed'; exit 1; fi
grep -Eq 'VirtualAddressOutsideMemory|FlashBudgetExceeded' "$results/undersized.log"
echo "External integration: host/multi-model/cache/firmware/portability/budget PASS ($results)"
