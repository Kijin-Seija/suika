#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_INSTALLER="${SCRIPT_DIR}/codex/init.sh"

usage() {
  cat >&2 <<'USAGE'
用法:
  init.sh <target-project>
  init.sh --codex <target-project>
USAGE
}

main() {
  local target_project=""

  case "${1-}" in
    --codex)
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
  esac

  [[ $# -eq 1 ]] || {
    usage
    exit 1
  }

  target_project="$1"
  exec bash "${CODEX_INSTALLER}" "${target_project}"
}

main "$@"
