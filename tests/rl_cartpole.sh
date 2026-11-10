#!/usr/bin/env bash
# Offline deterministic RL pipeline; no display, network, or physical board.
set -euo pipefail
zig=${1:-zig}
out=${2:-rl-cartpole-results}
mkdir -p "$out"
out=$(cd "$out" && pwd)
build=examples/rl-cartpole/build.zig
"$zig" build --build-file "$build" test train evaluate e2e firmware -Dcheck-improvement=true -Dprogress=plain --prefix "$out/first" > "$out/first.log" 2>&1
"$zig" build --build-file "$build" train -Dprogress=plain --prefix "$out/first" > "$out/cached.log" 2>&1
grep -q cached "$out/cached.log"
"$zig" build --build-file "$build" train -Dprogress=off --prefix "$out/off" > "$out/off.log" 2>&1
for file in training/cartpole.zinn reports/curve.csv reports/report.json models/policy.zig reports/policy.json; do
  cmp "$out/first/$file" "$out/off/$file"
done
"$zig" build --build-file "$build" train e2e -Dprogress=off -Dcheckpoint="$out/first/training/cartpole.zinn" -Dcalibration="$out/first/reports/calibration.csv" --prefix "$out/reloaded" > "$out/reloaded.log" 2>&1
cmp "$out/first/training/cartpole.zinn" "$out/reloaded/training/cartpole.zinn"
cmp "$out/first/models/policy.zig" "$out/reloaded/models/policy.zig"
if "$zig" build --build-file "$build" firmware -Dflash-bytes=1024 > "$out/budget-rejected.log" 2>&1; then
  echo 'Expected final ELF budget failure' >&2
  exit 1
fi
grep -Eq 'FlashBudgetExceeded|OutsideMemory' "$out/budget-rejected.log"
echo 'CartPole pipeline: cached/off/reloaded artifacts identical; undersized ELF rejected'
