#!/bin/sh
# Explicit optional POSIX UART exchange. No flash operation. Raw 115200 8N1.
set -eu
if [ "$#" -ne 3 ]; then
  echo "usage: $0 PORT request.bin response.bin" >&2
  exit 2
fi
port=$1
case "$(uname -s)" in Darwin) flag=-f ;; *) flag=-F ;; esac
previous=$(stty "$flag" "$port" -g)
trap 'stty "$flag" "$port" "$previous"' EXIT HUP INT TERM
stty "$flag" "$port" raw 115200 -echo cs8 -cstopb -parenb min 0 time 10
exec 3<>"$port"
cat "$2" >&3
# At most one frame; VTIME causes a bounded partial read to terminate on timeout.
dd bs=1 count=65535 <&3 >"$3" 2>/dev/null
