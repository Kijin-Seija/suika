#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT_INSTALLER="${ROOT_DIR}/init.sh"
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

assert_executable() {
  local path="$1"
  [[ -x "${path}" ]] || fail "not executable: ${path}"
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

run_claude_install_test() {
  local target="${TMP_DIR}/claude-target"
  mkdir -p "${target}"

  assert_file "${CLAUDE_INSTALLER}"
  bash "${CLAUDE_INSTALLER}" "${target}"

  assert_file "${target}/.claude/skills/reviewer/SKILL.md"
  assert_file "${target}/.claude/skills/reviewer/reference.md"
  assert_file "${target}/.claude/skills/reviewer/prompts/codex-review-request.md"
  assert_file "${target}/.claude/skills/reviewer/prompts/claude-review-response.md"
  assert_file "${target}/.claude/skills/reviewer/prompts/dispute-report.md"
  assert_file "${target}/.claude/skills/reviewer/schemas/codex-review.schema.json"
  assert_file "${target}/.claude/skills/reviewer/bin/reviewer-run.sh"
  assert_file "${target}/CLAUDE.md"
  assert_executable "${target}/.claude/skills/reviewer/bin/reviewer-run.sh"

  assert_contains "${target}/CLAUDE.md" ".claude/skills/reviewer/SKILL.md"
  assert_contains "${target}/CLAUDE.md" ".claude/skills/reviewer/bin/reviewer-run.sh"
  assert_contains "${target}/CLAUDE.md" ".claude/skills/reviewer/schemas/codex-review.schema.json"
  assert_contains "${target}/CLAUDE.md" ".claude/plans/<topic-slug>/"
  assert_contains "${target}/CLAUDE.md" 'REVIEWER_CODEX_REVIEW_MODEL'
  assert_contains "${target}/.claude/skills/reviewer/SKILL.md" '默认 `5`'
  assert_contains "${target}/.claude/skills/reviewer/SKILL.md" '如果用户没有显式要求，不要默认启用。'
  assert_contains "${target}/.claude/skills/reviewer/SKILL.md" '制品类型：`code` 或 `doc`'
  assert_contains "${target}/.claude/skills/reviewer/SKILL.md" '.claude/skills/reviewer/bin/reviewer-run.sh'
  assert_contains "${target}/.claude/skills/reviewer/SKILL.md" 'REVIEWER_CODEX_REVIEW_MODEL'
  assert_contains "${target}/.claude/skills/reviewer/reference.md" 'codex-review.schema.json'
  assert_contains "${target}/.claude/skills/reviewer/reference.md" '真实的外部 `codex exec` 子进程'
  assert_contains "${target}/.claude/skills/reviewer/reference.md" '分歧报告'
  assert_contains "${target}/.claude/skills/reviewer/bin/reviewer-run.sh" 'gpt-5.4'
  assert_contains "${target}/.claude/skills/reviewer/bin/reviewer-run.sh" 'codex exec -C "${PWD}" -s read-only'
  assert_not_contains "${target}/.claude/skills/reviewer/SKILL.md" ".cursor/"
  assert_not_contains "${target}/.claude/skills/reviewer/reference.md" ".cursor/"
  assert_contains "${ROOT_DIR}/README.md" '.claude/skills/reviewer/bin/reviewer-run.sh'
  assert_contains "${ROOT_DIR}/README.md" 'REVIEWER_CODEX_REVIEW_MODEL'
}

run_root_default_install_test() {
  local target="${TMP_DIR}/root-default-target"
  mkdir -p "${target}"

  assert_file "${ROOT_INSTALLER}"
  bash "${ROOT_INSTALLER}" "${target}"

  assert_file "${target}/.claude/skills/reviewer/SKILL.md"
}

run_root_claude_install_test() {
  local target="${TMP_DIR}/root-claude-target"
  mkdir -p "${target}"

  assert_file "${ROOT_INSTALLER}"
  bash "${ROOT_INSTALLER}" --claude "${target}"

  assert_file "${target}/.claude/skills/reviewer/SKILL.md"
}

run_claude_install_test
run_root_default_install_test
run_root_claude_install_test

echo "PASS: reviewer root and claude installers"
