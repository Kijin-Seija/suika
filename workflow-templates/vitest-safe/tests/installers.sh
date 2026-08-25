#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT_INSTALLER="${ROOT_DIR}/init.sh"
CODEX_INSTALLER="${ROOT_DIR}/codex/init.sh"
WRAPPER_SOURCE="${ROOT_DIR}/common/bin/vitest-safe"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TMP_ROOT}"' EXIT

export HOME="${TMP_ROOT}/home"
export CODEX_HOME="${TMP_ROOT}/codex-home"
mkdir -p "${HOME}" "${CODEX_HOME}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_file() {
  local path="$1"
  [[ -f "${path}" ]] || fail "missing file: ${path}"
}

assert_symlink() {
  local path="$1"
  [[ -L "${path}" ]] || fail "missing symlink: ${path}"
}

assert_not_exists() {
  local path="$1"
  [[ ! -e "${path}" && ! -L "${path}" ]] || fail "unexpected path: ${path}"
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

assert_not_contains() {
  local path="$1"
  local unexpected="$2"
  if grep -Fq -- "${unexpected}" "${path}"; then
    fail "did not expect '${unexpected}' in ${path}"
  fi
}

assert_json_field() {
  local path="$1"
  local field="$2"
  local expected="$3"
  python3 - "${path}" "${field}" "${expected}" <<'PY'
import json
import sys

path, field, expected = sys.argv[1:]
with open(path, "r", encoding="utf-8") as handle:
    actual = str(json.load(handle)[field])
if actual != expected:
    raise SystemExit(f"expected {field}={expected}, got {actual}")
PY
}

run_install_test() {
  printf '%s\n' '<!-- CODEGRAPH_START -->' '# Existing global rules' '<!-- CODEGRAPH_END -->' > "${CODEX_HOME}/AGENTS.md"

  if bash "${ROOT_INSTALLER}" --max-concurrent 0 >/dev/null 2>&1; then
    fail 'zero concurrency should be rejected'
  fi
  assert_not_exists "${CODEX_HOME}/skills/vitest-safe"

  bash "${ROOT_INSTALLER}" --max-concurrent 2

  assert_symlink "${CODEX_HOME}/skills/vitest-safe"
  assert_file "${CODEX_HOME}/skills/vitest-safe/SKILL.md"
  assert_file "${CODEX_HOME}/skills/vitest-safe/agents/openai.yaml"
  assert_symlink "${CODEX_HOME}/bin/vitest-safe"
  assert_executable "${CODEX_HOME}/bin/vitest-safe"
  assert_file "${CODEX_HOME}/vitest-safe/config.json"
  assert_json_field "${CODEX_HOME}/vitest-safe/config.json" max_concurrent 2
  assert_contains "${CODEX_HOME}/AGENTS.md" '# Existing global rules'
  assert_contains "${CODEX_HOME}/AGENTS.md" '<!-- BEGIN vitest-safe -->'
  assert_contains "${CODEX_HOME}/AGENTS.md" "${CODEX_HOME}/bin/vitest-safe -- <原始命令>"
  assert_contains "${WRAPPER_SOURCE}" 'fcntl.flock'

  bash "${ROOT_INSTALLER}"
  assert_json_field "${CODEX_HOME}/vitest-safe/config.json" max_concurrent 2
  [[ "$(grep -Fc '<!-- BEGIN vitest-safe -->' "${CODEX_HOME}/AGENTS.md")" == 1 ]] || fail 'AGENTS block should be idempotent'

  bash "${CODEX_INSTALLER}" --max-concurrent 3
  assert_json_field "${CODEX_HOME}/vitest-safe/config.json" max_concurrent 3

  bash "${CODEX_INSTALLER}" --max-concurrent 2
  assert_json_field "${CODEX_HOME}/vitest-safe/config.json" max_concurrent 2
}

run_wrapper_smoke_test() {
  local output="${TMP_ROOT}/wrapper-output"
  "${CODEX_HOME}/bin/vitest-safe" -- python3 -c 'print("vitest-safe smoke")' > "${output}"
  assert_contains "${output}" 'vitest-safe smoke'
}

run_queue_test() {
  local output_dir="${TMP_ROOT}/queue"
  local pid
  mkdir -p "${output_dir}"

  for i in 1 2 3; do
    "${CODEX_HOME}/bin/vitest-safe" -- python3 -c 'import time; time.sleep(2.0)' > "${output_dir}/${i}.out" 2>&1 &
    pid=$!
    printf '%s\n' "${pid}" >> "${output_dir}/pids"
  done
  while IFS= read -r pid; do
    wait "${pid}"
  done < "${output_dir}/pids"

  grep -R -Fq '正在队列中等待可用 slot' "${output_dir}" || fail 'third Vitest invocation should wait in queue'
}

run_remove_test() {
  bash "${ROOT_INSTALLER}" --remove
  assert_not_exists "${CODEX_HOME}/skills/vitest-safe"
  assert_not_exists "${CODEX_HOME}/bin/vitest-safe"
  assert_not_exists "${CODEX_HOME}/vitest-safe/config.json"
  assert_contains "${CODEX_HOME}/AGENTS.md" '# Existing global rules'
  assert_not_contains "${CODEX_HOME}/AGENTS.md" '<!-- BEGIN vitest-safe -->'
}

run_install_test
run_wrapper_smoke_test
run_queue_test
run_remove_test

echo 'PASS: vitest-safe global install, queue, idempotence, and removal'
