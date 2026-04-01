#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_INSTALLER="${SCRIPT_DIR}/codex/init.sh"

usage() {
  cat >&2 <<'EOF'
用法:
  init.sh <target-project>         默认安装 Codex 版
  init.sh --codex <target-project> 只安装 Codex 版
EOF
}

main() {
  local mode="codex"
  local target_project=""

  case "${1-}" in
    --codex)
      mode="codex"
      shift
      ;;
  esac

  [[ $# -eq 1 ]] || {
    usage
    exit 1
  }

  target_project="$1"

  case "${mode}" in
    codex)
      exec bash "${CODEX_INSTALLER}" "${target_project}"
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
