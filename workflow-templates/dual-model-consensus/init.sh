#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="${SCRIPT_DIR}"

BEGIN_MARKER="<!-- BEGIN dual-model-consensus -->"
END_MARKER="<!-- END dual-model-consensus -->"
LEGACY_BEGIN_MARKER="<!-- BEGIN dual-model-consensus-plan -->"
LEGACY_END_MARKER="<!-- END dual-model-consensus-plan -->"

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

copy_file() {
  local source="$1"
  local destination="$2"
  cp "${source}" "${destination}"
}

remove_if_exists() {
  local path="$1"
  if [[ -e "${path}" ]]; then
    rm -rf "${path}"
  fi
}

agents_block() {
  cat <<'EOF'
<!-- BEGIN dual-model-consensus -->
## 双模型共识工作流

当用户显式要求使用"双模型共识工作流"时，优先使用项目级 skill：

- `.cursor/skills/dual-model-consensus/SKILL.md`

不要默认对所有普通请求启用该流程；只有用户明确要求时才触发。

支持两种制品类型：`plan`（计划制定）和 `code`（代码开发）。

相关模板位于：

- plan 模式: `claude-analysis-planner.md`, `gpt-review.md`, `claude-revision.md`
- code 模式: `claude-code-draft.md`, `gpt-code-review.md`, `claude-code-revision.md`
- 共用: `disagreement-report.md`
- 目录: `.cursor/prompts/dual-model-consensus/`

运行产物保存在：

- `.cursor/plans/<topic-slug>/`
<!-- END dual-model-consensus -->
EOF
}

upsert_agents_block() {
  local file="$1"
  local block
  local block_file
  local tmp_file

  block="$(agents_block)"
  block_file="$(mktemp)"
  tmp_file="$(mktemp)"
  printf "%s\n" "${block}" > "${block_file}"

  if [[ -f "${file}" ]]; then
    awk \
      -v begin1="${BEGIN_MARKER}" \
      -v end1="${END_MARKER}" \
      -v begin2="${LEGACY_BEGIN_MARKER}" \
      -v end2="${LEGACY_END_MARKER}" \
      -v block_file="${block_file}" '
      function print_block(   line) {
        while ((getline line < block_file) > 0) {
          print line
        }
        close(block_file)
      }
      BEGIN {
        inside = 0
      }
      $0 == begin1 || $0 == begin2 {
        inside = 1
        next
      }
      $0 == end1 || $0 == end2 {
        inside = 0
        next
      }
      inside {
        next
      }
      {
        print
      }
      END {
        if (NR > 0) {
          print ""
        }
        print_block()
      }
    ' "${file}" > "${tmp_file}"
  else
    printf "%s\n" "${block}" > "${tmp_file}"
  fi

  mv "${tmp_file}" "${file}"
  rm -f "${block_file}"
}

clean_legacy_install() {
  local target_project="$1"

  remove_if_exists "${target_project}/.cursor/skills/dual-model-consensus-plan"
  remove_if_exists "${target_project}/.cursor/prompts/dual-model-consensus-plan"
  remove_if_exists "${target_project}/.cursor/skills/dual-model-consensus"
  remove_if_exists "${target_project}/.cursor/prompts/dual-model-consensus"
  remove_if_exists "${target_project}/docs/ai/dual-model-consensus-workflow.md"
  remove_if_exists "${target_project}/docs/ai/dual-model-consensus-plan-workflow.md"
}

main() {
  local target_project

  [[ $# -eq 1 ]] || {
    usage
    exit 1
  }

  target_project="$1"
  require_directory "${target_project}"

  clean_legacy_install "${target_project}"

  mkdir -p \
    "${target_project}/.cursor/skills/dual-model-consensus" \
    "${target_project}/.cursor/prompts/dual-model-consensus" \
    "${target_project}/.cursor/agents" \
    "${target_project}/.cursor/plans"

  copy_file "${TEMPLATE_DIR}/skill/SKILL.md" "${target_project}/.cursor/skills/dual-model-consensus/SKILL.md"
  copy_file "${TEMPLATE_DIR}/skill/reference.md" "${target_project}/.cursor/skills/dual-model-consensus/reference.md"
  copy_file "${TEMPLATE_DIR}/prompts/claude-analysis-planner.md" "${target_project}/.cursor/prompts/dual-model-consensus/claude-analysis-planner.md"
  copy_file "${TEMPLATE_DIR}/prompts/gpt-review.md" "${target_project}/.cursor/prompts/dual-model-consensus/gpt-review.md"
  copy_file "${TEMPLATE_DIR}/prompts/claude-revision.md" "${target_project}/.cursor/prompts/dual-model-consensus/claude-revision.md"
  copy_file "${TEMPLATE_DIR}/prompts/disagreement-report.md" "${target_project}/.cursor/prompts/dual-model-consensus/disagreement-report.md"
  copy_file "${TEMPLATE_DIR}/prompts/claude-code-draft.md" "${target_project}/.cursor/prompts/dual-model-consensus/claude-code-draft.md"
  copy_file "${TEMPLATE_DIR}/prompts/gpt-code-review.md" "${target_project}/.cursor/prompts/dual-model-consensus/gpt-code-review.md"
  copy_file "${TEMPLATE_DIR}/prompts/claude-code-revision.md" "${target_project}/.cursor/prompts/dual-model-consensus/claude-code-revision.md"
  copy_file "${TEMPLATE_DIR}/agents/claude-author.md" "${target_project}/.cursor/agents/claude-author.md"
  copy_file "${TEMPLATE_DIR}/agents/gpt-reviewer.md" "${target_project}/.cursor/agents/gpt-reviewer.md"

  upsert_agents_block "${target_project}/AGENTS.md"

  echo "已初始化双模型共识工作流:"
  echo "- 目标项目: ${target_project}"
  echo "- skill: .cursor/skills/dual-model-consensus/SKILL.md"
  echo "- prompts: .cursor/prompts/dual-model-consensus/"
  echo "- agents: .cursor/agents/"
}

main "$@"
