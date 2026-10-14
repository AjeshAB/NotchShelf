#!/bin/bash
set -euo pipefail
app_pid=${1:-$(pgrep -x NotchShelf)}
if [[ ! "$app_pid" =~ ^[0-9]+$ ]]; then
  printf 'Pass the PID of one running NotchShelf process.\n' >&2
  exit 1
fi
# Keep the panel collapsed and avoid interacting with it during this sample.
# Discard top's initial CPU reading; later samples cover two-second intervals.
top -l 6 -s 2 -pid "$app_pid" -stats pid,cpu,mem,threads
