#!/bin/bash
# Starts a debug build of DROP.app in each screenshot scenario (sample data, no network) and
# captures its windows into OUT_DIR as PNG files.
#
# Usage: scripts/screenshots.sh path/to/DROP.app OUT_DIR
set -euo pipefail

app="${1:?usage: screenshots.sh path/to/DROP.app OUT_DIR}"
out="${2:?usage: screenshots.sh path/to/DROP.app OUT_DIR}"
root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$out"
tool="$(mktemp -d)/window_bounds"
swiftc -O -o "$tool" "$root/scripts/window_bounds.swift"

capture() {
    local name="$1" scenario="$2" which="$3"
    shift 3
    "$app/Contents/MacOS/DROP" -DROPScreenshot "$scenario" -ApplePersistenceIgnoreState YES "$@" \
        > "$out/$name.log" 2>&1 &
    local pid=$!
    sleep 10
    local bounds
    if bounds="$("$tool" "$pid" "$which")"; then
        screencapture -x -o -R "$bounds" "$out/$name.png"
    else
        echo "::warning::No window found for $name; capturing the whole screen."
        screencapture -x "$out/$name.png"
    fi
    kill "$pid" 2> /dev/null || true
    wait "$pid" 2> /dev/null || true
    echo "Captured $name"
}

capture 1-projects projects all
capture 2-drop-form drop-form all
capture 3-ready-to-drop ready-to-drop all
capture 4-dropped dropped all
capture 5-account account front
capture 6-projects-de projects all -AppleLanguages "(de)" -AppleLocale de_DE
