#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${SCRIPT_DIR}"
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

claude_block() {
  cat <<'EOF'
<!-- BEGIN reviewer -->
## Reviewer 工作流

当用户显式要求使用 reviewer 工作流时，优先使用项目级 skill：

- `.claude/skills/reviewer/SKILL.md`

不要默认对所有普通请求启用该流程；只有用户明确要求时才触发。

该工作流通过 launcher 执行“外层独立盲审 + 内层 Claude 修复/reviewer 复查”，而不是在对话里抽象描述“外部 reviewer”：

- `.claude/skills/reviewer/bin/reviewer-run.sh`
- `.claude/skills/reviewer/schemas/codex-review.schema.json`
- `.claude/skills/reviewer/schemas/consensus-exclusions.schema.json`
- `.claude/skills/reviewer/schemas/review-backlog.schema.json`
- `.claude/skills/reviewer/schemas/workflow-state.schema.json`

每次外层盲审都启动全新的外部 Codex 会话，只接收原始任务、原始 baseline、baseline diff 和真实工作区。盲审发现问题后，Claude 在同一盲审轮次内修订并通过带历史上下文的 follow-up 复查，达成一致后再启动下一次独立盲审。

新盲审还会接收 `consensus-exclusions.json` 中双方已确认的不成立/无需处理事项，以及 `review-backlog.json` 中不阻塞交付的已知 finding，但不会接收完整 review 历史。code 只有已观察到的 failing check/runtime reproduction/safe PoC 才进入修复循环；doc 可使用 document observation；未来风险和静态猜测进入 backlog。

Claude 修改前必须独立执行 reviewer 的 reproduction，并记录 verification-result/evidence；无法复现时不得修改，reviewer 必须修正复现或撤回 blocker。

每轮通过后先合并共识账本和 backlog，再删除该轮的 artifact、blind-review、response、revision 和 review 临时文件。brief、共识账本、backlog、最终/争议文件保留；未通过或需人工裁决时不清理。

每个主会话最多完成 10 次独立盲审；仍需继续时写入 `workflow-state.json` 和 `session-handoff.md`，旧会话停止，新会话通过 `reviewer-run.sh resume --topic <slug>` 恢复。

该工作流支持两类制品：`code`（代码变更）和 `doc`（计划、分析、说明文档）。

外部 reviewer 必须复用当前工作区，在同一项目目录中执行 `codex exec -C <project> -s read-only`，并忽略 `.codex/plans/` 与 `.claude/plans/`；默认模型为 `gpt-5.4`，可通过 `REVIEWER_CODEX_REVIEW_MODEL` 覆盖。普通会话默认最多启动 `5` 次独立盲审；一次独立盲审没有交付阻塞问题时稳定收敛，goal 模式最多 20 轮。

运行产物默认保存在：

- `.claude/plans/<topic-slug>/`
<!-- END reviewer -->
EOF
}

upsert_claude_block() {
  local file="$1"
  local block
  local block_file
  local tmp_file

  block="$(claude_block)"
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

  remove_if_exists "${target_project}/.claude/skills/reviewer"
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
    "${target_project}/.claude/skills/reviewer/prompts" \
    "${target_project}/.claude/skills/reviewer/schemas" \
    "${target_project}/.claude/skills/reviewer/bin" \
    "${target_project}/.claude/plans"

  copy_file "${CLAUDE_DIR}/skill/SKILL.md" "${target_project}/.claude/skills/reviewer/SKILL.md"
  copy_file "${COMMON_DIR}/reference.md" "${target_project}/.claude/skills/reviewer/reference.md"
  copy_file "${COMMON_DIR}/prompts/codex-blind-review-request.md" "${target_project}/.claude/skills/reviewer/prompts/codex-blind-review-request.md"
  copy_file "${COMMON_DIR}/prompts/codex-review-request.md" "${target_project}/.claude/skills/reviewer/prompts/codex-review-request.md"
  copy_file "${COMMON_DIR}/prompts/claude-review-response.md" "${target_project}/.claude/skills/reviewer/prompts/claude-review-response.md"
  copy_file "${COMMON_DIR}/prompts/dispute-report.md" "${target_project}/.claude/skills/reviewer/prompts/dispute-report.md"
  copy_file "${COMMON_DIR}/schemas/codex-review.schema.json" "${target_project}/.claude/skills/reviewer/schemas/codex-review.schema.json"
  copy_file "${COMMON_DIR}/schemas/consensus-exclusions.schema.json" "${target_project}/.claude/skills/reviewer/schemas/consensus-exclusions.schema.json"
  copy_file "${COMMON_DIR}/schemas/review-backlog.schema.json" "${target_project}/.claude/skills/reviewer/schemas/review-backlog.schema.json"
  copy_file "${COMMON_DIR}/schemas/workflow-state.schema.json" "${target_project}/.claude/skills/reviewer/schemas/workflow-state.schema.json"
  copy_file "${COMMON_DIR}/bin/reviewer-run.sh" "${target_project}/.claude/skills/reviewer/bin/reviewer-run.sh"
  chmod +x "${target_project}/.claude/skills/reviewer/bin/reviewer-run.sh"

  upsert_claude_block "${target_project}/CLAUDE.md"

  echo "已初始化 Claude Code 版 reviewer 工作流:"
  echo "- 目标项目: ${target_project}"
  echo "- skill: .claude/skills/reviewer/SKILL.md"
  echo "- launcher: .claude/skills/reviewer/bin/reviewer-run.sh"
  echo "- schemas: .claude/skills/reviewer/schemas/"
  echo "- prompts: .claude/skills/reviewer/prompts/"
  echo "- plans: .claude/plans/"
}

main "$@"
