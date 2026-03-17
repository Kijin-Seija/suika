#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT_INSTALLER="${ROOT_DIR}/init.sh"
CURSOR_INSTALLER="${ROOT_DIR}/cursor/init.sh"
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
  grep -Fq "${expected}" "${path}" || fail "expected '${expected}' in ${path}"
}

assert_not_contains() {
  local path="$1"
  local unexpected="$2"
  if grep -Fq "${unexpected}" "${path}"; then
    fail "did not expect '${unexpected}' in ${path}"
  fi
}

run_cursor_install_test() {
  local target="${TMP_DIR}/cursor-target"
  mkdir -p "${target}"

  assert_file "${CURSOR_INSTALLER}"
  bash "${CURSOR_INSTALLER}" "${target}"

  assert_file "${target}/.cursor/skills/dual-model-consensus/SKILL.md"
  assert_file "${target}/.cursor/skills/dual-model-consensus/reference.md"
  assert_file "${target}/.cursor/prompts/dual-model-consensus/claude-analysis-planner.md"
  assert_file "${target}/.cursor/prompts/dual-model-consensus/gpt-review.md"
  assert_file "${target}/.cursor/prompts/dual-model-consensus/claude-revision.md"
  assert_file "${target}/.cursor/prompts/dual-model-consensus/claude-code-draft.md"
  assert_file "${target}/.cursor/prompts/dual-model-consensus/gpt-code-review.md"
  assert_file "${target}/.cursor/prompts/dual-model-consensus/claude-code-revision.md"
  assert_file "${target}/.cursor/prompts/dual-model-consensus/disagreement-report.md"
  assert_file "${target}/.cursor/agents/claude-author.md"
  assert_file "${target}/.cursor/agents/gpt-reviewer.md"
  assert_file "${target}/AGENTS.md"

  assert_contains "${target}/AGENTS.md" ".cursor/skills/dual-model-consensus/SKILL.md"
  assert_contains "${target}/AGENTS.md" ".cursor/prompts/dual-model-consensus/"
  assert_contains "${target}/AGENTS.md" ".cursor/plans/<topic-slug>/"

  assert_not_contains "${target}/.cursor/skills/dual-model-consensus/SKILL.md" ".claude/"
}

run_claude_install_test() {
  local target="${TMP_DIR}/claude-target"
  mkdir -p "${target}"

  assert_file "${CLAUDE_INSTALLER}"
  bash "${CLAUDE_INSTALLER}" "${target}"

  assert_file "${target}/.claude/skills/dual-model-consensus/SKILL.md"
  assert_file "${target}/.claude/skills/dual-model-consensus/reference.md"
  assert_file "${target}/.claude/skills/dual-model-consensus/prompts/claude-analysis-planner.md"
  assert_file "${target}/.claude/skills/dual-model-consensus/prompts/gpt-review.md"
  assert_file "${target}/.claude/skills/dual-model-consensus/prompts/claude-revision.md"
  assert_file "${target}/.claude/skills/dual-model-consensus/prompts/claude-code-draft.md"
  assert_file "${target}/.claude/skills/dual-model-consensus/prompts/gpt-code-review.md"
  assert_file "${target}/.claude/skills/dual-model-consensus/prompts/claude-code-revision.md"
  assert_file "${target}/.claude/skills/dual-model-consensus/prompts/disagreement-report.md"
  assert_file "${target}/.claude/agents/claude-author.md"
  assert_file "${target}/.claude/agents/gpt-reviewer.md"
  assert_file "${target}/CLAUDE.md"

  assert_contains "${target}/CLAUDE.md" ".claude/skills/dual-model-consensus/SKILL.md"
  assert_contains "${target}/CLAUDE.md" ".claude/agents/"
  assert_contains "${target}/.claude/skills/dual-model-consensus/SKILL.md" "./prompts/claude-analysis-planner.md"
  assert_contains "${target}/.claude/skills/dual-model-consensus/SKILL.md" ".claude/plans/<topic-slug>/"
  assert_contains "${target}/.claude/agents/gpt-reviewer.md" "model: claude-"
  assert_not_contains "${target}/.claude/skills/dual-model-consensus/SKILL.md" "../../prompts/dual-model-consensus/"
  assert_not_contains "${target}/.claude/skills/dual-model-consensus/SKILL.md" ".cursor/"
  assert_not_contains "${target}/.claude/skills/dual-model-consensus/reference.md" ".cursor/plans/"
  assert_not_contains "${target}/.claude/agents/gpt-reviewer.md" "model: gpt-5.4"
}

run_root_default_install_test() {
  local target="${TMP_DIR}/root-default-target"
  mkdir -p "${target}"

  assert_file "${ROOT_INSTALLER}"
  bash "${ROOT_INSTALLER}" "${target}"

  assert_file "${target}/.cursor/skills/dual-model-consensus/SKILL.md"
  [[ ! -e "${target}/.claude/skills/dual-model-consensus/SKILL.md" ]] || fail "root default install should not create claude files"
}

run_root_claude_install_test() {
  local target="${TMP_DIR}/root-claude-target"
  mkdir -p "${target}"

  assert_file "${ROOT_INSTALLER}"
  bash "${ROOT_INSTALLER}" --claude "${target}"

  assert_file "${target}/.claude/skills/dual-model-consensus/SKILL.md"
  [[ ! -e "${target}/.cursor/skills/dual-model-consensus/SKILL.md" ]] || fail "root --claude install should not create cursor files"
}

run_root_all_install_test() {
  local target="${TMP_DIR}/root-all-target"
  mkdir -p "${target}"

  assert_file "${ROOT_INSTALLER}"
  bash "${ROOT_INSTALLER}" --all "${target}"

  assert_file "${target}/.cursor/skills/dual-model-consensus/SKILL.md"
  assert_file "${target}/.claude/skills/dual-model-consensus/SKILL.md"
}

run_cursor_install_test
run_claude_install_test
run_root_default_install_test
run_root_claude_install_test
run_root_all_install_test

echo "PASS: root, cursor and claude installers"
