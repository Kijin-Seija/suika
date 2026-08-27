#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT_INSTALLER="${ROOT_DIR}/init.sh"
CODEX_INSTALLER="${ROOT_DIR}/codex/init.sh"
CLAUDE_INSTALLER="${ROOT_DIR}/claude/init.sh"
TMP_ROOT="${ROOT_DIR}/.tmp-tests"
TMP_DIR="${TMP_ROOT}/installers"
rm -rf "${TMP_DIR}"
mkdir -p "${TMP_DIR}"
trap 'rm -rf "${TMP_ROOT}"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_file() {
  local path="$1"
  [[ -f "${path}" ]] || fail "missing file: ${path}"
}

assert_contains() {
  local path="$1"
  local expected="$2"
  grep -Fq -- "${expected}" "${path}" || fail "expected '${expected}' in ${path}"
}

run_codex_install_test() {
  local target="${TMP_DIR}/codex-target"
  mkdir -p "${target}"

  assert_file "${CODEX_INSTALLER}"
  bash "${CODEX_INSTALLER}" "${target}"

  assert_file "${target}/.codex/skills/karpathy/SKILL.md"
  assert_file "${target}/.codex/skills/karpathy/reference.md"
  assert_file "${target}/AGENTS.md"

  assert_contains "${target}/AGENTS.md" ".codex/skills/karpathy/SKILL.md"
  assert_contains "${target}/AGENTS.md" "默认优先使用项目级 skill"
  assert_contains "${target}/AGENTS.md" "显而易见的一行式机械改动"
  assert_contains "${target}/AGENTS.md" "可验证的成功标准"
  assert_contains "${target}/.codex/skills/karpathy/SKILL.md" "默认用于大多数非琐碎工程任务"
  assert_contains "${target}/.codex/skills/karpathy/SKILL.md" "纯信息查询"
  assert_contains "${target}/.codex/skills/karpathy/SKILL.md" "先想清楚再编码"
  assert_contains "${target}/.codex/skills/karpathy/SKILL.md" "简单优先"
  assert_contains "${target}/.codex/skills/karpathy/SKILL.md" "外科式改动"
  assert_contains "${target}/.codex/skills/karpathy/SKILL.md" "目标驱动执行"
  assert_contains "${target}/.codex/skills/karpathy/reference.md" "给用户数据加一个导出功能"
  assert_contains "${target}/.codex/skills/karpathy/reference.md" "把搜索做快一点"
}

run_root_default_install_test() {
  local target="${TMP_DIR}/root-default-target"
  mkdir -p "${target}"

  assert_file "${ROOT_INSTALLER}"
  bash "${ROOT_INSTALLER}" "${target}"

  assert_file "${target}/.codex/skills/karpathy/SKILL.md"
}

run_root_codex_install_test() {
  local target="${TMP_DIR}/root-codex-target"
  mkdir -p "${target}"

  bash "${ROOT_INSTALLER}" --codex "${target}"

  assert_file "${target}/.codex/skills/karpathy/SKILL.md"
}

run_claude_install_test() {
  local target="${TMP_DIR}/claude-target"
  mkdir -p "${target}"

  bash "${ROOT_INSTALLER}" --claude "${target}"
  assert_file "${target}/.claude/skills/karpathy/SKILL.md"
  assert_file "${target}/.claude/skills/karpathy/reference.md"
  assert_contains "${target}/.claude/skills/karpathy/SKILL.md" "Claude Code"
  assert_contains "${target}/.claude/skills/karpathy/SKILL.md" ".claude/skills/karpathy/reference.md"
  [[ ! -e "${target}/CLAUDE.md" ]] || fail "Claude project skill install should not create CLAUDE.md"
}

run_codex_install_test
run_root_default_install_test
run_root_codex_install_test
run_claude_install_test
cmp \
  "${TMP_DIR}/codex-target/.codex/skills/karpathy/reference.md" \
  "${TMP_DIR}/claude-target/.claude/skills/karpathy/reference.md"

echo "PASS: karpathy root, Codex, and Claude Code installers"
