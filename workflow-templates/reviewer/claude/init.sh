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
  destination="${target_project}/.claude/skills/reviewer"

  rm -rf "${destination}"
  mkdir -p \
    "${destination}/prompts" \
    "${destination}/schemas" \
    "${destination}/bin" \
    "${target_project}/.claude/plans"

  cp "${SCRIPT_DIR}/skill/SKILL.md" "${destination}/SKILL.md"
  cp "${COMMON_DIR}/reference.md" "${destination}/reference.md"
  cp "${COMMON_DIR}/prompts/codex-blind-review-request.md" "${destination}/prompts/codex-blind-review-request.md"
  cp "${COMMON_DIR}/prompts/codex-review-request.md" "${destination}/prompts/codex-review-request.md"
  cp "${COMMON_DIR}/prompts/claude-review-response.md" "${destination}/prompts/claude-review-response.md"
  cp "${COMMON_DIR}/prompts/dispute-report.md" "${destination}/prompts/dispute-report.md"
  cp "${COMMON_DIR}/schemas/codex-review.schema.json" "${destination}/schemas/codex-review.schema.json"
  cp "${COMMON_DIR}/schemas/consensus-exclusions.schema.json" "${destination}/schemas/consensus-exclusions.schema.json"
  cp "${COMMON_DIR}/schemas/review-backlog.schema.json" "${destination}/schemas/review-backlog.schema.json"
  cp "${COMMON_DIR}/schemas/workflow-state.schema.json" "${destination}/schemas/workflow-state.schema.json"
  cp "${COMMON_DIR}/bin/reviewer-run.sh" "${destination}/bin/reviewer-run.sh"
  chmod +x "${destination}/bin/reviewer-run.sh"

  echo "已初始化 Claude Code 版 reviewer 工作流:"
  echo "- 目标项目: ${target_project}"
  echo "- skill: .claude/skills/reviewer/SKILL.md"
  echo "- launcher: .claude/skills/reviewer/bin/reviewer-run.sh"
  echo "- schemas: .claude/skills/reviewer/schemas/"
  echo "- prompts: .claude/skills/reviewer/prompts/"
  echo "- plans: .claude/plans/"
}

main "$@"
