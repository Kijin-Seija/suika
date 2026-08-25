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

assert_not_exists() {
  local path="$1"
  [[ ! -e "${path}" ]] || fail "unexpected path: ${path}"
}

assert_contains() {
  local path="$1"
  local expected="$2"
  grep -Fq -- "${expected}" "${path}" || fail "expected '${expected}' in ${path}"
}

assert_count() {
  local path="$1"
  local expected="$2"
  local text="$3"
  local actual

  actual="$(grep -Fc -- "${text}" "${path}")"
  [[ "${actual}" == "${expected}" ]] || fail "expected ${expected} occurrences of '${text}' in ${path}, got ${actual}"
}

assert_skill_files() {
  local skill_dir="$1"

  assert_file "${skill_dir}/SKILL.md"
  assert_file "${skill_dir}/CONTEXT-FORMAT.md"
  assert_file "${skill_dir}/ADR-FORMAT.md"
  assert_file "${skill_dir}/LICENSE"
  assert_contains "${skill_dir}/SKILL.md" "Ask the questions one at a time"
  assert_contains "${skill_dir}/SKILL.md" "Update CONTEXT.md inline"
  assert_contains "${skill_dir}/ADR-FORMAT.md" "Hard to reverse"
}

run_codex_install_test() {
  local target="${TMP_DIR}/codex-target"
  mkdir -p "${target}"
  printf '# Existing instructions\n' > "${target}/AGENTS.md"

  bash "${CODEX_INSTALLER}" "${target}"
  bash "${CODEX_INSTALLER}" "${target}"

  assert_skill_files "${target}/.codex/skills/grill-with-docs"
  assert_not_exists "${target}/.claude"
  assert_contains "${target}/AGENTS.md" "# Existing instructions"
  assert_contains "${target}/AGENTS.md" ".codex/skills/grill-with-docs/SKILL.md"
  assert_count "${target}/AGENTS.md" 1 "<!-- BEGIN grill-with-docs -->"
}

run_claude_install_test() {
  local target="${TMP_DIR}/claude-target"
  mkdir -p "${target}"

  bash "${CLAUDE_INSTALLER}" "${target}"

  assert_skill_files "${target}/.claude/skills/grill-with-docs"
  assert_not_exists "${target}/.codex"
  assert_not_exists "${target}/AGENTS.md"
}

run_root_default_install_test() {
  local target="${TMP_DIR}/root-default-target"
  mkdir -p "${target}"

  bash "${ROOT_INSTALLER}" "${target}"

  assert_skill_files "${target}/.codex/skills/grill-with-docs"
  assert_skill_files "${target}/.claude/skills/grill-with-docs"
  assert_file "${target}/AGENTS.md"
}

run_root_mode_tests() {
  local codex_target="${TMP_DIR}/root-codex-target"
  local claude_target="${TMP_DIR}/root-claude-target"
  mkdir -p "${codex_target}" "${claude_target}"

  bash "${ROOT_INSTALLER}" --codex "${codex_target}"
  assert_skill_files "${codex_target}/.codex/skills/grill-with-docs"
  assert_not_exists "${codex_target}/.claude"

  bash "${ROOT_INSTALLER}" --claude "${claude_target}"
  assert_skill_files "${claude_target}/.claude/skills/grill-with-docs"
  assert_not_exists "${claude_target}/.codex"
}

run_codex_install_test
run_claude_install_test
run_root_default_install_test
run_root_mode_tests

echo "PASS: grill-with-docs Codex and Claude Code installers"
