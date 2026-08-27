#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="${SCRIPT_DIR}/../common"

usage() {
  echo "用法: $0 <target-project>" >&2
}

main() {
  local target_project

  [[ $# -eq 1 ]] || {
    usage
    exit 1
  }
  target_project="$1"
  [[ -d "${target_project}" ]] || {
    echo "错误: 目标目录不存在或不是目录: ${target_project}" >&2
    exit 1
  }

  rm -rf \
    "${target_project}/.claude/skills/debug" \
    "${target_project}/.claude/skills/debug-auto" \
    "${target_project}/.claude/skills/debug-steps" \
    "${target_project}/.claude/skills/debug-manual"
  mkdir -p \
    "${target_project}/.claude/skills/debug-auto" \
    "${target_project}/.claude/skills/debug-steps/bin" \
    "${target_project}/.claude/skills/debug-manual"

  cp "${SCRIPT_DIR}/skills/debug-auto/SKILL.md" "${target_project}/.claude/skills/debug-auto/SKILL.md"
  cp "${SCRIPT_DIR}/skills/debug-steps/SKILL.md" "${target_project}/.claude/skills/debug-steps/SKILL.md"
  cp "${SCRIPT_DIR}/skills/debug-manual/SKILL.md" "${target_project}/.claude/skills/debug-manual/SKILL.md"
  cp "${SCRIPT_DIR}/reference-steps.md" "${target_project}/.claude/skills/debug-steps/reference.md"
  cp "${COMMON_DIR}/bin/debug-session.sh" "${target_project}/.claude/skills/debug-steps/bin/debug-session.sh"
  cp "${COMMON_DIR}/bin/debug_log_server.py" "${target_project}/.claude/skills/debug-steps/bin/debug_log_server.py"
  chmod +x \
    "${target_project}/.claude/skills/debug-steps/bin/debug-session.sh" \
    "${target_project}/.claude/skills/debug-steps/bin/debug_log_server.py"

  echo "已初始化 Claude Code 版 debug 工作流:"
  echo "- 目标项目: ${target_project}"
  echo "- skills:"
  echo "  - .claude/skills/debug-auto/SKILL.md"
  echo "  - .claude/skills/debug-steps/SKILL.md"
  echo "  - .claude/skills/debug-manual/SKILL.md"
  echo "- launcher: .claude/skills/debug-steps/bin/debug-session.sh"
}

main "$@"
