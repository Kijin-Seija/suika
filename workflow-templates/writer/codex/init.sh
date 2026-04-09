#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_DIR="${SCRIPT_DIR}"
COMMON_DIR="${SCRIPT_DIR}/../common"

BEGIN_MARKER="<!-- BEGIN writer -->"
END_MARKER="<!-- END writer -->"
LEGACY_BEGIN_MARKER="<!-- BEGIN implementation-loop -->"
LEGACY_END_MARKER="<!-- END implementation-loop -->"

usage() {
  echo "用法: $0 [--default-writer <claude|codex>] <target-project>" >&2
}

validate_writer_kind() {
  local writer_kind="$1"
  [[ "${writer_kind}" == "claude" || "${writer_kind}" == "codex" ]] || {
    echo "错误: --default-writer 只能是 claude 或 codex" >&2
    exit 1
  }
}

write_writer_config() {
  local destination="$1"
  local default_writer="$2"

  cat > "${destination}" <<EOF
WRITER_DEFAULT_WRITER=${default_writer}
EOF
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
  local default_writer="$1"
  local template

  template="$(cat <<'EOF'
<!-- BEGIN writer -->
## 实现闭环工作流

当用户显式要求使用 `writer skill`、`writer workflow`、`实现闭环工作流`、`让 Claude Code 开发并由 Codex 审查` 时，优先使用项目级 skill：

- `.codex/skills/writer/SKILL.md`

不要默认对所有普通请求启用该流程；只有用户明确要求时才触发。

该工作流适用于会落盘到仓库的制品任务：

- Codex 负责流程调度和审查
- writer 可选 Claude Code 或独立 Codex 子进程来负责开发、制品编写和修订
- 项目默认 writer: `__DEFAULT_WRITER__`；用户未显式指定时按此值执行
- 支持代码实现，以及 OpenSpec proposal/design/spec/tasks 等制品任务
- 默认最大审查轮次为 `5`

运行产物保存在：

- `.codex/plans/<topic-slug>/`
<!-- END writer -->
EOF
)"

  printf '%s\n' "${template//__DEFAULT_WRITER__/${default_writer}}"
}

upsert_agents_block() {
  local file="$1"
  local default_writer="$2"
  local block
  local block_file
  local tmp_file

  block="$(agents_block "${default_writer}")"
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

  remove_if_exists "${target_project}/.codex/skills/implementation-loop"
  remove_if_exists "${target_project}/.codex/skills/writer"
}

main() {
  local target_project
  local default_writer="claude"

  while [[ $# -gt 0 ]]; do
    case "${1-}" in
      --default-writer)
        default_writer="${2-}"
        shift 2
        ;;
      --)
        shift
        break
        ;;
      -*)
        usage
        exit 1
        ;;
      *)
        break
        ;;
    esac
  done

  [[ $# -eq 1 ]] || {
    usage
    exit 1
  }

  validate_writer_kind "${default_writer}"
  target_project="$1"
  require_directory "${target_project}"

  clean_legacy_install "${target_project}"

  mkdir -p \
    "${target_project}/.codex/skills/writer" \
    "${target_project}/.codex/skills/writer/prompts" \
    "${target_project}/.codex/skills/writer/schemas" \
    "${target_project}/.codex/skills/writer/bin" \
    "${target_project}/.codex/plans"

  copy_file "${CODEX_DIR}/skill/SKILL.md" "${target_project}/.codex/skills/writer/SKILL.md"
  copy_file "${COMMON_DIR}/reference.md" "${target_project}/.codex/skills/writer/reference.md"
  copy_file "${COMMON_DIR}/prompts/claude-code-draft.md" "${target_project}/.codex/skills/writer/prompts/claude-code-draft.md"
  copy_file "${COMMON_DIR}/prompts/claude-code-revision.md" "${target_project}/.codex/skills/writer/prompts/claude-code-revision.md"
  copy_file "${COMMON_DIR}/prompts/codex-review.md" "${target_project}/.codex/skills/writer/prompts/codex-review.md"
  copy_file "${COMMON_DIR}/prompts/dispute-report.md" "${target_project}/.codex/skills/writer/prompts/dispute-report.md"
  copy_file "${COMMON_DIR}/schemas/claude-draft.schema.json" "${target_project}/.codex/skills/writer/schemas/claude-draft.schema.json"
  copy_file "${COMMON_DIR}/schemas/claude-response.schema.json" "${target_project}/.codex/skills/writer/schemas/claude-response.schema.json"
  copy_file "${COMMON_DIR}/schemas/codex-review.schema.json" "${target_project}/.codex/skills/writer/schemas/codex-review.schema.json"
  copy_file "${COMMON_DIR}/bin/writer-run.sh" "${target_project}/.codex/skills/writer/bin/writer-run.sh"
  write_writer_config "${target_project}/.codex/skills/writer/config.env" "${default_writer}"
  chmod +x "${target_project}/.codex/skills/writer/bin/writer-run.sh"

  upsert_agents_block "${target_project}/AGENTS.md" "${default_writer}"

  echo "已初始化 Codex 版实现闭环工作流:"
  echo "- 目标项目: ${target_project}"
  echo "- default writer: ${default_writer}"
  echo "- skill: .codex/skills/writer/SKILL.md"
  echo "- launcher: .codex/skills/writer/bin/writer-run.sh"
  echo "- outputs: .codex/plans/"
}

main "$@"
