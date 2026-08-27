#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_INSTALLER="${SCRIPT_DIR}/codex/init.sh"
CLAUDE_INSTALLER="${SCRIPT_DIR}/claude/init.sh"

usage() {
  cat >&2 <<'EOF'
用法:
  init.sh [--max-concurrent <n>]              默认安装 Codex 版
  init.sh --codex [--max-concurrent <n>]      安装 Codex 版
  init.sh --claude [--max-concurrent <n>]     安装 Claude Code 版
  init.sh [--codex|--claude] --remove         卸载对应宿主版本
EOF
}

main() {
  local installer="${CODEX_INSTALLER}"
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

  exec bash "${installer}" "$@"
}

main "$@"
