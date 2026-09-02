#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"
PORT="${1:-8080}"
echo "Preview: http://localhost:$PORT"
python3 -m http.server "$PORT"
