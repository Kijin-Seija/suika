#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_DIR="${SCRIPT_DIR}"
COMMON_DIR="${SCRIPT_DIR}/../common"

BEGIN_MARKER="<!-- BEGIN reviewer -->"
END_MARKER="<!-- END reviewer -->"

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
<!-- BEGIN reviewer -->
## Reviewer 工作流

当用户显式要求使用 reviewer 工作流时，优先使用项目级 skill：

- `.codex/skills/reviewer/SKILL.md`

不要默认对所有普通请求启用该流程；只有用户明确要求时才触发。

该工作流由当前 Codex 会话完成主任务，再执行“外层独立盲审 + 内层主 agent 修复/reviewer 复查”：

- 每次外层盲审必须 `spawn_agent(..., fork_turns="none")` 创建上下文隔离的只读 reviewer subagent
- 盲审只接收原始任务、原始 baseline、baseline diff、真实工作区、active 共识排除项和非阻塞 review backlog，不接收完整 review 历史、回应或轮次信息
- 只有 reviewer 明确确认的 questioned/rejected 问题才能进入 `consensus-exclusions.json`；事实变化时可结构化重新打开
- code 只有当前状态下已观察到、可独立复验的 failing check/runtime reproduction/safe PoC 才阻塞；doc 可使用 document observation；未来风险和静态猜测进入 `review-backlog.json`
- 盲审发现交付阻塞问题后，主 agent 必须先独立复现；只有复现成功才修改，再由同一个只读 reviewer subagent 复查
- 内层通过后先合并共识账本并清理该轮临时审查文件，再启动下一次全新独立盲审
- `brief.md`、`consensus-exclusions.json`、`review-backlog.json`、最终/争议文件保留；未通过或需人工裁决时不清理
- 每个主 task 最多完成 10 次独立盲审；仍需继续时写入 workflow checkpoint，并通过 `create_thread` 在同一 local checkout 创建无历史的新 task
- 不使用 fork 或 worktree；新 task 从 `workflow-state.json` 的 next audit 恢复
- 一次独立盲审没有交付阻塞问题时稳定收敛；goal 模式全局最多 20 轮
- `.codex/skills/reviewer/bin/reviewer-run.sh` 仅保留兼容/回归用途，不是首选执行方式
- `.codex/skills/reviewer/schemas/codex-review.schema.json`
- `.codex/skills/reviewer/schemas/consensus-exclusions.schema.json`
- `.codex/skills/reviewer/schemas/review-backlog.schema.json`
- `.codex/skills/reviewer/schemas/workflow-state.schema.json`

该工作流支持两类制品：`code`（代码变更）和 `doc`（计划、分析、说明文档）。

reviewer subagent 必须复用当前工作区直接读取最新文件和未提交改动，并忽略 `.codex/plans/`。不要退回用 shell 启动 `codex exec` 来充当 reviewer。兼容 launcher 默认模型仍为 `gpt-5.4`，可通过 `REVIEWER_CODEX_REVIEW_MODEL` 覆盖。

普通会话默认最多启动 `5` 次独立盲审；内层修订不计入该次数。当前 Codex 会话处于 goal 模式时使用 `20 (goal-mode)`。任意一次全新盲审没有交付阻塞问题即稳定收敛；第 20 轮内层收敛后按 review budget 结束。

运行产物默认保存在：

- `.codex/plans/<topic-slug>/`
<!-- END reviewer -->
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
      $0 == begin1 {
        inside = 1
        next
      }
      $0 == end1 {
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

clean_previous_install() {
  local target_project="$1"

  remove_if_exists "${target_project}/.codex/skills/reviewer"
}

main() {
  local target_project

  [[ $# -eq 1 ]] || {
    usage
    exit 1
  }

  target_project="$1"
  require_directory "${target_project}"

  clean_previous_install "${target_project}"

  mkdir -p \
    "${target_project}/.codex/skills/reviewer/prompts" \
    "${target_project}/.codex/skills/reviewer/schemas" \
    "${target_project}/.codex/skills/reviewer/bin" \
    "${target_project}/.codex/plans"

  copy_file "${CODEX_DIR}/skill/SKILL.md" "${target_project}/.codex/skills/reviewer/SKILL.md"
  copy_file "${COMMON_DIR}/reference.md" "${target_project}/.codex/skills/reviewer/reference.md"
  copy_file "${COMMON_DIR}/prompts/codex-blind-review-request.md" "${target_project}/.codex/skills/reviewer/prompts/codex-blind-review-request.md"
  copy_file "${COMMON_DIR}/prompts/codex-review-request.md" "${target_project}/.codex/skills/reviewer/prompts/codex-review-request.md"
  copy_file "${COMMON_DIR}/prompts/codex-review-response.md" "${target_project}/.codex/skills/reviewer/prompts/codex-review-response.md"
  copy_file "${COMMON_DIR}/prompts/dispute-report.md" "${target_project}/.codex/skills/reviewer/prompts/dispute-report.md"
  copy_file "${COMMON_DIR}/schemas/codex-review.schema.json" "${target_project}/.codex/skills/reviewer/schemas/codex-review.schema.json"
  copy_file "${COMMON_DIR}/schemas/consensus-exclusions.schema.json" "${target_project}/.codex/skills/reviewer/schemas/consensus-exclusions.schema.json"
  copy_file "${COMMON_DIR}/schemas/review-backlog.schema.json" "${target_project}/.codex/skills/reviewer/schemas/review-backlog.schema.json"
  copy_file "${COMMON_DIR}/schemas/workflow-state.schema.json" "${target_project}/.codex/skills/reviewer/schemas/workflow-state.schema.json"
  copy_file "${COMMON_DIR}/bin/reviewer-run.sh" "${target_project}/.codex/skills/reviewer/bin/reviewer-run.sh"
  chmod +x "${target_project}/.codex/skills/reviewer/bin/reviewer-run.sh"

  upsert_agents_block "${target_project}/AGENTS.md"

  echo "已初始化 Codex 版 reviewer 工作流:"
  echo "- 目标项目: ${target_project}"
  echo "- skill: .codex/skills/reviewer/SKILL.md"
  echo "- compatibility launcher/helper: .codex/skills/reviewer/bin/reviewer-run.sh"
  echo "- schemas: .codex/skills/reviewer/schemas/"
  echo "- prompts: .codex/skills/reviewer/prompts/"
  echo "- plans: .codex/plans/"
}

main "$@"
