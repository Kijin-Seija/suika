#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_INSTALLER="${SCRIPT_DIR}/codex/init.sh"
CLAUDE_INSTALLER="${SCRIPT_DIR}/claude/init.sh"

usage() {
  cat >&2 <<'USAGE'
用法:
  init.sh <target-project>          默认同时安装 Codex 和 Claude Code 两版
  init.sh --codex <target-project> 只安装 Codex 版
  init.sh --claude <target-project> 只安装 Claude Code 版
  init.sh --all <target-project>    同时安装 Codex 和 Claude Code 两版
USAGE
}

main() {
  local mode="all"
  local target_project=""

  case "${1-}" in
    --codex|--claude|--all)
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
    codex)
      exec bash "${CODEX_INSTALLER}" "${target_project}"
      ;;
    claude)
      exec bash "${CLAUDE_INSTALLER}" "${target_project}"
      ;;
    all)
      bash "${CODEX_INSTALLER}" "${target_project}"
      exec bash "${CLAUDE_INSTALLER}" "${target_project}"
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
