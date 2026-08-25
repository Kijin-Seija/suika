#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_INSTALLER="${SCRIPT_DIR}/codex/init.sh"

usage() {
  cat >&2 <<'EOF'
用法:
  init.sh [--max-concurrent <n>]     全局安装 Vitest Safe（默认上限 2）
  init.sh --remove                   卸载全局 Vitest Safe
EOF
}

main() {
  case "${1-}" in
    --help|-h)
      usage
      exit 0
      ;;
  esac

  exec bash "${CODEX_INSTALLER}" "$@"
}

main "$@"
