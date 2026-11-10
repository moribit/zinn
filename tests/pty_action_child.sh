#!/usr/bin/env bash
set -euo pipefail
action="$1"
shift
target_pid=$$
(
    sleep 1
    if [ "$action" = resize ]; then
        stty columns 40 rows 24 <&2
    else
        kill -INT "$target_pid"
    fi
) &
exec "$@"
