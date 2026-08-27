#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT_INSTALLER="${ROOT_DIR}/init.sh"
CODEX_INSTALLER="${ROOT_DIR}/codex/init.sh"
CLAUDE_INSTALLER="${ROOT_DIR}/claude/init.sh"
TMP_ROOT="$(mktemp -d)"
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

assert_not_contains() {
  local path="$1"
  local unexpected="$2"
  if grep -Fq -- "${unexpected}" "${path}"; then
    fail "did not expect '${unexpected}' in ${path}"
  fi
}

assert_count() {
  local path="$1"
  local expected_count="$2"
  local text="$3"
  local actual_count

  actual_count="$(grep -Fc -- "${text}" "${path}" || true)"
  [[ "${actual_count}" == "${expected_count}" ]] || {
    fail "expected ${expected_count} occurrences of '${text}' in ${path}, got ${actual_count}"
  }
}

run_install_and_remove_test() {
  local target="${TMP_ROOT}/target"
  mkdir -p "${target}"
  printf '# Existing project rules\n' > "${target}/AGENTS.md"

  bash "${CODEX_INSTALLER}" "${target}"

  assert_file "${target}/.codex/skills/explain-code/SKILL.md"
  assert_file "${target}/.codex/skills/explain-code/agents/openai.yaml"
  assert_contains "${target}/AGENTS.md" '# Existing project rules'
  assert_contains "${target}/AGENTS.md" '<!-- BEGIN explain-code -->'
  assert_contains "${target}/AGENTS.md" '$explain-code'
  assert_contains "${target}/.codex/skills/explain-code/agents/openai.yaml" 'allow_implicit_invocation: false'
  assert_contains "${target}/.codex/skills/explain-code/SKILL.md" '先建立地图'

  bash "${CODEX_INSTALLER}" "${target}"
  assert_count "${target}/AGENTS.md" 1 '<!-- BEGIN explain-code -->'

  bash "${CODEX_INSTALLER}" --remove "${target}"
  assert_not_exists "${target}/.codex/skills/explain-code"
  assert_contains "${target}/AGENTS.md" '# Existing project rules'
  assert_not_contains "${target}/AGENTS.md" '<!-- BEGIN explain-code -->'
}

run_root_installer_test() {
  local target="${TMP_ROOT}/root-target"
  mkdir -p "${target}"

  bash "${ROOT_INSTALLER}" --codex "${target}"
  assert_file "${target}/.codex/skills/explain-code/SKILL.md"

  bash "${ROOT_INSTALLER}" --codex --remove "${target}"
  assert_not_exists "${target}/.codex/skills/explain-code"
}

run_claude_install_and_remove_test() {
  local target="${TMP_ROOT}/claude-target"
  mkdir -p "${target}"

  bash "${CODEX_INSTALLER}" "${target}"
  bash "${CLAUDE_INSTALLER}" "${target}"
  assert_file "${target}/.claude/skills/explain-code/SKILL.md"
  assert_contains "${target}/.claude/skills/explain-code/SKILL.md" '/explain-code deep'
  assert_not_exists "${target}/CLAUDE.md"
  diff -u \
    <(grep -F '$explain-code' "${target}/.codex/skills/explain-code/SKILL.md" | sed 's/\$explain-code/\/explain-code/g') \
    <(grep -F '/explain-code' "${target}/.claude/skills/explain-code/SKILL.md")

  bash "${ROOT_INSTALLER}" --claude --remove "${target}"
  assert_not_exists "${target}/.claude/skills/explain-code"
}

run_install_and_remove_test
run_root_installer_test
run_claude_install_and_remove_test

echo "PASS: explain-code Codex and Claude Code install, idempotence, and removal"
