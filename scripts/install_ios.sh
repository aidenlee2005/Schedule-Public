#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec xcrun python3 "$SCRIPT_DIR/install_ios.py" "$@"
