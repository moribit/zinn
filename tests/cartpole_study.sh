#!/usr/bin/env bash
# Full frozen study; do not use final-test results to select another export profile.
set -euo pipefail
zig=${1:-zig}
out=${2:-cartpole-study-results}
mkdir -p "$out"
out=$(cd "$out" && pwd)
for seed in 42 43 44 45 46; do
  "$zig" build --build-file examples/rl-cartpole/build.zig train study stability e2e firmware -Dseed="$seed" -Dpolicy-export=improved -Dfinal-test=true -Dprogress=off --prefix "$out/seed-$seed"
done
