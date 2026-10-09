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

capture 01-signed-out signed-out all
capture 02-sign-in sign-in all
capture 03-session-ended session-ended all
capture 04-projects projects all
capture 05-add-project add-project all
capture 06-drop-form drop-form all
capture 07-ready-to-drop ready-to-drop all
capture 08-dropped dropped all
capture 09-run run all
capture 10-run-workflow run-workflow all
capture 11-release-workflow release-workflow all
capture 12-settings-general settings-general front
capture 13-settings-account settings-account front
capture 14-projects-de projects all -AppleLanguages "(de)" -AppleLocale de_DE
capture 15-drop-form-de drop-form all -AppleLanguages "(de)" -AppleLocale de_DE
