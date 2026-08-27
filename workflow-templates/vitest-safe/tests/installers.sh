#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT_INSTALLER="${ROOT_DIR}/init.sh"
CODEX_INSTALLER="${ROOT_DIR}/codex/init.sh"
CLAUDE_INSTALLER="${ROOT_DIR}/claude/init.sh"
WRAPPER_SOURCE="${ROOT_DIR}/common/bin/vitest-safe"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TMP_ROOT}"' EXIT

export HOME="${TMP_ROOT}/home"
export CODEX_HOME="${TMP_ROOT}/codex-home"
export CLAUDE_HOME="${TMP_ROOT}/claude-home"
export XDG_STATE_HOME="${TMP_ROOT}/state"
mkdir -p "${HOME}" "${CODEX_HOME}" "${CLAUDE_HOME}"
SHARED_CONFIG="${XDG_STATE_HOME}/suika-vitest-safe/config.json"

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_file() { [[ -f "$1" ]] || fail "missing file: $1"; }
assert_symlink() { [[ -L "$1" ]] || fail "missing symlink: $1"; }
assert_not_exists() { [[ ! -e "$1" && ! -L "$1" ]] || fail "unexpected path: $1"; }
assert_contains() { grep -Fq -- "$2" "$1" || fail "expected '$2' in $1"; }
assert_not_contains() { ! grep -Fq -- "$2" "$1" || fail "did not expect '$2' in $1"; }

json_value() {
  python3 - "$1" "$2" <<'PY'
import json, sys
print(json.load(open(sys.argv[1], encoding="utf-8"))[sys.argv[2]])
PY
}

run_install_tests() {
  printf '%s\n' '# Existing Codex rules' > "${CODEX_HOME}/AGENTS.md"
  printf '%s\n' '# Existing Claude rules' > "${CLAUDE_HOME}/CLAUDE.md"

  if bash "${ROOT_INSTALLER}" --max-concurrent 0 >/dev/null 2>&1; then
    fail 'zero concurrency should be rejected'
  fi

  bash "${ROOT_INSTALLER}" --max-concurrent 1
  assert_symlink "${CODEX_HOME}/skills/vitest-safe"
  assert_symlink "${CODEX_HOME}/bin/vitest-safe"
  assert_file "${CODEX_HOME}/skills/vitest-safe/agents/openai.yaml"
  assert_file "${CODEX_HOME}/vitest-safe/config.json"
  assert_file "${SHARED_CONFIG}"
  [[ "$(json_value "${SHARED_CONFIG}" max_concurrent)" == 1 ]] || fail 'shared max should be 1'
  assert_contains "${CODEX_HOME}/AGENTS.md" '# Existing Codex rules'
  assert_contains "${CODEX_HOME}/AGENTS.md" '<!-- BEGIN vitest-safe -->'

  bash "${ROOT_INSTALLER}" --claude
  assert_symlink "${CLAUDE_HOME}/skills/vitest-safe"
  assert_symlink "${CLAUDE_HOME}/bin/vitest-safe"
  assert_not_exists "${CLAUDE_HOME}/skills/vitest-safe/agents/openai.yaml"
  assert_file "${CLAUDE_HOME}/vitest-safe/config.json"
  assert_contains "${CLAUDE_HOME}/CLAUDE.md" '# Existing Claude rules'
  assert_contains "${CLAUDE_HOME}/CLAUDE.md" 'Codex 与 Claude Code 共用同一队列'
  [[ "$(json_value "${CLAUDE_HOME}/vitest-safe/config.json" runtime_config)" == "${SHARED_CONFIG}" ]] || fail 'Claude descriptor should point to shared config'
  cmp "${CODEX_HOME}/bin/vitest-safe" "${CLAUDE_HOME}/bin/vitest-safe"
  diff -u \
    <(grep -F 'vitest-safe --' "${CODEX_HOME}/skills/vitest-safe/SKILL.md") \
    <(grep -F 'vitest-safe --' "${CLAUDE_HOME}/skills/vitest-safe/SKILL.md")

  bash "${CLAUDE_INSTALLER}" --max-concurrent 2
  [[ "$(json_value "${SHARED_CONFIG}" max_concurrent)" == 2 ]] || fail 'Claude install should update shared max'
  bash "${CODEX_INSTALLER}" --max-concurrent 1
}

run_wrapper_smoke_test() {
  local output="${TMP_ROOT}/wrapper-output"
  "${CODEX_HOME}/bin/vitest-safe" -- python3 -c 'print("vitest-safe smoke")' > "${output}"
  assert_contains "${output}" 'vitest-safe smoke'
}

run_cross_host_queue_test() {
  local output_dir="${TMP_ROOT}/queue"
  local first_pid
  mkdir -p "${output_dir}"

  "${CODEX_HOME}/bin/vitest-safe" -- python3 -c 'import time; time.sleep(2)' > "${output_dir}/codex.out" 2>&1 &
  first_pid=$!
  sleep 0.25
  "${CLAUDE_HOME}/bin/vitest-safe" -- python3 -c 'print("claude acquired")' > "${output_dir}/claude.out" 2>&1
  wait "${first_pid}"
  assert_contains "${output_dir}/claude.out" 'claude acquired'
  assert_contains "${output_dir}/claude.out" '已获得 slot'
}

run_remove_tests() {
  bash "${ROOT_INSTALLER}" --remove
  assert_not_exists "${CODEX_HOME}/skills/vitest-safe"
  assert_not_exists "${CODEX_HOME}/bin/vitest-safe"
  assert_not_contains "${CODEX_HOME}/AGENTS.md" '<!-- BEGIN vitest-safe -->'
  assert_file "${CLAUDE_HOME}/bin/vitest-safe"
  assert_file "${SHARED_CONFIG}"

  bash "${ROOT_INSTALLER}" --claude --remove
  assert_not_exists "${CLAUDE_HOME}/skills/vitest-safe"
  assert_not_exists "${CLAUDE_HOME}/bin/vitest-safe"
  assert_not_contains "${CLAUDE_HOME}/CLAUDE.md" '<!-- BEGIN vitest-safe -->'
  assert_file "${SHARED_CONFIG}"
  assert_contains "${WRAPPER_SOURCE}" 'fcntl.flock'
}

run_install_tests
run_wrapper_smoke_test
run_cross_host_queue_test
run_remove_tests

echo 'PASS: vitest-safe Codex/Claude shared install, queue, and removal'
