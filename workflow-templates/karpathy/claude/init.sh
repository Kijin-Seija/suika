#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="${SCRIPT_DIR}/../common"

usage() {
  echo "用法: $0 <target-project>" >&2
}

main() {
  local target_project
  local destination

  [[ $# -eq 1 ]] || {
    usage
    exit 1
  }
  target_project="$1"
  [[ -d "${target_project}" ]] || {
    echo "错误: 目标目录不存在或不是目录: ${target_project}" >&2
    exit 1
  }
  destination="${target_project}/.claude/skills/karpathy"

  rm -rf "${destination}"
  mkdir -p "${destination}"
  cp "${SCRIPT_DIR}/skill/SKILL.md" "${destination}/SKILL.md"
  cp "${COMMON_DIR}/reference.md" "${destination}/reference.md"

  echo "已初始化 Claude Code 版 karpathy skill:"
  echo "- 目标项目: ${target_project}"
  echo "- skill: .claude/skills/karpathy/SKILL.md"
  echo "- reference: .claude/skills/karpathy/reference.md"
}

main "$@"
