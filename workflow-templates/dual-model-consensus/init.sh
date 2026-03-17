#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURSOR_INSTALLER="${SCRIPT_DIR}/cursor/init.sh"
CLAUDE_INSTALLER="${SCRIPT_DIR}/claude/init.sh"

usage() {
  cat >&2 <<'EOF'
用法:
  init.sh <target-project>          默认安装 Cursor 版
  init.sh --cursor <target-project> 只安装 Cursor 版
  init.sh --claude <target-project> 只安装 Claude Code 版
  init.sh --all <target-project>    同时安装 Cursor 和 Claude Code 两版
EOF
}

main() {
  local mode="cursor"
  local target_project=""

  case "${1-}" in
    --cursor|--claude|--all)
      mode="${1#--}"
      shift
      ;;
  esac

  [[ $# -eq 1 ]] || {
    usage
    exit 1
  }

  target_project="$1"

  case "${mode}" in
    cursor)
      exec bash "${CURSOR_INSTALLER}" "${target_project}"
      ;;
    claude)
      exec bash "${CLAUDE_INSTALLER}" "${target_project}"
      ;;
    all)
      bash "${CURSOR_INSTALLER}" "${target_project}"
      exec bash "${CLAUDE_INSTALLER}" "${target_project}"
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
