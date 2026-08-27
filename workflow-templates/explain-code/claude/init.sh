#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_SKILL_DIR="${SCRIPT_DIR}/explain-code"

usage() {
  cat >&2 <<'EOF'
用法:
  init.sh <target-project>          安装 explain-code skill
  init.sh --remove <target-project> 卸载 explain-code skill
EOF
}

main() {
  local mode="install"
  local target_project
  local destination

  if [[ "${1-}" == "--remove" ]]; then
    mode="remove"
    shift
  fi
  [[ $# -eq 1 ]] || {
    usage
    exit 1
  }
  target_project="$1"
  [[ -d "${target_project}" ]] || {
    echo "错误: 目标目录不存在或不是目录: ${target_project}" >&2
    exit 1
  }
  destination="${target_project}/.claude/skills/explain-code"

  if [[ "${mode}" == "remove" ]]; then
    rm -rf "${destination}"
    echo "已卸载 Claude Code 版 explain-code skill:"
    echo "- 目标项目: ${target_project}"
    return
  fi

  rm -rf "${destination}"
  mkdir -p "${destination}"
  cp "${SOURCE_SKILL_DIR}/SKILL.md" "${destination}/SKILL.md"

  echo "已安装 Claude Code 版 explain-code skill:"
  echo "- 目标项目: ${target_project}"
  echo "- skill: .claude/skills/explain-code/SKILL.md"
  echo "- 调用: /explain-code"
}

main "$@"
