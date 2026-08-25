#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_INSTALLER="${SCRIPT_DIR}/codex/init.sh"

usage() {
  cat >&2 <<'EOF'
用法:
  init.sh <target-project>                默认安装 Codex 版
  init.sh --codex <target-project>        安装 Codex 版
  init.sh --remove <target-project>       卸载 Codex 版
  init.sh --codex --remove <target-project>
EOF
}

main() {
  local remove_flag=""

  if [[ "${1-}" == "--codex" ]]; then
    shift
  fi
  if [[ "${1-}" == "--remove" ]]; then
    remove_flag="--remove"
    shift
  fi

  [[ $# -eq 1 ]] || {
    usage
    exit 1
  }

  if [[ -n "${remove_flag}" ]]; then
    exec bash "${CODEX_INSTALLER}" "${remove_flag}" "$1"
  fi
  exec bash "${CODEX_INSTALLER}" "$1"
}

main "$@"
