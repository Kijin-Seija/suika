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

该工作流通过 launcher 启动外部 Codex reviewer 子进程，而不是在对话里抽象描述“外部 reviewer”：

- `.claude/skills/reviewer/bin/reviewer-run.sh`
- `.claude/skills/reviewer/schemas/codex-review.schema.json`

该工作流支持两类制品：`code`（代码变更）和 `doc`（计划、分析、说明文档）。

外部 reviewer 必须复用当前工作区，在同一项目目录中执行 `codex exec -C <project> -s read-only`；默认模型为 `gpt-5.4`，可通过 `REVIEWER_CODEX_REVIEW_MODEL` 覆盖。

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
  copy_file "${COMMON_DIR}/prompts/codex-review-request.md" "${target_project}/.claude/skills/reviewer/prompts/codex-review-request.md"
  copy_file "${COMMON_DIR}/prompts/claude-review-response.md" "${target_project}/.claude/skills/reviewer/prompts/claude-review-response.md"
  copy_file "${COMMON_DIR}/prompts/dispute-report.md" "${target_project}/.claude/skills/reviewer/prompts/dispute-report.md"
  copy_file "${COMMON_DIR}/schemas/codex-review.schema.json" "${target_project}/.claude/skills/reviewer/schemas/codex-review.schema.json"
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
