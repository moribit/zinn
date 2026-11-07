#!/bin/sh
# Fixed, prespecified validation study. It never reads official test files.
set -eu
zig_bin=${ZIG:-zig}
mnist_dir=${1:-data/mnist}
run() {
  "$zig_bin" build mnist-train mnist "-Ddata-dir=$mnist_dir" -Devaluation-split=validation -Dvalidation-count=5000 -Dsplit-seed=24301 "$@"
}
run -Drun-name=val-mlp16-e10-s42 -Dmnist-hidden=16 -Dmnist-epochs=10 -Dlearning-rate=0.05 -Dseed=42
run -Drun-name=val-mlp16-e30-s42 -Dmnist-hidden=16 -Dmnist-epochs=30 -Dlearning-rate=0.05 -Dseed=42
run -Drun-name=val-mlp32-e20-s42 -Dmnist-hidden=32 -Dmnist-epochs=20 -Dlearning-rate=0.05 -Dseed=42
run -Drun-name=val-mlp32-lr1-e20-s42 -Dmnist-hidden=32 -Dmnist-epochs=20 -Dlearning-rate=0.1 -Dseed=42
run -Drun-name=val-mlp32-nearest-e20-s42 -Dmnist-hidden=32 -Dmnist-epochs=20 -Dlearning-rate=0.05 -Dpreprocess=nearest -Dseed=42
run -Drun-name=val-cnn2-e20-s42 -Dmnist-model=cnn -Dcnn-channels=2 -Dmnist-epochs=20 -Dlearning-rate=0.05 -Dseed=42
run -Drun-name=val-cnn4-e20-s42 -Dmnist-model=cnn -Dcnn-channels=4 -Dmnist-epochs=20 -Dlearning-rate=0.05 -Dseed=42
# Repeat the primary MLP config with a second seed; do not select the best seed by test score.
run -Drun-name=val-mlp32-lr1-e20-s43 -Dmnist-hidden=32 -Dmnist-epochs=20 -Dlearning-rate=0.1 -Dseed=43
