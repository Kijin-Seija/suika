#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT_INSTALLER="${ROOT_DIR}/init.sh"
CODEX_INSTALLER="${ROOT_DIR}/codex/init.sh"
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
  grep -Fq -- "${expected}" "${path}" || fail "expected '${expected}' in ${path}"
}

run_codex_install_test() {
  local target="${TMP_DIR}/codex-target"
  mkdir -p "${target}"

  assert_file "${CODEX_INSTALLER}"
  bash "${CODEX_INSTALLER}" "${target}"

  assert_file "${target}/.codex/skills/writer/SKILL.md"
  assert_file "${target}/.codex/skills/writer/reference.md"
  assert_file "${target}/.codex/skills/writer/prompts/claude-code-draft.md"
  assert_file "${target}/.codex/skills/writer/prompts/claude-code-revision.md"
  assert_file "${target}/.codex/skills/writer/prompts/codex-review.md"
  assert_file "${target}/.codex/skills/writer/prompts/dispute-report.md"
  assert_file "${target}/.codex/skills/writer/schemas/claude-draft.schema.json"
  assert_file "${target}/.codex/skills/writer/schemas/claude-response.schema.json"
  assert_file "${target}/.codex/skills/writer/schemas/codex-review.schema.json"
  assert_file "${target}/.codex/skills/writer/bin/writer-run.sh"
  assert_file "${target}/AGENTS.md"
  assert_executable "${target}/.codex/skills/writer/bin/writer-run.sh"

  assert_contains "${target}/AGENTS.md" ".codex/skills/writer/SKILL.md"
  assert_contains "${target}/AGENTS.md" ".codex/plans/<topic-slug>/"
  assert_contains "${target}/AGENTS.md" "writer 可选 Claude Code 或独立 Codex 子进程"
  assert_contains "${target}/AGENTS.md" "OpenSpec proposal/design/spec/tasks"
  assert_contains "${target}/.codex/skills/writer/SKILL.md" '默认 `5`'
  assert_contains "${target}/.codex/skills/writer/SKILL.md" '不要默认启用。'
  assert_contains "${target}/.codex/skills/writer/SKILL.md" '使用 writer skill'
  assert_contains "${target}/.codex/skills/writer/SKILL.md" 'openspec-artifacts'
  assert_contains "${target}/.codex/skills/writer/SKILL.md" 'writer 类型：`claude` 或 `codex`'
  assert_contains "${target}/.codex/skills/writer/reference.md" '`artifact-type: code | openspec-artifacts`'
  assert_contains "${target}/.codex/skills/writer/reference.md" '`status`: `pass | fail`'
  assert_contains "${target}/.codex/skills/writer/reference.md" '`blocking` 和 `important`'
  assert_contains "${target}/.codex/skills/writer/bin/writer-run.sh" '--artifact-type'
  assert_contains "${target}/.codex/skills/writer/bin/writer-run.sh" 'Codex review'
  assert_contains "${target}/.codex/skills/writer/bin/writer-run.sh" 'WRITER_CLAUDE_MAX_ATTEMPTS'
  assert_contains "${target}/.codex/skills/writer/bin/writer-run.sh" 'writer-handoff-r${round}.md'
}

run_root_default_install_test() {
  local target="${TMP_DIR}/root-default-target"
  mkdir -p "${target}"

  assert_file "${ROOT_INSTALLER}"
  bash "${ROOT_INSTALLER}" "${target}"

  assert_file "${target}/.codex/skills/writer/SKILL.md"
}

run_codex_install_test
run_root_default_install_test

echo "PASS: writer root and codex installers"
