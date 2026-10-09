#!/bin/bash
# Starts DROP.app and checks that it is still running after a while. Catches anything that stops
# DROP from starting at all.
#
# Usage: scripts/launch_test.sh path/to/DROP.app [seconds]
set -euo pipefail

app="${1:?usage: launch_test.sh path/to/DROP.app [seconds]}"
seconds="${2:-15}"
log="$(mktemp)"

"$app/Contents/MacOS/DROP" > "$log" 2>&1 &
pid=$!
sleep "$seconds"
if ! kill -0 "$pid" 2> /dev/null; then
    echo "::error::DROP quit within $seconds seconds of starting."
    cat "$log"
    exit 1
fi
kill "$pid"
echo "DROP started and kept running for $seconds seconds."
