#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_SKILL_DIR="${SCRIPT_DIR}/../common/skill"

BEGIN_MARKER="<!-- BEGIN grill-with-docs -->"
END_MARKER="<!-- END grill-with-docs -->"

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

copy_skill() {
  local destination="$1"

  rm -rf "${destination}"
  mkdir -p "${destination}"
  cp "${COMMON_SKILL_DIR}/SKILL.md" "${destination}/SKILL.md"
  cp "${COMMON_SKILL_DIR}/CONTEXT-FORMAT.md" "${destination}/CONTEXT-FORMAT.md"
  cp "${COMMON_SKILL_DIR}/ADR-FORMAT.md" "${destination}/ADR-FORMAT.md"
  cp "${COMMON_SKILL_DIR}/LICENSE" "${destination}/LICENSE"
}

agents_block() {
  cat <<'EOF'
<!-- BEGIN grill-with-docs -->
## Grill with docs

当用户希望质询、推敲或压力测试一个方案、设计或计划时，使用项目级 skill：

- `.codex/skills/grill-with-docs/SKILL.md`

该 skill 会结合代码与现有领域文档逐项追问，并在术语或架构决策明确后按需维护：

- `CONTEXT.md` 或 `CONTEXT-MAP.md` 指向的上下文词汇表
- `docs/adr/` 下的重要架构决策记录

一次只提出一个问题，并为问题提供推荐答案。能从代码库确认的内容应先自行检查。
<!-- END grill-with-docs -->
EOF
}

upsert_agents_block() {
  local file="$1"
  local block_file
  local tmp_file

  block_file="$(mktemp)"
  tmp_file="$(mktemp)"
  agents_block > "${block_file}"

  if [[ -f "${file}" ]]; then
    awk \
      -v begin_marker="${BEGIN_MARKER}" \
      -v end_marker="${END_MARKER}" \
      -v block_file="${block_file}" '
      function print_block(   line) {
        while ((getline line < block_file) > 0) {
          print line
        }
        close(block_file)
      }
      BEGIN { inside = 0 }
      $0 == begin_marker { inside = 1; next }
      $0 == end_marker { inside = 0; next }
      inside { next }
      { print }
      END {
        if (NR > 0) {
          print ""
        }
        print_block()
      }
    ' "${file}" > "${tmp_file}"
  else
    cp "${block_file}" "${tmp_file}"
  fi

  mv "${tmp_file}" "${file}"
  rm -f "${block_file}"
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
  destination="${target_project}/.codex/skills/grill-with-docs"

  copy_skill "${destination}"
  upsert_agents_block "${target_project}/AGENTS.md"

  echo "已安装 Codex 版 grill-with-docs:"
  echo "- 目标项目: ${target_project}"
  echo "- skill: .codex/skills/grill-with-docs/SKILL.md"
}

main "$@"
