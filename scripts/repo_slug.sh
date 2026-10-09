#!/bin/bash
# Prints DROP's repository slug (owner/name) from Config/Repo.xcconfig, the only place it is set.
#
# Usage: scripts/repo_slug.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
slug="$(sed -n 's/^DROP_REPO_SLUG *= *\([^ ]*\) *$/\1/p' "$root/Config/Repo.xcconfig")"
if [[ ! "$slug" =~ ^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$ ]]; then
    echo "error: DROP_REPO_SLUG in Config/Repo.xcconfig is missing or not owner/name" >&2
    exit 1
fi
echo "$slug"
