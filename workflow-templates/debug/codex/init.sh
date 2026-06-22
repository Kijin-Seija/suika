#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_DIR="${SCRIPT_DIR}"
COMMON_DIR="${SCRIPT_DIR}/../common"

BEGIN_MARKER="<!-- BEGIN debug -->"
END_MARKER="<!-- END debug -->"

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
  cat <<'BLOCK'
<!-- BEGIN debug -->
## Debug 工作流

当用户显式要求以下任一调试模式时，优先使用对应的项目级 skill：

- `.codex/skills/debug-auto/SKILL.md`
- `.codex/skills/debug-steps/SKILL.md`
- `.codex/skills/debug-manual/SKILL.md`

不要默认对所有普通请求启用该流程；只有用户明确要求时才触发。

三种模式的职责分别是：

- `debug auto`：agent 使用 Playwright 或等价浏览器自动化能力启动项目、自动操作页面、监听运行日志并分析问题
- `debug steps`：用户手动操作并反馈，agent 启动本地日志服务器自动收集浏览器日志后分析
- `debug manual`：不启动日志服务器；agent 在代码中添加临时 `console` 日志，用户复现后上传日志，再基于日志分析问题

相关资源位于：

- `.codex/skills/debug-steps/bin/debug-session.sh`
- `.codex/skills/debug-steps/bin/debug_log_server.py`
- `.codex/skills/debug-steps/reference.md`
<!-- END debug -->
BLOCK
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

  remove_if_exists "${target_project}/.codex/skills/debug"
  remove_if_exists "${target_project}/.codex/skills/debug-auto"
  remove_if_exists "${target_project}/.codex/skills/debug-steps"
  remove_if_exists "${target_project}/.codex/skills/debug-manual"
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
    "${target_project}/.codex/skills/debug-auto" \
    "${target_project}/.codex/skills/debug-steps/bin" \
    "${target_project}/.codex/skills/debug-manual"

  copy_file "${CODEX_DIR}/skills/debug-auto/SKILL.md" "${target_project}/.codex/skills/debug-auto/SKILL.md"
  copy_file "${CODEX_DIR}/skills/debug-steps/SKILL.md" "${target_project}/.codex/skills/debug-steps/SKILL.md"
  copy_file "${CODEX_DIR}/skills/debug-manual/SKILL.md" "${target_project}/.codex/skills/debug-manual/SKILL.md"
  copy_file "${CODEX_DIR}/reference-steps.md" "${target_project}/.codex/skills/debug-steps/reference.md"
  copy_file "${COMMON_DIR}/bin/debug-session.sh" "${target_project}/.codex/skills/debug-steps/bin/debug-session.sh"
  copy_file "${COMMON_DIR}/bin/debug_log_server.py" "${target_project}/.codex/skills/debug-steps/bin/debug_log_server.py"
  chmod +x \
    "${target_project}/.codex/skills/debug-steps/bin/debug-session.sh" \
    "${target_project}/.codex/skills/debug-steps/bin/debug_log_server.py"

  upsert_agents_block "${target_project}/AGENTS.md"

  echo "已初始化 Codex 版 debug 工作流:"
  echo "- 目标项目: ${target_project}"
  echo "- skills:"
  echo "  - .codex/skills/debug-auto/SKILL.md"
  echo "  - .codex/skills/debug-steps/SKILL.md"
  echo "  - .codex/skills/debug-manual/SKILL.md"
  echo "- launcher: .codex/skills/debug-steps/bin/debug-session.sh"
}

main "$@"
