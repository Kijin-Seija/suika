#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_INSTALLER="${SCRIPT_DIR}/claude/init.sh"

usage() {
  cat >&2 <<'EOF'
用法:
  init.sh <target-project>          默认安装 Claude Code 版
  init.sh --claude <target-project> 只安装 Claude Code 版
EOF
}

main() {
  local mode="claude"
  local target_project=""

  case "${1-}" in
    --claude)
      mode="claude"
      shift
      ;;
  esac

  [[ $# -eq 1 ]] || {
    usage
    exit 1
  }

  target_project="$1"

  case "${mode}" in
    claude)
      exec bash "${CLAUDE_INSTALLER}" "${target_project}"
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
