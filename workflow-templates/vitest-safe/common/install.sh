#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_WRAPPER="${SCRIPT_DIR}/bin/vitest-safe"
HOST_KIND="${VITEST_SAFE_HOST:-codex}"

case "${HOST_KIND}" in
  codex)
    HOST_LABEL="Codex"
    HOST_HOME_DIR="${CODEX_HOME:-${HOME}/.codex}"
    INSTRUCTIONS_PATH="${HOST_HOME_DIR}/AGENTS.md"
    ;;
  claude)
    HOST_LABEL="Claude Code"
    HOST_HOME_DIR="${CLAUDE_HOME:-${HOME}/.claude}"
    INSTRUCTIONS_PATH="${HOST_HOME_DIR}/CLAUDE.md"
    ;;
  *)
    echo "错误: 不支持的宿主: ${HOST_KIND}" >&2
    exit 1
    ;;
esac

SOURCE_SKILL_DIR="${SCRIPT_DIR}/../${HOST_KIND}/skill"
SKILL_DESTINATION="${HOST_HOME_DIR}/skills/vitest-safe"
WRAPPER_DESTINATION="${HOST_HOME_DIR}/bin/vitest-safe"
HOST_STATE_DIR="${HOST_HOME_DIR}/vitest-safe"
HOST_CONFIG_PATH="${HOST_STATE_DIR}/config.json"
SHARED_STATE_DIR="${VITEST_SAFE_STATE_DIR:-${XDG_STATE_HOME:-${HOME}/.local/state}/suika-vitest-safe}"
SHARED_CONFIG_PATH="${SHARED_STATE_DIR}/config.json"
DEFAULT_LOCK_DIR="${SHARED_STATE_DIR}/locks"
BEGIN_MARKER="<!-- BEGIN vitest-safe -->"
END_MARKER="<!-- END vitest-safe -->"

usage() {
  cat >&2 <<'EOF'
用法:
  init.sh [--max-concurrent <n>]     全局安装 Vitest Safe（默认上限 2）
  init.sh --remove                   卸载当前宿主的 Vitest Safe
EOF
}

require_positive_integer() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]] || {
    echo "错误: --max-concurrent 必须是正整数: $1" >&2
    exit 1
  }
}

validate_managed_config() {
  local path="$1"
  [[ -e "${path}" ]] || return 0
  [[ -f "${path}" ]] || {
    echo "错误: 配置路径不是普通文件，拒绝覆盖: ${path}" >&2
    exit 1
  }
  python3 - "${path}" <<'PY'
import json, sys
path = sys.argv[1]
try:
    value = json.load(open(path, encoding="utf-8"))
except (OSError, json.JSONDecodeError) as exc:
    raise SystemExit(f"现有配置不可读取: {exc}")
if value.get("managed_by") != "suika-vitest-safe":
    raise SystemExit(f"现有配置不是由 Vitest Safe 安装器创建的: {path}")
PY
}

config_field() {
  local path="$1"
  local field="$2"
  [[ -f "${path}" ]] || return 0
  python3 - "${path}" "${field}" <<'PY'
import json, sys
value = json.load(open(sys.argv[1], encoding="utf-8")).get(sys.argv[2], "")
if value != "": print(value)
PY
}

ensure_owned_symlink() {
  local destination="$1"
  local source="$2"
  if [[ -L "${destination}" ]]; then
    [[ "$(readlink "${destination}")" == "${source}" ]] || {
      echo "错误: 已存在指向其他位置的 symlink，拒绝覆盖: ${destination}" >&2
      exit 1
    }
    return
  fi
  [[ ! -e "${destination}" ]] || {
    echo "错误: 已存在非本安装器创建的路径，拒绝覆盖: ${destination}" >&2
    exit 1
  }
  ln -s "${source}" "${destination}"
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

write_json_configs() {
  local max_concurrent="$1"
  local lock_dir="$2"
  mkdir -p "${SHARED_STATE_DIR}" "${HOST_STATE_DIR}"
  python3 - "${SHARED_CONFIG_PATH}" "${HOST_CONFIG_PATH}" "${max_concurrent}" "${lock_dir}" "${HOST_KIND}" <<'PY'
import json, os, sys, tempfile
runtime_path, host_path, max_concurrent, lock_dir, host_kind = sys.argv[1:]
runtime = {
    "managed_by": "suika-vitest-safe", "version": 2,
    "max_concurrent": int(max_concurrent), "lock_dir": os.path.abspath(lock_dir),
}
descriptor = {
    "managed_by": "suika-vitest-safe", "version": 2, "host": host_kind,
    "runtime_config": os.path.abspath(runtime_path),
}
for path, payload in ((runtime_path, runtime), (host_path, descriptor)):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".config.", dir=os.path.dirname(path))
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)
PY
}

instructions_block() {
  cat <<EOF
${BEGIN_MARKER}
## Vitest Safe

当命令会执行任何项目测试，尤其是 Vitest，或项目脚本已确认会启动测试时，${HOST_LABEL} 必须使用全局队列：

- skill: ${SKILL_DESTINATION}/SKILL.md
- wrapper: ${WRAPPER_DESTINATION}

执行格式必须是：

    ${WRAPPER_DESTINATION} -- <原始命令>

禁止直接调用 \`vitest\`、\`pnpm exec vitest\`、\`npm exec vitest\`，也禁止直接调用已知会启动测试的 \`test\` package script。先检查脚本实际执行的内容；一旦确认它是测试命令，整个命令都要通过 wrapper。

不要为了绕过队列而并行启动完整测试套件；Codex 与 Claude Code 共用同一队列。
${END_MARKER}
EOF
}

remove_instructions_block() {
  local file="$1"
  local temporary
  [[ -f "${file}" ]] || return 0
  temporary="$(mktemp)"
  awk -v begin="${BEGIN_MARKER}" -v end="${END_MARKER}" '
    BEGIN { inside = 0 }
    $0 == begin { inside = 1; next }
    $0 == end { inside = 0; next }
    inside { next }
    { lines[++count] = $0 }
    END { while (count > 0 && lines[count] == "") count--; for (i=1; i<=count; i++) print lines[i] }
  ' "${file}" > "${temporary}"
  mv "${temporary}" "${file}"
}

upsert_instructions_block() {
  mkdir -p "$(dirname "${INSTRUCTIONS_PATH}")"
  remove_instructions_block "${INSTRUCTIONS_PATH}"
  [[ ! -s "${INSTRUCTIONS_PATH}" ]] || printf '\n' >> "${INSTRUCTIONS_PATH}"
  instructions_block >> "${INSTRUCTIONS_PATH}"
}

install_skill() {
  local requested_max="$1"
  local max_concurrent="${requested_max}"
  local lock_dir=""
  local legacy_codex_config="${CODEX_HOME:-${HOME}/.codex}/vitest-safe/config.json"

  [[ -f "${SOURCE_SKILL_DIR}/SKILL.md" ]] || {
    echo "错误: 缺少 skill 源文件: ${SOURCE_SKILL_DIR}/SKILL.md" >&2
    exit 1
  }
  [[ -f "${SOURCE_WRAPPER}" ]] || {
    echo "错误: 缺少 vitest-safe 包装器: ${SOURCE_WRAPPER}" >&2
    exit 1
  }
  [[ -z "${requested_max}" ]] || require_positive_integer "${requested_max}"
  validate_managed_config "${HOST_CONFIG_PATH}"
  validate_managed_config "${SHARED_CONFIG_PATH}"
  if [[ "${legacy_codex_config}" != "${HOST_CONFIG_PATH}" ]]; then
    validate_managed_config "${legacy_codex_config}"
  fi

  if [[ -z "${max_concurrent}" ]]; then
    max_concurrent="$(config_field "${SHARED_CONFIG_PATH}" max_concurrent || true)"
  fi
  if [[ -z "${max_concurrent}" ]]; then
    max_concurrent="$(config_field "${HOST_CONFIG_PATH}" max_concurrent || true)"
  fi
  if [[ -z "${max_concurrent}" && "${legacy_codex_config}" != "${HOST_CONFIG_PATH}" ]]; then
    max_concurrent="$(config_field "${legacy_codex_config}" max_concurrent || true)"
  fi
  [[ -n "${max_concurrent}" ]] || max_concurrent=2
  require_positive_integer "${max_concurrent}"

  lock_dir="$(config_field "${SHARED_CONFIG_PATH}" lock_dir || true)"
  [[ -n "${lock_dir}" ]] || lock_dir="$(config_field "${HOST_CONFIG_PATH}" lock_dir || true)"
  if [[ -z "${lock_dir}" && "${legacy_codex_config}" != "${HOST_CONFIG_PATH}" ]]; then
    lock_dir="$(config_field "${legacy_codex_config}" lock_dir || true)"
  fi
  [[ -n "${lock_dir}" ]] || lock_dir="${DEFAULT_LOCK_DIR}"

  mkdir -p "${HOST_HOME_DIR}/skills" "${HOST_HOME_DIR}/bin"
  ensure_owned_symlink "${SKILL_DESTINATION}" "${SOURCE_SKILL_DIR}"
  ensure_owned_symlink "${WRAPPER_DESTINATION}" "${SOURCE_WRAPPER}"
  write_json_configs "${max_concurrent}" "${lock_dir}"
  upsert_instructions_block

  echo "已为 ${HOST_LABEL} 全局安装 Vitest Safe:"
  echo "- skill: ${SKILL_DESTINATION}/SKILL.md"
  echo "- wrapper: ${WRAPPER_DESTINATION}"
  echo "- 最大并发测试数量: ${max_concurrent}"
  echo "- 共享配置: ${SHARED_CONFIG_PATH}"
}

remove_install() {
  validate_managed_config "${HOST_CONFIG_PATH}"
  remove_owned_symlink "${SKILL_DESTINATION}" "${SOURCE_SKILL_DIR}"
  remove_owned_symlink "${WRAPPER_DESTINATION}" "${SOURCE_WRAPPER}"
  [[ ! -f "${HOST_CONFIG_PATH}" ]] || rm "${HOST_CONFIG_PATH}"
  rmdir "${HOST_STATE_DIR}" 2>/dev/null || true
  remove_instructions_block "${INSTRUCTIONS_PATH}"
  echo "已卸载 ${HOST_LABEL} 版 Vitest Safe；共享队列和锁文件已保留。"
}

main() {
  local mode="install"
  local max_concurrent=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --max-concurrent)
        [[ $# -ge 2 ]] || { usage; exit 1; }
        max_concurrent="$2"
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
  if [[ "${mode}" == "remove" ]]; then
    remove_install
  else
    install_skill "${max_concurrent}"
  fi
}

main "$@"
