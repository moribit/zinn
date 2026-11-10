#!/usr/bin/env bash
# Standard macOS/Linux `script` supplies a real TTY; no Python dependency.
set -euo pipefail
zig_bin="${1:-zig}"
results="${2:-$(mktemp -d)}"
mkdir -p "$results"
run_pty() {
    local capture="$1"
    shift
    if [ "$(uname -s)" = Darwin ]; then
        script -q "$capture" "$@" > /dev/null
    else
        local quoted
        printf -v quoted '%q ' "$@"
        script -q -e -c "$quoted" "$capture" > /dev/null
    fi
}
"$zig_bin" build progress-tools
for width in 40 60 80 120; do
    name="visual-pty-$width-$$"
    command=(bash tests/pty_child.sh "$width" "$zig_bin" build train -Dproject=mnist -Dmnist-fixture=true -Dmnist-epochs=2 "-Dapp-name=$name" -Dprogress=auto --prefix "$results/out")
    # Preconfigure under CI/plain capabilities. Runtime TTY detection must not
    # inherit a cached CI/TERM environment from this help-only invocation.
    CI=true TERM=dumb "$zig_bin" build train -Dproject=mnist -Dmnist-fixture=true -Dmnist-epochs=2 "-Dapp-name=$name" -Dprogress=auto --prefix "$results/out" --help > "$results/help-$width.txt"
    run_pty "$results/$width.log" "${command[@]}"
    grep -Fq $'\033[2K' "$results/$width.log"
    grep -Fq '[#####' "$results/$width.log"
    grep -q "completed $name" "$results/$width.log"
    if [ "$width" = 40 ]; then
        cp "$results/out/training/$name.zinn" "$results/expected.zinn"
        cp "$results/out/reports/$name-training.csv" "$results/expected.csv"
    else
        cmp "$results/expected.zinn" "$results/out/training/$name.zinn"
        cmp "$results/expected.csv" "$results/out/reports/$name-training.csv"
    fi
    run_pty "$results/download-$width.log" bash tests/pty_child.sh "$width" ./zig-out/bin/progress-demo --download --progress=auto
    grep -Fq $'\033[2K' "$results/download-$width.log"
    grep -Fq '100%' "$results/download-$width.log"
done
run_pty "$results/cached-training.log" "${command[@]}"
grep -q "cached $name" "$results/cached-training.log"
if grep -Eq 'E[0-9]+/[0-9]+' "$results/cached-training.log"; then echo 'Cache hit replayed a visual fit'; exit 1; fi
for mode in plain off; do
    run_pty "$results/download-$mode.log" bash tests/pty_child.sh 80 ./zig-out/bin/progress-demo --download "--progress=$mode"
    if grep -Fq $'\033' "$results/download-$mode.log"; then echo 'Non-auto mode emitted ANSI'; exit 1; fi
done
run_pty "$results/dumb.log" bash tests/pty_child.sh 80 env TERM=dumb ./zig-out/bin/progress-demo --download --progress=auto
if grep -Fq $'\033' "$results/dumb.log"; then echo 'Dumb terminal emitted ANSI'; exit 1; fi
if run_pty "$results/failed-download.log" bash tests/pty_child.sh 80 ./zig-out/bin/progress-demo --download --fail --progress=auto; then
    echo 'Expected visual fixture failure'; exit 1
fi
grep -q 'failed fixture.gz' "$results/failed-download.log"
if grep -q '100%' "$results/failed-download.log"; then echo 'Failed transfer displayed completion'; exit 1; fi
run_pty "$results/resize.log" bash tests/pty_child.sh 120 bash tests/pty_action_child.sh resize ./zig-out/bin/progress-demo --download --wait --progress=auto
grep -Fq '[#####] 9.77/9.77KiB 100%' "$results/resize.log"
if run_pty "$results/interrupt.log" bash tests/pty_child.sh 80 bash tests/pty_action_child.sh interrupt ./zig-out/bin/progress-demo --download --wait --progress=auto; then
    echo 'Expected SIGINT exit'; exit 1
fi
if grep -Fq '100%' "$results/interrupt.log"; then echo 'Interrupted transfer displayed completion'; exit 1; fi
echo "PTY bars: 40/60/80/120 columns, identical checkpoints/CSV ($results)"
