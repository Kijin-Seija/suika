#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PUSH_CODE_HOST=codex exec bash "${SCRIPT_DIR}/../common/install.sh" "$@"
