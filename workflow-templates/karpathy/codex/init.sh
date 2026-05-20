#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_DIR="${SCRIPT_DIR}"
COMMON_DIR="${SCRIPT_DIR}/../common"

BEGIN_MARKER="<!-- BEGIN karpathy -->"
END_MARKER="<!-- END karpathy -->"

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
<!-- BEGIN karpathy -->
## Karpathy 编码守则

在大多数非琐碎的编码、review、重构、排障等工程任务中，默认优先使用项目级 skill：

- `.codex/skills/karpathy/SKILL.md`

以下场景可以不完整启用，按更轻量方式处理：

- 纯闲聊或纯说明
- 纯翻译
- 纯信息查询
- 显而易见的一行式机械改动

该 skill 用于在编码、review、重构、排障等工程任务中约束 Codex：

- 先显式暴露关键假设和歧义
- 优先最小实现，避免过度设计
- 只做与需求直接相关的外科式修改
- 把任务改写成可验证的成功标准

补充参考位于：

- `.codex/skills/karpathy/reference.md`
<!-- END karpathy -->
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

  remove_if_exists "${target_project}/.codex/skills/karpathy"
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

  mkdir -p "${target_project}/.codex/skills/karpathy"

  copy_file "${CODEX_DIR}/skill/SKILL.md" "${target_project}/.codex/skills/karpathy/SKILL.md"
  copy_file "${COMMON_DIR}/reference.md" "${target_project}/.codex/skills/karpathy/reference.md"

  upsert_agents_block "${target_project}/AGENTS.md"

  echo "已初始化 Codex 版 karpathy skill:"
  echo "- 目标项目: ${target_project}"
  echo "- skill: .codex/skills/karpathy/SKILL.md"
  echo "- reference: .codex/skills/karpathy/reference.md"
}

main "$@"
