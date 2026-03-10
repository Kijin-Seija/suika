#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
INIT_SCRIPT="${TEMPLATE_DIR}/init.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

assert_file() {
  local path="$1"
  [[ -f "${path}" ]] || fail "expected file: ${path}"
}

assert_dir() {
  local path="$1"
  [[ -d "${path}" ]] || fail "expected directory: ${path}"
}

assert_contains() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq "${needle}" "${file}"; then
    fail "expected '${needle}' in ${file}"
  fi
}

assert_count() {
  local file="$1"
  local needle="$2"
  local expected="$3"
  local actual
  actual="$(grep -Fc "${needle}" "${file}" || true)"
  [[ "${actual}" == "${expected}" ]] || fail "expected ${expected} occurrences of '${needle}' in ${file}, got ${actual}"
}

TMP_ROOT="$(mktemp -d "${TEMPLATE_DIR}/tmp.init-test.XXXXXX")"
trap 'rm -rf "${TMP_ROOT}"' EXIT

TARGET_PROJECT="${TMP_ROOT}/target-project"
mkdir -p "${TARGET_PROJECT}"

"${INIT_SCRIPT}" "${TARGET_PROJECT}"

assert_dir "${TARGET_PROJECT}/.cursor/skills/dual-model-consensus-plan"
assert_dir "${TARGET_PROJECT}/.cursor/prompts/dual-model-consensus-plan"
assert_dir "${TARGET_PROJECT}/.cursor/agents"
assert_dir "${TARGET_PROJECT}/.cursor/plans"
assert_dir "${TARGET_PROJECT}/docs/ai"

assert_file "${TARGET_PROJECT}/.cursor/skills/dual-model-consensus-plan/SKILL.md"
assert_file "${TARGET_PROJECT}/.cursor/skills/dual-model-consensus-plan/reference.md"
assert_file "${TARGET_PROJECT}/.cursor/prompts/dual-model-consensus-plan/claude-analysis-planner.md"
assert_file "${TARGET_PROJECT}/.cursor/prompts/dual-model-consensus-plan/gpt-review.md"
assert_file "${TARGET_PROJECT}/.cursor/prompts/dual-model-consensus-plan/claude-revision.md"
assert_file "${TARGET_PROJECT}/.cursor/prompts/dual-model-consensus-plan/disagreement-report.md"
assert_file "${TARGET_PROJECT}/.cursor/agents/claude-author.md"
assert_file "${TARGET_PROJECT}/.cursor/agents/gpt-reviewer.md"
assert_file "${TARGET_PROJECT}/docs/ai/dual-model-consensus-plan-workflow.md"
assert_file "${TARGET_PROJECT}/AGENTS.md"

assert_contains "${TARGET_PROJECT}/AGENTS.md" "<!-- BEGIN dual-model-consensus-plan -->"
assert_contains "${TARGET_PROJECT}/AGENTS.md" "<!-- END dual-model-consensus-plan -->"
assert_contains "${TARGET_PROJECT}/AGENTS.md" ".cursor/skills/dual-model-consensus-plan/SKILL.md"

"${INIT_SCRIPT}" "${TARGET_PROJECT}"

assert_count "${TARGET_PROJECT}/AGENTS.md" "<!-- BEGIN dual-model-consensus-plan -->" "1"
assert_count "${TARGET_PROJECT}/AGENTS.md" "<!-- END dual-model-consensus-plan -->" "1"

echo "PASS: init script test"
