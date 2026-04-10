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

assert_executable() {
  local path="$1"
  [[ -x "${path}" ]] || fail "not executable: ${path}"
}

assert_contains() {
  local path="$1"
  local expected="$2"
  grep -Fq "${expected}" "${path}" || fail "expected '${expected}' in ${path}"
}

json_field() {
  local json="$1"
  local field="$2"
  python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get(sys.argv[2], ""))' "${json}" "${field}"
}

post_log() {
  local endpoint="$1"
  local message="$2"
  python3 -c 'import json,sys,urllib.request; req=urllib.request.Request(sys.argv[1], data=json.dumps({"mode":"append","content":sys.argv[2]}).encode("utf-8"), headers={"Content-Type":"application/json"}, method="POST"); urllib.request.urlopen(req, timeout=2).read()' "${endpoint}" "${message}"
}

run_runtime_smoke_test() {
  local launcher="$1"
  local start_json
  local start_again_json
  local endpoint
  local log_file

  start_json="$(bash "${launcher}" start)"
  [[ "$(json_field "${start_json}" status)" == "ready" ]] || fail "start should return ready"
  endpoint="$(json_field "${start_json}" endpoint)"
  log_file="$(json_field "${start_json}" log_file)"
  [[ -n "${endpoint}" ]] || fail "missing endpoint"
  [[ -n "${log_file}" ]] || fail "missing log file"

  start_again_json="$(bash "${launcher}" start)"
  [[ "$(json_field "${start_again_json}" log_file)" == "${log_file}" ]] || fail "start should reuse same log file"

  post_log "${endpoint}" "browser debug payload"
  grep -Fq "browser debug payload" "${log_file}" || fail "log file should contain posted payload"

  bash "${launcher}" reset >/dev/null
  [[ ! -s "${log_file}" ]] || fail "reset should clear log file"

  bash "${launcher}" cleanup >/dev/null
  [[ ! -e "${log_file}" ]] || fail "cleanup should remove log file"
}

run_start_failure_smoke_test() {
  local launcher="$1"
  local failed_json
  local server_log
  local state_dir

  failed_json="$(bash "${launcher}" start --session invalid-host --host 256.256.256.256 2>/dev/null || true)"
  [[ "$(json_field "${failed_json}" status)" == "error" ]] || fail "invalid host should return error"
  server_log="$(json_field "${failed_json}" server_log)"
  state_dir="$(json_field "${failed_json}" state_dir)"
  [[ -n "${server_log}" ]] || fail "failed start should return server_log"
  [[ -n "${state_dir}" ]] || fail "failed start should return state_dir"
  [[ -f "${server_log}" ]] || fail "failed start should preserve server_log"
  grep -Eq "Traceback|gaierror|Name or service not known|nodename nor servname provided" "${server_log}" || fail "server_log should contain failure details"

  bash "${launcher}" cleanup --session invalid-host >/dev/null
  [[ ! -e "${state_dir}" ]] || fail "cleanup should remove failed runtime directory"
}

run_codex_install_test() {
  local target="${TMP_DIR}/codex-target"
  mkdir -p "${target}"

  assert_file "${CODEX_INSTALLER}"
  bash "${CODEX_INSTALLER}" "${target}"

  assert_file "${target}/.codex/skills/debug/SKILL.md"
  assert_file "${target}/.codex/skills/debug/reference.md"
  assert_file "${target}/.codex/skills/debug/bin/debug-session.sh"
  assert_file "${target}/.codex/skills/debug/bin/debug_log_server.py"
  assert_file "${target}/AGENTS.md"
  assert_executable "${target}/.codex/skills/debug/bin/debug-session.sh"
  assert_executable "${target}/.codex/skills/debug/bin/debug_log_server.py"

  assert_contains "${target}/AGENTS.md" ".codex/skills/debug/SKILL.md"
  assert_contains "${target}/AGENTS.md" "同一个临时 log 文件"
  assert_contains "${target}/.codex/skills/debug/SKILL.md" '.codex/skills/debug/bin/debug-session.sh start'
  assert_contains "${target}/.codex/skills/debug/SKILL.md" '.codex/skills/debug/bin/debug-session.sh cleanup'
  assert_contains "${target}/.codex/skills/debug/reference.md" '.codex/skills/debug/bin/debug-session.sh start'
  assert_contains "${target}/.codex/skills/debug/reference.md" '每次新的用户追加提问前'

  run_runtime_smoke_test "${target}/.codex/skills/debug/bin/debug-session.sh"
  run_start_failure_smoke_test "${target}/.codex/skills/debug/bin/debug-session.sh"
}

run_claude_install_test() {
  local target="${TMP_DIR}/claude-target"
  mkdir -p "${target}"

  assert_file "${CLAUDE_INSTALLER}"
  bash "${CLAUDE_INSTALLER}" "${target}"

  assert_file "${target}/.claude/skills/debug/SKILL.md"
  assert_file "${target}/.claude/skills/debug/reference.md"
  assert_file "${target}/.claude/skills/debug/bin/debug-session.sh"
  assert_file "${target}/.claude/skills/debug/bin/debug_log_server.py"
  assert_file "${target}/CLAUDE.md"
  assert_executable "${target}/.claude/skills/debug/bin/debug-session.sh"
  assert_executable "${target}/.claude/skills/debug/bin/debug_log_server.py"

  assert_contains "${target}/CLAUDE.md" ".claude/skills/debug/SKILL.md"
  assert_contains "${target}/CLAUDE.md" "同一个临时 log 文件"
  assert_contains "${target}/.claude/skills/debug/SKILL.md" '.claude/skills/debug/bin/debug-session.sh reset'
  assert_contains "${target}/.claude/skills/debug/reference.md" '.claude/skills/debug/bin/debug-session.sh start'
  assert_contains "${target}/.claude/skills/debug/reference.md" 'POST /clear'

  run_runtime_smoke_test "${target}/.claude/skills/debug/bin/debug-session.sh"
  run_start_failure_smoke_test "${target}/.claude/skills/debug/bin/debug-session.sh"
}

run_root_default_install_test() {
  local target="${TMP_DIR}/root-all-target"
  mkdir -p "${target}"

  assert_file "${ROOT_INSTALLER}"
  bash "${ROOT_INSTALLER}" "${target}"

  assert_file "${target}/.codex/skills/debug/SKILL.md"
  assert_file "${target}/.claude/skills/debug/SKILL.md"
}

run_root_codex_install_test() {
  local target="${TMP_DIR}/root-codex-target"
  mkdir -p "${target}"

  bash "${ROOT_INSTALLER}" --codex "${target}"

  assert_file "${target}/.codex/skills/debug/SKILL.md"
  [[ ! -e "${target}/.claude/skills/debug/SKILL.md" ]] || fail "root --codex should not create claude files"
}

run_root_claude_install_test() {
  local target="${TMP_DIR}/root-claude-target"
  mkdir -p "${target}"

  bash "${ROOT_INSTALLER}" --claude "${target}"

  assert_file "${target}/.claude/skills/debug/SKILL.md"
  [[ ! -e "${target}/.codex/skills/debug/SKILL.md" ]] || fail "root --claude should not create codex files"
}

run_codex_install_test
run_claude_install_test
run_root_default_install_test
run_root_codex_install_test
run_root_claude_install_test

echo "PASS: debug root, codex and claude installers"
