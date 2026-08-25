#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_SKILL_DIR="${SCRIPT_DIR}/explain-code"

BEGIN_MARKER="<!-- BEGIN explain-code -->"
END_MARKER="<!-- END explain-code -->"

usage() {
  cat >&2 <<'EOF'
用法:
  init.sh <target-project>          安装 explain-code skill
  init.sh --remove <target-project> 卸载 explain-code skill
EOF
}

require_directory() {
  local path="$1"
  [[ -d "${path}" ]] || {
    echo "错误: 目标目录不存在或不是目录: ${path}" >&2
    exit 1
  }
}

agents_block() {
  cat <<'EOF'
<!-- BEGIN explain-code -->
## Explain Code

本项目安装了说明书式代码解释 skill：

- `.codex/skills/explain-code/SKILL.md`

只有当用户显式写出 `$explain-code`，或明确要求使用 explain-code skill 时才启用。不要对普通代码问题自动应用。

可选调用深度：

- `$explain-code quick`：结论、主流程和关键源码落点
- `$explain-code`：默认的说明书式解释
- `$explain-code deep`：概览之后展开调用路径、状态变化和错误分支

该 skill 只改变解释结构，不授权修改代码。
<!-- END explain-code -->
EOF
}

remove_agents_block() {
  local file="$1"
  local tmp_file

  [[ -f "${file}" ]] || return 0

  tmp_file="$(mktemp)"
  awk \
    -v begin_marker="${BEGIN_MARKER}" \
    -v end_marker="${END_MARKER}" '
    BEGIN { inside = 0 }
    $0 == begin_marker { inside = 1; next }
    $0 == end_marker { inside = 0; next }
    inside { next }
    { lines[++count] = $0 }
    END {
      while (count > 0 && lines[count] == "") {
        count--
      }
      for (i = 1; i <= count; i++) {
        print lines[i]
      }
    }
  ' "${file}" > "${tmp_file}"
  mv "${tmp_file}" "${file}"
}

upsert_agents_block() {
  local file="$1"

  remove_agents_block "${file}"
  if [[ -s "${file}" ]]; then
    printf '\n' >> "${file}"
  fi
  agents_block >> "${file}"
}

install_skill() {
  local target_project="$1"
  local destination="${target_project}/.codex/skills/explain-code"

  rm -rf "${destination}"
  mkdir -p "${destination}/agents"
  cp "${SOURCE_SKILL_DIR}/SKILL.md" "${destination}/SKILL.md"
  cp "${SOURCE_SKILL_DIR}/agents/openai.yaml" "${destination}/agents/openai.yaml"
  upsert_agents_block "${target_project}/AGENTS.md"

  echo "已安装 Codex 版 explain-code skill:"
  echo "- 目标项目: ${target_project}"
  echo "- skill: .codex/skills/explain-code/SKILL.md"
  echo "- 调用: \$explain-code"
}

remove_skill() {
  local target_project="$1"
  local destination="${target_project}/.codex/skills/explain-code"

  rm -rf "${destination}"
  remove_agents_block "${target_project}/AGENTS.md"

  echo "已卸载 Codex 版 explain-code skill:"
  echo "- 目标项目: ${target_project}"
}

main() {
  local mode="install"
  local target_project

  case "${1-}" in
    --remove)
      mode="remove"
      shift
      ;;
  esac

  [[ $# -eq 1 ]] || {
    usage
    exit 1
  }

  target_project="$1"
  require_directory "${target_project}"

  case "${mode}" in
    install) install_skill "${target_project}" ;;
    remove) remove_skill "${target_project}" ;;
  esac
}

main "$@"
