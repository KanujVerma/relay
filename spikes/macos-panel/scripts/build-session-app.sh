#!/bin/bash
set -euo pipefail
relay_panel_dir="$(cd "$(dirname "$0")/.." && pwd)"
relay_repository_dir="$(cd "$relay_panel_dir/../.." && pwd)"
exec "${RELAY_BUILD_PYTHON:-python3}" "$relay_repository_dir/packaging/build_product.py" "$@"
