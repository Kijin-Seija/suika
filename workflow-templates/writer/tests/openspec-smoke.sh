#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="${ROOT_DIR}/init.sh"
BASE_DIR="${1:-${ROOT_DIR}/.tmp-tests/external}"

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

assert_json_value() {
  local path="$1"
  local key="$2"
  local expected="$3"
  local actual

  actual="$(python3 - "$path" "$key" <<'PY'
import json
import sys

path, key = sys.argv[1:3]
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)
print(data.get(key, ""))
PY
)"

  [[ "${actual}" == "${expected}" ]] || fail "expected ${key}=${expected}, got ${actual} in ${path}"
}

mkdir -p "${BASE_DIR}"
BASE_DIR="$(cd "${BASE_DIR}" && pwd)"
TEST_DIR="$(mktemp -d "${BASE_DIR%/}/writer-openspec-smoke-XXXXXX")"
REPO_DIR="${TEST_DIR}/repo"
STUB_BIN="${TEST_DIR}/bin"
LOG_DIR="${TEST_DIR}/logs"

mkdir -p "${REPO_DIR}" "${STUB_BIN}" "${LOG_DIR}"

cat > "${STUB_BIN}/openspec-propose" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

topic="${1:-unnamed}"
log_dir="${WRITER_STUB_LOG_DIR:?}"

printf 'openspec-propose %s\n' "$*" >> "${log_dir}/openspec-propose.log"

mkdir -p "docs/openspec/${topic}"
cat > "docs/openspec/${topic}/proposal.md" <<DOC
# Proposal

- topic: ${topic}
- source: fake openspec-propose
DOC
cat > "docs/openspec/${topic}/design.md" <<DOC
# Design

- topic: ${topic}
- source: fake openspec-propose
DOC
cat > "docs/openspec/${topic}/spec.md" <<DOC
# Spec

- topic: ${topic}
- source: fake openspec-propose
DOC
cat > "docs/openspec/${topic}/tasks.md" <<DOC
# Tasks

- [ ] Validate smoke flow for ${topic}
DOC
EOF
chmod +x "${STUB_BIN}/openspec-propose"

cat > "${STUB_BIN}/claude" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

prompt="$(cat)"
log_dir="${WRITER_STUB_LOG_DIR:?}"

printf '%s' "${prompt}" > "${log_dir}/claude-prompt.md"

[[ "${prompt}" == *"制品类型: openspec-artifacts"* ]] || {
  echo "missing openspec artifact type in Claude prompt" >&2
  exit 11
}
[[ "${prompt}" == *"OpenSpec 任务约束"* ]] || {
  echo "missing OpenSpec section in Claude prompt" >&2
  exit 12
}
[[ "${prompt}" == *"运行 openspec-propose，为新的导出流程生成 proposal/design/spec/tasks"* ]] || {
  echo "missing task text in Claude prompt" >&2
  exit 13
}

openspec-propose export-flow

cat <<'JSON'
{"summary":"Ran fake openspec-propose and generated proposal/design/spec/tasks for export-flow.","verification":"Executed stub openspec-propose and confirmed proposal/design/spec/tasks files were created.","changed_files":[{"path":"docs/openspec/export-flow/proposal.md","summary":"Create proposal artifact for export flow."},{"path":"docs/openspec/export-flow/design.md","summary":"Create design artifact for export flow."},{"path":"docs/openspec/export-flow/spec.md","summary":"Create spec artifact for export flow."},{"path":"docs/openspec/export-flow/tasks.md","summary":"Create tasks artifact for export flow."}],"questions":[]}
JSON
EOF
chmod +x "${STUB_BIN}/claude"

cat > "${STUB_BIN}/codex" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

log_dir="${WRITER_STUB_LOG_DIR:?}"
output_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o)
      output_path="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

[[ -n "${output_path}" ]] || {
  echo "missing -o output path for codex stub" >&2
  exit 21
}

prompt="$(cat)"
if [[ "${prompt}" == *"当前 artifact:"* ]]; then
  printf '%s' "${prompt}" > "${log_dir}/codex-review-prompt.md"

  [[ "${prompt}" == *"制品类型: openspec-artifacts"* ]] || {
    echo "missing openspec artifact type in Codex review prompt" >&2
    exit 22
  }
  [[ "${prompt}" == *"当前 artifact:"* ]] || {
    echo "missing current artifact reference in Codex review prompt" >&2
    exit 23
  }

  cat > "${output_path}" <<'JSON'
{"status":"pass","summary":"Smoke test reviewer accepted the OpenSpec artifacts flow.","issues":[],"next_action":"approve"}
JSON
  exit 0
fi

printf '%s' "${prompt}" > "${log_dir}/codex-writer-prompt.md"

[[ "${prompt}" == *"制品类型: openspec-artifacts"* ]] || {
  echo "missing openspec artifact type in Codex writer prompt" >&2
  exit 24
}
[[ "${prompt}" == *"运行 openspec-propose，为新的导出流程生成 proposal/design/spec/tasks"* ]] || {
  echo "missing task text in Codex writer prompt" >&2
  exit 25
}

openspec-propose export-flow

cat > "${output_path}" <<'JSON'
{"summary":"Ran fake openspec-propose and generated proposal/design/spec/tasks for export-flow.","verification":"Executed stub openspec-propose and confirmed proposal/design/spec/tasks files were created.","changed_files":[{"path":"docs/openspec/export-flow/proposal.md","summary":"Create proposal artifact for export flow."},{"path":"docs/openspec/export-flow/design.md","summary":"Create design artifact for export flow."},{"path":"docs/openspec/export-flow/spec.md","summary":"Create spec artifact for export flow."},{"path":"docs/openspec/export-flow/tasks.md","summary":"Create tasks artifact for export flow."}],"questions":[]}
JSON
EOF
chmod +x "${STUB_BIN}/codex"

cat > "${REPO_DIR}/README.md" <<'EOF'
# writer openspec smoke
EOF

git -C "${REPO_DIR}" init >/dev/null
git -C "${REPO_DIR}" config user.name "writer-smoke"
git -C "${REPO_DIR}" config user.email "writer-smoke@example.com"
git -C "${REPO_DIR}" add README.md
git -C "${REPO_DIR}" commit -m "init" >/dev/null

bash "${INSTALLER}" --default-writer codex "${REPO_DIR}"

assert_file "${REPO_DIR}/.codex/skills/writer/bin/writer-run.sh"
assert_contains "${REPO_DIR}/AGENTS.md" "OpenSpec proposal/design/spec/tasks"
assert_contains "${REPO_DIR}/AGENTS.md" '项目默认 writer: `codex`'
assert_contains "${REPO_DIR}/.codex/skills/writer/SKILL.md" "openspec-artifacts"
assert_contains "${REPO_DIR}/.codex/skills/writer/config.env" "WRITER_DEFAULT_WRITER=codex"

git -C "${REPO_DIR}" add .
git -C "${REPO_DIR}" commit -m "install writer workflow" >/dev/null

(
  cd "${REPO_DIR}"
  PATH="${STUB_BIN}:${PATH}" \
  WRITER_STUB_LOG_DIR="${LOG_DIR}" \
  bash ".codex/skills/writer/bin/writer-run.sh" run \
    --task "运行 openspec-propose，为新的导出流程生成 proposal/design/spec/tasks，并补齐必要说明" \
    --artifact-type openspec-artifacts \
    --topic export-flow \
    --max-rounds 2
)

assert_file "${LOG_DIR}/codex-writer-prompt.md"
assert_file "${LOG_DIR}/codex-review-prompt.md"
assert_file "${LOG_DIR}/openspec-propose.log"
assert_contains "${LOG_DIR}/codex-writer-prompt.md" "制品类型: openspec-artifacts"
assert_contains "${LOG_DIR}/codex-review-prompt.md" "制品类型: openspec-artifacts"
assert_contains "${LOG_DIR}/openspec-propose.log" "openspec-propose export-flow"

assert_file "${REPO_DIR}/docs/openspec/export-flow/proposal.md"
assert_file "${REPO_DIR}/docs/openspec/export-flow/design.md"
assert_file "${REPO_DIR}/docs/openspec/export-flow/spec.md"
assert_file "${REPO_DIR}/docs/openspec/export-flow/tasks.md"

assert_contains "${REPO_DIR}/.codex/plans/export-flow/brief.md" "artifact-type: openspec-artifacts"
assert_contains "${REPO_DIR}/.codex/plans/export-flow/draft-r1.md" "# OpenSpec 制品变更摘要"
assert_contains "${REPO_DIR}/.codex/plans/export-flow/final.md" "artifact-type: openspec-artifacts"
assert_contains "${REPO_DIR}/.codex/plans/export-flow/final.md" "review-summary: Smoke test reviewer accepted the OpenSpec artifacts flow."
assert_json_value "${REPO_DIR}/.codex/plans/export-flow/review-r1.json" "status" "pass"
assert_json_value "${REPO_DIR}/.codex/plans/export-flow/review-r1.json" "next_action" "approve"

echo "PASS: writer openspec smoke"
echo "TEST_DIR=${TEST_DIR}"
echo "REPO_DIR=${REPO_DIR}"
