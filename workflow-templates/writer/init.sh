#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_INSTALLER="${SCRIPT_DIR}/codex/init.sh"

usage() {
  cat >&2 <<'EOF'
用法:
  init.sh [--default-writer <claude|codex>] <target-project>
  init.sh --codex [--default-writer <claude|codex>] <target-project>
EOF
}

main() {
  local mode="codex"
  local default_writer=""
  local target_project=""

  while [[ $# -gt 0 ]]; do
    case "${1-}" in
      --codex)
        mode="codex"
        shift
        ;;
      --default-writer)
        default_writer="${2-}"
        shift 2
        ;;
      --)
        shift
        break
        ;;
      -*)
        usage
        exit 1
        ;;
      *)
        break
        ;;
    esac
  done

  [[ $# -eq 1 ]] || {
    usage
    exit 1
  }

  target_project="$1"

  case "${mode}" in
    codex)
      if [[ -n "${default_writer}" ]]; then
        exec bash "${CODEX_INSTALLER}" --default-writer "${default_writer}" "${target_project}"
      fi
      exec bash "${CODEX_INSTALLER}" "${target_project}"
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
