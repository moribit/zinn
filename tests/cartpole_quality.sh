#!/usr/bin/env bash
set -euo pipefail
zig=${1:-zig}
out=${2:-cartpole-quality-results}
mkdir -p "$out"
out=$(cd "$out" && pwd)
build=examples/rl-cartpole/build.zig
"$zig" build --build-file "$build" test train evaluate e2e firmware study quality-check -Dpolicy-export=improved -Dfinal-test=true -Dprogress=off --prefix "$out/first" > "$out/first.log" 2>&1
"$zig" build --build-file "$build" train e2e -Dpolicy-export=improved -Dprogress=plain --prefix "$out/plain" > "$out/plain.log" 2>&1
for file in training/cartpole.zinn reports/curve.csv models/policy.zig reports/policy.json; do cmp "$out/first/$file" "$out/plain/$file"; done
# Export profile may change integer source, never the saved original float policy.
"$zig" build --build-file "$build" train -Dprogress=off --prefix "$out/baseline" > "$out/baseline.log" 2>&1
cmp "$out/first/training/cartpole.zinn" "$out/baseline/training/cartpole.zinn"
cmp "$out/first/reports/curve.csv" "$out/baseline/reports/curve.csv"
"$zig" build --build-file "$build" train e2e -Dpolicy-export=improved -Dprogress=off -Dcheckpoint="$out/first/training/cartpole.zinn" -Dcalibration="$out/first/reports/calibration.csv" --prefix "$out/reloaded" > "$out/reloaded.log" 2>&1
cmp "$out/first/training/cartpole.zinn" "$out/reloaded/training/cartpole.zinn"
cmp "$out/first/models/policy.zig" "$out/reloaded/models/policy.zig"
if "$zig" build --build-file "$build" train -Dpolicy-export=invalid > "$out/invalid-profile.log" 2>&1; then exit 1; fi
if "$zig" build --build-file "$build" train -Dgamma=nan > "$out/invalid-gamma.log" 2>&1; then exit 1; fi
if "$zig" build --build-file "$build" train -Dbatch=0 > "$out/invalid-batch.log" 2>&1; then exit 1; fi
if "$zig" build --build-file "$build" firmware -Dpolicy-export=improved -Dflash-bytes=1024 > "$out/budget.log" 2>&1; then exit 1; fi
grep -Eq 'OutsideMemory|FlashBudgetExceeded' "$out/budget.log"
echo 'CartPole quality: final comparison, integer reference, checkpoint/curve preservation, progress modes, invalid options and ELF budget PASS'
