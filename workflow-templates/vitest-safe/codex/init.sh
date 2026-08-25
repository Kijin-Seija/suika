#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_SKILL_DIR="${SCRIPT_DIR}/skill"
SOURCE_WRAPPER="${SCRIPT_DIR}/../common/bin/vitest-safe"

CODEX_HOME_DIR="${CODEX_HOME:-${HOME}/.codex}"
SKILLS_DIR="${CODEX_HOME_DIR}/skills"
SKILL_DESTINATION="${SKILLS_DIR}/vitest-safe"
BIN_DIR="${CODEX_HOME_DIR}/bin"
WRAPPER_DESTINATION="${BIN_DIR}/vitest-safe"
STATE_DIR="${CODEX_HOME_DIR}/vitest-safe"
CONFIG_PATH="${STATE_DIR}/config.json"
DEFAULT_LOCK_DIR="${STATE_DIR}/locks"
AGENTS_PATH="${CODEX_HOME_DIR}/AGENTS.md"

BEGIN_MARKER="<!-- BEGIN vitest-safe -->"
END_MARKER="<!-- END vitest-safe -->"

usage() {
  cat >&2 <<'EOF'
用法:
  init.sh [--max-concurrent <n>]     全局安装 Vitest Safe（默认上限 2）
  init.sh --remove                   卸载全局 Vitest Safe
EOF
}

require_positive_integer() {
  local value="$1"
  [[ "${value}" =~ ^[1-9][0-9]*$ ]] || {
    echo "错误: --max-concurrent 必须是正整数: ${value}" >&2
    exit 1
  }
}

require_source_files() {
  [[ -f "${SOURCE_SKILL_DIR}/SKILL.md" ]] || {
    echo "错误: 缺少 skill 源文件: ${SOURCE_SKILL_DIR}/SKILL.md" >&2
    exit 1
  }
  [[ -f "${SOURCE_SKILL_DIR}/agents/openai.yaml" ]] || {
    echo "错误: 缺少 skill UI 配置: ${SOURCE_SKILL_DIR}/agents/openai.yaml" >&2
    exit 1
  }
  [[ -x "${SOURCE_WRAPPER}" || -f "${SOURCE_WRAPPER}" ]] || {
    echo "错误: 缺少 vitest-safe 包装器: ${SOURCE_WRAPPER}" >&2
    exit 1
  }
}

ensure_owned_symlink() {
  local destination="$1"
  local source="$2"

  if [[ -L "${destination}" ]]; then
    [[ "$(readlink "${destination}")" == "${source}" ]] || {
      echo "错误: 已存在指向其他位置的 symlink，拒绝覆盖: ${destination}" >&2
      exit 1
    }
    return 0
  fi
  if [[ -e "${destination}" ]]; then
    echo "错误: 已存在非本安装器创建的路径，拒绝覆盖: ${destination}" >&2
    echo "请先备份并移走该路径后重试。" >&2
    exit 1
  fi

  ln -s "${source}" "${destination}"
}

validate_existing_config() {
  [[ -e "${CONFIG_PATH}" ]] || return 0
  [[ -f "${CONFIG_PATH}" ]] || {
    echo "错误: 配置路径不是普通文件，拒绝覆盖: ${CONFIG_PATH}" >&2
    exit 1
  }

  python3 - "${CONFIG_PATH}" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as handle:
        config = json.load(handle)
except (OSError, json.JSONDecodeError) as exc:
    raise SystemExit(f"现有配置不可读取: {exc}")

if config.get("managed_by") != "suika-vitest-safe":
    raise SystemExit("现有配置不是由 Vitest Safe 安装器创建的")
try:
    if int(config["max_concurrent"]) < 1:
        raise ValueError
except (KeyError, TypeError, ValueError):
    raise SystemExit("现有配置中的 max_concurrent 无效")
PY
}

existing_max_concurrent() {
  [[ -f "${CONFIG_PATH}" ]] || return 0
  python3 - "${CONFIG_PATH}" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    print(int(json.load(handle)["max_concurrent"]))
PY
}

existing_lock_dir() {
  [[ -f "${CONFIG_PATH}" ]] || return 0
  python3 - "${CONFIG_PATH}" <<'PY'
import json
import sys

value = json.load(open(sys.argv[1], "r", encoding="utf-8")).get("lock_dir", "")
if value:
    print(value)
PY
}

write_config() {
  local max_concurrent="$1"
  local lock_dir="$2"
  local temporary

  mkdir -p "${STATE_DIR}"
  temporary="$(mktemp "${STATE_DIR}/.config.XXXXXX")"
  python3 - "${temporary}" "${max_concurrent}" "${lock_dir}" <<'PY'
import json
import os
import sys

path, max_concurrent, lock_dir = sys.argv[1:]
payload = {
    "managed_by": "suika-vitest-safe",
    "version": 1,
    "max_concurrent": int(max_concurrent),
    "lock_dir": os.path.abspath(lock_dir),
}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
os.chmod(path, 0o600)
PY
  mv "${temporary}" "${CONFIG_PATH}"
}

agents_block() {
  cat <<EOF
${BEGIN_MARKER}
## Vitest Safe

当命令会执行任何项目测试，尤其是 Vitest，或项目脚本已确认会启动测试时，Codex 必须使用全局队列：

- skill: ${SKILL_DESTINATION}/SKILL.md
- wrapper: ${WRAPPER_DESTINATION}

执行格式必须是：

    ${WRAPPER_DESTINATION} -- <原始命令>

禁止直接调用 \`vitest\`、\`pnpm exec vitest\`、\`npm exec vitest\`，也禁止直接调用已知会启动测试的 \`test\` package script。先检查脚本实际执行的内容；一旦确认它是测试命令，整个命令都要通过 wrapper。只有明确不是测试的命令才可以不经过该队列。

不要为了绕过队列而并行启动完整测试套件；超过并发上限的调用必须等待已有 slot 释放。
${END_MARKER}
EOF
}

remove_agents_block() {
  local file="$1"
  local temporary

  [[ -f "${file}" ]] || return 0
  temporary="$(mktemp)"
  awk \
    -v begin_marker="${BEGIN_MARKER}" \
    -v end_marker="${END_MARKER}" '
    BEGIN { inside = 0 }
    $0 == begin_marker { inside = 1; next }
    $0 == end_marker { inside = 0; next }
    inside { next }
    { lines[++count] = $0 }
    END {
      while (count > 0 && lines[count] == "") count--
      for (i = 1; i <= count; i++) print lines[i]
    }
  ' "${file}" > "${temporary}"
  mv "${temporary}" "${file}"
}

upsert_agents_block() {
  local file="$1"
  local block_file

  mkdir -p "$(dirname "${file}")"
  remove_agents_block "${file}"
  block_file="$(mktemp)"
  agents_block > "${block_file}"
  if [[ -s "${file}" ]]; then
    printf '\n' >> "${file}"
  fi
  cat "${block_file}" >> "${file}"
  rm -f "${block_file}"
}

install() {
  local requested_max="$1"
  local max_concurrent="${requested_max}"
  local lock_dir="${DEFAULT_LOCK_DIR}"

  require_source_files
  if [[ -n "${requested_max}" ]]; then
    require_positive_integer "${requested_max}"
  fi
  validate_existing_config
  mkdir -p "${SKILLS_DIR}" "${BIN_DIR}"
  ensure_owned_symlink "${SKILL_DESTINATION}" "${SOURCE_SKILL_DIR}"
  ensure_owned_symlink "${WRAPPER_DESTINATION}" "${SOURCE_WRAPPER}"

  if [[ -z "${max_concurrent}" ]]; then
    max_concurrent="$(existing_max_concurrent || true)"
  fi
  [[ -n "${max_concurrent}" ]] || max_concurrent="2"
  require_positive_integer "${max_concurrent}"

  if [[ -z "${requested_max}" ]]; then
    lock_dir="$(existing_lock_dir || true)"
  fi
  [[ -n "${lock_dir}" ]] || lock_dir="${DEFAULT_LOCK_DIR}"
  write_config "${max_concurrent}" "${lock_dir}"
  upsert_agents_block "${AGENTS_PATH}"

  echo "已全局安装 Vitest Safe:"
  echo "- skill: ${SKILL_DESTINATION}/SKILL.md"
  echo "- wrapper: ${WRAPPER_DESTINATION}"
  echo "- 最大并发 Vitest 数量: ${max_concurrent}"
  echo "- 配置: ${CONFIG_PATH}"
}

remove_owned_symlink() {
  local destination="$1"
  local source="$2"

  if [[ -L "${destination}" ]]; then
    [[ "$(readlink "${destination}")" == "${source}" ]] || {
      echo "错误: symlink 指向其他位置，拒绝删除: ${destination}" >&2
      exit 1
    }
    rm "${destination}"
  elif [[ -e "${destination}" ]]; then
    echo "错误: 路径不是本安装器创建的 symlink，拒绝删除: ${destination}" >&2
    exit 1
  fi
}

remove_install() {
  validate_existing_config
  remove_owned_symlink "${SKILL_DESTINATION}" "${SOURCE_SKILL_DIR}"
  remove_owned_symlink "${WRAPPER_DESTINATION}" "${SOURCE_WRAPPER}"
  if [[ -f "${CONFIG_PATH}" ]]; then
    rm "${CONFIG_PATH}"
  fi
  rmdir "${STATE_DIR}/locks" 2>/dev/null || true
  rmdir "${STATE_DIR}" 2>/dev/null || true
  remove_agents_block "${AGENTS_PATH}"
  echo "已卸载 Vitest Safe（保留正在使用中的锁目录内容）。"
}

main() {
  local mode="install"
  local max_concurrent=""

  while [[ $# -gt 0 ]]; do
    case "${1}" in
      --max-concurrent)
        [[ $# -ge 2 ]] || { usage; exit 1; }
        max_concurrent="${2}"
        shift 2
        ;;
      --remove)
        mode="remove"
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        usage
        exit 1
        ;;
    esac
  done

  case "${mode}" in
    install) install "${max_concurrent}" ;;
    remove) remove_install ;;
  esac
}

main "$@"
