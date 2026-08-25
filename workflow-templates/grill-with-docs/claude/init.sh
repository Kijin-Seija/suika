#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_SKILL_DIR="${SCRIPT_DIR}/../common/skill"

usage() {
  echo "用法: $0 <target-project>" >&2
}

require_directory() {
  local path="$1"
  [[ -d "${path}" ]] || {
    echo "错误: 目标目录不存在或不是目录: ${path}" >&2
    exit 1
  }
}

main() {
  local target_project
  local destination

  [[ $# -eq 1 ]] || {
    usage
    exit 1
  }

  target_project="$1"
  require_directory "${target_project}"
  destination="${target_project}/.claude/skills/grill-with-docs"

  rm -rf "${destination}"
  mkdir -p "${destination}"
  cp "${COMMON_SKILL_DIR}/SKILL.md" "${destination}/SKILL.md"
  cp "${COMMON_SKILL_DIR}/CONTEXT-FORMAT.md" "${destination}/CONTEXT-FORMAT.md"
  cp "${COMMON_SKILL_DIR}/ADR-FORMAT.md" "${destination}/ADR-FORMAT.md"
  cp "${COMMON_SKILL_DIR}/LICENSE" "${destination}/LICENSE"

  echo "已安装 Claude Code 版 grill-with-docs:"
  echo "- 目标项目: ${target_project}"
  echo "- skill: .claude/skills/grill-with-docs/SKILL.md"
}

main "$@"
