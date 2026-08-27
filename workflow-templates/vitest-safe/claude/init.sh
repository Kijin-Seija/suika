#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VITEST_SAFE_HOST=claude exec bash "${SCRIPT_DIR}/../common/install.sh" "$@"
