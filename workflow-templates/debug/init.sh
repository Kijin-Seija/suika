#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_INSTALLER="${SCRIPT_DIR}/codex/init.sh"
CLAUDE_INSTALLER="${SCRIPT_DIR}/claude/init.sh"

usage() {
  cat >&2 <<'USAGE'
用法:
  init.sh <target-project>
  init.sh --codex <target-project>
  init.sh --claude <target-project>
USAGE
}

main() {
  local installer="${CODEX_INSTALLER}"
  local target_project=""

  case "${1-}" in
    --codex)
      shift
      ;;
    --claude)
      installer="${CLAUDE_INSTALLER}"
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
  exec bash "${installer}" "${target_project}"
}

main "$@"
