#!/usr/bin/env bash
set -euo pipefail
stty columns "$1" rows 24
shift
export TERM=xterm-256color
unset CI
exec "$@"
