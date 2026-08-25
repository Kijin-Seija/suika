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
export CODEX_HOME="${TMP_DIR}/codex-home"
mkdir -p "${CODEX_HOME}"

global_monitor_root() {
  printf '%s/push-code-monitor' "${CODEX_HOME}"
}

global_monitor_config_path() {
  printf '%s/config.json' "$(global_monitor_root)"
}

global_monitor_db_path() {
  printf '%s/monitor.db' "$(global_monitor_root)"
}

global_monitor_service_path() {
  printf '%s/service.json' "$(global_monitor_root)"
}

global_monitor_script_path() {
  printf '%s/bin/push-code-monitor.cjs' "$(global_monitor_root)"
}

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_file() {
  local path="$1"
  [[ -f "${path}" ]] || fail "missing file: ${path}"
}

assert_no_file() {
  local path="$1"
  [[ ! -e "${path}" ]] || fail "unexpected file: ${path}"
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

assert_output_contains() {
  local output="$1"
  local expected="$2"
  [[ "${output}" == *"${expected}"* ]] || fail "expected output to contain '${expected}'"
}

assert_output_not_contains() {
  local output="$1"
  local unexpected="$2"
  [[ "${output}" != *"${unexpected}"* ]] || fail "expected output to not contain '${unexpected}'"
}

run_codex_install_test() {
  local target="${TMP_DIR}/codex-target"
  local output=""
  mkdir -p "${target}"

  assert_file "${CODEX_INSTALLER}"
  output="$(bash "${CODEX_INSTALLER}" \
    --no-connectivity-check \
    --remote upstream \
    --target-branch develop \
    --project-id group/project \
    --gitlab-base-url https://gitlab.example.com \
    --gitlab-api-token glpat-demo \
    --gitlab-token-header-name PRIVATE-TOKEN \
    --gitlab-ca-bundle /tmp/cacert.pem \
    --gitlab-skip-tls-verify false \
    --poll-interval-seconds 15 \
    --review-timeout-seconds 900 \
    --initial-review-grace-seconds 120 \
    --enable-mr-monitor \
    --mr-monitor-interval-seconds 180 \
    "${target}" 2>&1)"

  assert_file "${target}/.codex/skills/push-code/SKILL.md"
  assert_file "${target}/.codex/skills/push-code/reference.md"
  assert_file "${target}/.codex/skills/push-code/config.env"
  assert_file "${target}/.codex/skills/push-code/bin/push-code-run.sh"
  assert_file "${target}/.codex/skills/push-code/bin/push_code_webhook.py"
  assert_file "${target}/.codex/skills/push-code/bin/push-code-monitor.cjs"
  assert_file "$(global_monitor_script_path)"
  assert_file "$(global_monitor_config_path)"
  assert_file "$(global_monitor_db_path)"
  assert_file "${target}/AGENTS.md"
  assert_executable "${target}/.codex/skills/push-code/bin/push-code-run.sh"
  assert_executable "${target}/.codex/skills/push-code/bin/push_code_webhook.py"
  assert_executable "${target}/.codex/skills/push-code/bin/push-code-monitor.cjs"
  assert_executable "$(global_monitor_script_path)"

  assert_contains "${target}/AGENTS.md" ".codex/skills/push-code/SKILL.md"
  assert_contains "${target}/AGENTS.md" ".codex/skills/push-code/config.env"
  assert_contains "${target}/AGENTS.md" ".codex/skills/push-code/bin/push-code-run.sh"
  assert_contains "${target}/AGENTS.md" 'GitLab REST API'
  assert_contains "${target}/.codex/skills/push-code/SKILL.md" 'GitLab REST API'
  assert_contains "${target}/.codex/skills/push-code/SKILL.md" 'wait-review --mr-id'
  assert_contains "${target}/.codex/skills/push-code/SKILL.md" 'rebase-target'
  assert_contains "${target}/.codex/skills/push-code/SKILL.md" 'resolve-thread'
  assert_contains "${target}/.codex/skills/push-code/SKILL.md" '不要自动 merge MR'
  assert_contains "${target}/.codex/skills/push-code/SKILL.md" '普通 MR notes'
  assert_contains "${target}/.codex/skills/push-code/SKILL.md" 'pre-push 检查脚本报错'
  assert_contains "${target}/.codex/skills/push-code/SKILL.md" '当前会话必须自己继续定时轮询'
  assert_not_contains "${target}/.codex/skills/push-code/SKILL.md" 'monitor 接管后'
  assert_contains "${target}/.codex/skills/push-code/reference.md" 'PUSH_CODE_GITLAB_BASE_URL'
  assert_contains "${target}/.codex/skills/push-code/reference.md" 'PUSH_CODE_GITLAB_CA_BUNDLE'
  assert_contains "${target}/.codex/skills/push-code/reference.md" 'push-code-monitor.cjs'
  assert_contains "${target}/.codex/skills/push-code/reference.md" 'keep_waiting_for_ci_in_current_session'
  assert_contains "${target}/.codex/skills/push-code/reference.md" '退出码 `11`'
  assert_contains "${target}/.codex/skills/push-code/reference.md" 'resolve-thread'
  assert_contains "${target}/.codex/skills/push-code/reference.md" '不提供 merge 命令'
  assert_contains "${target}/.codex/skills/push-code/reference.md" 'GET /api/v4/user'
  assert_contains "${target}/.codex/skills/push-code/reference.md" 'POST /api/v4/projects/:id/merge_requests'
  assert_contains "${target}/.codex/skills/push-code/reference.md" '退出码 `10`'
  assert_contains "${target}/.codex/skills/push-code/config.env" 'PUSH_CODE_GIT_REMOTE=upstream'
  assert_contains "${target}/.codex/skills/push-code/config.env" 'PUSH_CODE_TARGET_BRANCH=develop'
  assert_contains "${target}/.codex/skills/push-code/config.env" 'PUSH_CODE_PROJECT_ID=group/project'
  assert_contains "${target}/.codex/skills/push-code/config.env" 'PUSH_CODE_GITLAB_BASE_URL=https://gitlab.example.com'
  assert_contains "${target}/.codex/skills/push-code/config.env" 'PUSH_CODE_GITLAB_API_TOKEN=glpat-demo'
  assert_contains "${target}/.codex/skills/push-code/config.env" 'PUSH_CODE_GITLAB_TOKEN_HEADER_NAME=PRIVATE-TOKEN'
  assert_contains "${target}/.codex/skills/push-code/config.env" 'PUSH_CODE_GITLAB_CA_BUNDLE=/tmp/cacert.pem'
  assert_contains "${target}/.codex/skills/push-code/config.env" 'PUSH_CODE_GITLAB_SKIP_TLS_VERIFY=false'
  assert_contains "${target}/.codex/skills/push-code/config.env" 'PUSH_CODE_GITLAB_INITIAL_REVIEW_GRACE_SECONDS=120'
  assert_contains "${target}/.codex/skills/push-code/config.env" 'PUSH_CODE_POLL_INTERVAL_SECONDS=15'
  assert_contains "${target}/.codex/skills/push-code/config.env" 'PUSH_CODE_REVIEW_TIMEOUT_SECONDS=900'
  assert_contains "${target}/.codex/skills/push-code/config.env" 'PUSH_CODE_MR_MONITOR_ENABLED=true'
  assert_contains "${target}/.codex/skills/push-code/config.env" 'PUSH_CODE_MR_MONITOR_INTERVAL_SECONDS=180'
  assert_contains "${target}/.codex/skills/push-code/config.env" "PUSH_CODE_MR_MONITOR_DB_PATH=$(global_monitor_db_path)"
  assert_contains "${target}/.codex/skills/push-code/config.env" "PUSH_CODE_MR_MONITOR_CONFIG_PATH=$(global_monitor_config_path)"
  assert_contains "${target}/.codex/skills/push-code/bin/push-code-run.sh" 'PUSH_CODE_GITLAB_BASE_URL'
  assert_contains "${target}/.codex/skills/push-code/bin/push-code-run.sh" 'push-code-run.sh note'
  assert_contains "${target}/.codex/skills/push-code/bin/push-code-run.sh" 'push-code-run.sh resolve-thread'
  assert_contains "${target}/.codex/skills/push-code/bin/push-code-run.sh" '缺少 GitLab 基础地址配置'
  assert_contains "${target}/.codex/skills/push-code/bin/push_code_webhook.py" 'merge_requests'
  assert_contains "${target}/.codex/skills/push-code/bin/push_code_webhook.py" 'resolve-thread'
  assert_contains "${target}/.codex/skills/push-code/bin/push_code_webhook.py" 'PUSH_CODE_GITLAB_INITIAL_REVIEW_GRACE_SECONDS'
  assert_contains "${target}/.codex/skills/push-code/bin/push_code_webhook.py" 'keep_waiting_for_ci_in_current_session'
  assert_contains "${target}/.codex/skills/push-code/bin/push-code-monitor.cjs" 'registration-upsert'
  assert_contains "${target}/.codex/skills/push-code/bin/push-code-monitor.cjs" 'run-loop'
  assert_contains "${target}/.codex/skills/push-code/bin/push-code-monitor.cjs" 'case "start"'
  assert_contains "${target}/.codex/skills/push-code/bin/push-code-monitor.cjs" 'case "stop"'
  assert_contains "${target}/.codex/skills/push-code/bin/push-code-monitor.cjs" 'case "status"'
  assert_contains "${target}/.codex/skills/push-code/bin/push-code-monitor.cjs" 'case "dashboard-data"'
  assert_contains "${target}/.codex/skills/push-code/bin/push-code-monitor.cjs" 'case "service"'
  assert_output_contains "${output}" '连接检查: 已跳过（--no-connectivity-check）'
  assert_output_contains "${output}" '全局 MR 定时巡检: 已启用'
}

run_root_install_test() {
  local target="${TMP_DIR}/root-target"
  local output=""
  mkdir -p "${target}"

  assert_file "${ROOT_INSTALLER}"
  output="$(bash "${ROOT_INSTALLER}" "${target}" 2>&1)"

  assert_file "${target}/.codex/skills/push-code/SKILL.md"
  assert_contains "${target}/.codex/skills/push-code/config.env" 'PUSH_CODE_GIT_REMOTE=origin'
  assert_contains "${target}/.codex/skills/push-code/config.env" 'PUSH_CODE_TARGET_BRANCH=main'
  assert_contains "${target}/.codex/skills/push-code/config.env" 'PUSH_CODE_MR_MONITOR_ENABLED=false'
  assert_output_contains "${output}" '连接检查: 没有可执行的检查项，已跳过'
}

run_global_monitor_install_test() {
  local target="${TMP_DIR}/global-monitor-target"
  local output=""
  mkdir -p "${target}"

  output="$(bash "${CODEX_INSTALLER}" \
    --no-prompt \
    --no-connectivity-check \
    --project-id team/project \
    --gitlab-base-url https://gitlab.example.com \
    --gitlab-api-token glpat-monitor \
    --enable-mr-monitor \
    --mr-monitor-interval-seconds 240 \
    "${target}" 2>&1)"

  assert_file "$(global_monitor_config_path)"
  assert_file "$(global_monitor_db_path)"
  assert_no_file "$(global_monitor_service_path)"
  assert_no_file "${CODEX_HOME}/automations/push-code-mr-monitor"
  assert_output_contains "${output}" '全局 MR 定时巡检: 已启用'

  output="$(python3 - "$(global_monitor_config_path)" "$(global_monitor_db_path)" <<'EOF'
import json
import sqlite3
import sys

config_path, db_path = sys.argv[1:3]
config = json.load(open(config_path, "r", encoding="utf-8"))
connection = sqlite3.connect(db_path)
count = connection.execute("SELECT COUNT(*) FROM mr_threads").fetchone()[0]
if config["enabled"] is not True:
    raise SystemExit("config.enabled should be true")
if config["intervalSeconds"] != 240:
    raise SystemExit(f"expected interval 240, got {config['intervalSeconds']}")
if count != 0:
    raise SystemExit(f"expected empty mr_threads table, got {count}")
print("ok")
EOF
)"
  assert_output_contains "${output}" 'ok'
}

run_type_module_project_monitor_test() {
  local target="${TMP_DIR}/type-module-target"
  local output=""

  mkdir -p "${target}"
  cat > "${target}/package.json" <<'EOF'
{
  "name": "type-module-target",
  "type": "module"
}
EOF

  bash "${CODEX_INSTALLER}" \
    --no-prompt \
    --no-connectivity-check \
    --project-id team/module \
    --gitlab-base-url https://gitlab.example.com \
    --gitlab-api-token token-module \
    --enable-mr-monitor \
    "${target}" >/dev/null

  output="$(node "$(global_monitor_script_path)" status 2>&1)"
  assert_output_contains "${output}" '"running": false'
}

run_monitor_config_persistence_test() {
  local target="${TMP_DIR}/monitor-persistence-target"
  mkdir -p "${target}"

  bash "${CODEX_INSTALLER}" \
    --no-prompt \
    --no-connectivity-check \
    --project-id team/persist \
    --gitlab-base-url https://gitlab.example.com \
    --gitlab-api-token token-a \
    --enable-mr-monitor \
    --mr-monitor-interval-seconds 111 \
    "${target}" >/dev/null

  node "$(global_monitor_script_path)" config-set \
    --config-path "$(global_monitor_config_path)" \
    --codex-bin "/tmp/persist-codex" >/dev/null

  node "$(global_monitor_script_path)" registration-upsert \
    --db-path "$(global_monitor_db_path)" \
    --mr-id "9" \
    --thread-id "thread-persist" \
    --branch "feature/persist" \
    --target-branch "main" \
    --mr-url "https://gitlab.example.com/team/persist/-/merge_requests/9" \
    --project-id "team/persist" \
    --project-root "${target}" \
    --launcher-path "${target}/.codex/skills/push-code/bin/push-code-run.sh" >/dev/null

  bash "${CODEX_INSTALLER}" \
    --no-prompt \
    --no-connectivity-check \
    --project-id team/persist \
    --gitlab-base-url https://gitlab.example.com \
    --gitlab-api-token token-b \
    "${target}" >/dev/null

  local output
  output="$(python3 - "$(global_monitor_config_path)" "$(global_monitor_db_path)" <<'EOF'
import json
import sqlite3
import sys

config_path, db_path = sys.argv[1:3]
config = json.load(open(config_path, "r", encoding="utf-8"))
connection = sqlite3.connect(db_path)
row = connection.execute(
    "SELECT mr_id, thread_id FROM mr_threads WHERE mr_id = ?",
    ("9",),
).fetchone()
if config["codexBin"] != "/tmp/persist-codex":
    raise SystemExit("codexBin not preserved")
if row != ("9", "thread-persist"):
    raise SystemExit(f"db row not preserved: {row}")
print("ok")
EOF
)"
  assert_output_contains "${output}" 'ok'
}

run_interactive_reinit_test() {
  local target="${TMP_DIR}/interactive-target"
  mkdir -p "${target}"

  assert_file "${CODEX_INSTALLER}"
  bash "${CODEX_INSTALLER}" \
    --no-prompt \
    --no-connectivity-check \
    --remote origin \
    --target-branch main \
    --project-id team/project \
    --mr-title-prefix '[Robot]' \
    --gitlab-base-url https://gitlab.example.com \
    --gitlab-api-token old-token \
    --gitlab-token-header-name Authorization \
    --gitlab-token-scheme Bearer \
    --gitlab-ca-bundle /tmp/original-ca.pem \
    --gitlab-skip-tls-verify true \
    --extra-header-name X-Trace-Id \
    --extra-header-value abc123 \
    --poll-interval-seconds 12 \
    --review-timeout-seconds 600 \
    --initial-review-grace-seconds 75 \
    --enable-mr-monitor \
    --mr-monitor-interval-seconds 66 \
    --approved-states approved,pass,ok \
    --changes-requested-states fail,blocked,changes_requested \
    --pending-states pending,queued,running \
    "${target}"

  awk 'BEGIN { for (i = 0; i < 20; i++) print "" }' | \
    bash "${CODEX_INSTALLER}" --prompt --no-connectivity-check "${target}"

  assert_contains "${target}/.codex/skills/push-code/config.env" 'PUSH_CODE_PROJECT_ID=team/project'
  assert_contains "${target}/.codex/skills/push-code/config.env" 'PUSH_CODE_MR_TITLE_PREFIX=\[Robot\]'
  assert_contains "${target}/.codex/skills/push-code/config.env" 'PUSH_CODE_GITLAB_API_TOKEN=old-token'
  assert_contains "${target}/.codex/skills/push-code/config.env" 'PUSH_CODE_GITLAB_TOKEN_HEADER_NAME=Authorization'
  assert_contains "${target}/.codex/skills/push-code/config.env" 'PUSH_CODE_GITLAB_TOKEN_SCHEME=Bearer'
  assert_contains "${target}/.codex/skills/push-code/config.env" 'PUSH_CODE_GITLAB_CA_BUNDLE=/tmp/original-ca.pem'
  assert_contains "${target}/.codex/skills/push-code/config.env" 'PUSH_CODE_GITLAB_SKIP_TLS_VERIFY=true'
  assert_contains "${target}/.codex/skills/push-code/config.env" 'PUSH_CODE_GITLAB_EXTRA_HEADER_NAME=X-Trace-Id'
  assert_contains "${target}/.codex/skills/push-code/config.env" 'PUSH_CODE_GITLAB_EXTRA_HEADER_VALUE=abc123'
  assert_contains "${target}/.codex/skills/push-code/config.env" 'PUSH_CODE_GITLAB_INITIAL_REVIEW_GRACE_SECONDS=75'
  assert_contains "${target}/.codex/skills/push-code/config.env" 'PUSH_CODE_MR_MONITOR_INTERVAL_SECONDS=66'
}

run_reinstall_preserves_custom_env_test() {
  local target="${TMP_DIR}/custom-env-reinit-target"

  mkdir -p "${target}"

  bash "${CODEX_INSTALLER}" \
    --no-prompt \
    --no-connectivity-check \
    --project-id team/custom-env \
    --gitlab-base-url https://gitlab.example.com \
    --gitlab-api-token token-custom \
    --enable-mr-monitor \
    "${target}" >/dev/null

  cat >> "${target}/.codex/skills/push-code/config.env" <<'EOF'
PUSH_CODE_CUSTOM_FOO=bar
PUSH_CODE_EXTRA_CLIENT='curl --http1.1'
EOF

  bash "${CODEX_INSTALLER}" \
    --no-prompt \
    --no-connectivity-check \
    "${target}" >/dev/null

  assert_contains "${target}/.codex/skills/push-code/config.env" 'PUSH_CODE_CUSTOM_FOO=bar'
  assert_contains "${target}/.codex/skills/push-code/config.env" "PUSH_CODE_EXTRA_CLIENT='curl --http1.1'"
}

run_git_connectivity_check_test() {
  local target="${TMP_DIR}/git-check-target"
  local bare="${TMP_DIR}/git-check-remote.git"
  local output=""

  mkdir -p "${target}"
  git init --bare "${bare}" >/dev/null 2>&1
  git -C "${target}" init >/dev/null 2>&1
  git -C "${target}" config user.name tester
  git -C "${target}" config user.email tester@example.com
  git -C "${target}" remote add origin "${bare}"
  printf 'hello\n' > "${target}/README.md"
  git -C "${target}" add README.md
  git -C "${target}" commit -m "init" >/dev/null 2>&1

  output="$(bash "${CODEX_INSTALLER}" \
    --no-prompt \
    --check-connectivity \
    "${target}" 2>&1)"

  assert_output_contains "${output}" "连接检查: 验证 git remote 'origin'"
  assert_output_contains "${output}" '连接检查: git remote 可用'
  assert_output_contains "${output}" '连接检查: 跳过 GitLab API 鉴权检查，未配置基础地址'
}

run_gitlab_connectivity_check_test() {
  local target="${TMP_DIR}/gitlab-check-target"
  local fake_bin="${TMP_DIR}/gitlab-check-bin"
  local output=""

  mkdir -p "${target}" "${fake_bin}"
  cat > "${fake_bin}/curl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${fake_bin}/curl"

  output="$(PATH="${fake_bin}:$PATH" bash "${CODEX_INSTALLER}" \
    --no-prompt \
    --check-connectivity \
    --project-id team/project \
    --gitlab-base-url https://gitlab.example.com \
    --gitlab-api-token token-demo \
    "${target}" 2>&1)"

  assert_output_contains "${output}" '连接检查: 验证 GitLab API 鉴权'
  assert_output_contains "${output}" '连接检查: GitLab API 鉴权通过'
  assert_output_contains "${output}" '连接检查: 验证 GitLab 项目 team/project'
  assert_output_contains "${output}" '连接检查: GitLab 项目可访问'
}

run_git_remote_inference_test() {
  local target="${TMP_DIR}/git-infer-target"
  local bare="${TMP_DIR}/git-infer-remote.git"
  local output=""

  mkdir -p "${target}"
  git init --bare "${bare}" >/dev/null 2>&1
  git -C "${target}" init >/dev/null 2>&1
  git -C "${target}" remote add upstream "${bare}"

  output="$(bash "${CODEX_INSTALLER}" \
    --no-prompt \
    --no-connectivity-check \
    "${target}" 2>&1)"

  assert_output_contains "${output}" "配置推断: 检测到唯一 git remote 'upstream'"
  assert_contains "${target}/.codex/skills/push-code/config.env" 'PUSH_CODE_GIT_REMOTE=upstream'
}

run_project_id_inference_https_test() {
  local target="${TMP_DIR}/project-id-https-target"
  local output=""

  mkdir -p "${target}"
  git -C "${target}" init >/dev/null 2>&1
  git -C "${target}" remote add origin "https://gitlab.example.com/group/subgroup/project.git"

  output="$(bash "${CODEX_INSTALLER}" \
    --no-prompt \
    --no-connectivity-check \
    "${target}" 2>&1)"

  assert_output_contains "${output}" "配置推断: 从 git remote URL 推断 project_id='group/subgroup/project'"
  assert_contains "${target}/.codex/skills/push-code/config.env" 'PUSH_CODE_PROJECT_ID=group/subgroup/project'
}

run_project_id_inference_ssh_test() {
  local target="${TMP_DIR}/project-id-ssh-target"
  local output=""

  mkdir -p "${target}"
  git -C "${target}" init >/dev/null 2>&1
  git -C "${target}" remote add origin "git@gitlab.example.com:team/project.git"

  output="$(bash "${CODEX_INSTALLER}" \
    --no-prompt \
    --no-connectivity-check \
    "${target}" 2>&1)"

  assert_output_contains "${output}" "配置推断: 从 git remote URL 推断 project_id='team/project'"
  assert_contains "${target}/.codex/skills/push-code/config.env" 'PUSH_CODE_PROJECT_ID=team/project'
}

run_relative_path_inference_test() {
  local base="${TMP_DIR}/relative-base"
  local target="${base}/target-project"
  local output=""

  mkdir -p "${target}"
  git -C "${target}" init >/dev/null 2>&1
  git -C "${target}" remote add origin "git@gitlab.example.com:demo/relative.git"

  output="$(cd "${base}" && bash "${CODEX_INSTALLER}" --no-prompt --no-connectivity-check ./target-project 2>&1)"

  assert_output_contains "${output}" "配置推断: 从 git remote URL 推断 project_id='demo/relative'"
  assert_contains "${target}/.codex/skills/push-code/config.env" 'PUSH_CODE_GIT_REMOTE=origin'
  assert_contains "${target}/.codex/skills/push-code/config.env" 'PUSH_CODE_PROJECT_ID=demo/relative'
}

run_inferred_values_skip_prompt_test() {
  local base="${TMP_DIR}/prompt-base"
  local target="${base}/prompt-target"
  local output=""

  mkdir -p "${target}"
  git -C "${target}" init >/dev/null 2>&1
  git -C "${target}" remote add origin "git@gitlab.example.com:demo/prompt.git"

  output="$(cd "${base}" && bash "${CODEX_INSTALLER}" --prompt --no-connectivity-check ./prompt-target <<'EOF' 2>&1
















EOF
)"

  assert_output_contains "${output}" "Git remote: 使用自动推断值 'origin'"
  assert_output_contains "${output}" "项目 ID: 使用自动推断值 'demo/prompt'"
  assert_output_contains "${output}" '高级参数将直接使用默认值写入 config.env'
  assert_output_not_contains "${output}" 'Token header 名称'
  assert_output_not_contains "${output}" 'review 超时秒数'
}

run_launcher_exports_config_test() {
  local target="${TMP_DIR}/launcher-env-target"
  local output=""

  mkdir -p "${target}"

  bash "${CODEX_INSTALLER}" \
    --no-prompt \
    --no-connectivity-check \
    --project-id team/project \
    --gitlab-base-url https://gitlab.example.com \
    --gitlab-api-token launcher-token \
    "${target}" >/dev/null

  cat > "${target}/.codex/skills/push-code/bin/push_code_webhook.py" <<'EOF'
#!/usr/bin/env python3
import json
import os

print(json.dumps({
    "base_url": os.environ.get("PUSH_CODE_GITLAB_BASE_URL"),
    "token": os.environ.get("PUSH_CODE_GITLAB_API_TOKEN"),
    "project_id": os.environ.get("PUSH_CODE_PROJECT_ID"),
}))
EOF
  chmod +x "${target}/.codex/skills/push-code/bin/push_code_webhook.py"

  output="$(cd "${target}" && ./.codex/skills/push-code/bin/push-code-run.sh status --mr-id 1 2>&1)"

  assert_output_contains "${output}" '"base_url": "https://gitlab.example.com"'
  assert_output_contains "${output}" '"token": "launcher-token"'
  assert_output_contains "${output}" '"project_id": "team/project"'
}

run_launcher_registers_monitor_mapping_test() {
  local target="${TMP_DIR}/launcher-monitor-target"
  local output=""
  local db_path="$(global_monitor_db_path)"

  mkdir -p "${target}"
  git -C "${target}" init >/dev/null 2>&1
  git -C "${target}" config user.name tester
  git -C "${target}" config user.email tester@example.com
  printf 'seed\n' > "${target}/README.md"
  git -C "${target}" add README.md
  git -C "${target}" commit -m "seed" >/dev/null 2>&1
  git -C "${target}" checkout -b feature/monitor >/dev/null 2>&1

  bash "${CODEX_INSTALLER}" \
    --no-prompt \
    --no-connectivity-check \
    --project-id team/launcher-monitor \
    --gitlab-base-url https://gitlab.example.com \
    --gitlab-api-token launcher-monitor-token \
    --enable-mr-monitor \
    "${target}" >/dev/null

  cat > "${target}/.codex/skills/push-code/bin/push_code_webhook.py" <<'EOF'
#!/usr/bin/env python3
import json
print(json.dumps({
    "mr_id": 123,
    "mr_url": "https://gitlab.example.com/team/launcher-monitor/-/merge_requests/123",
}))
EOF
  chmod +x "${target}/.codex/skills/push-code/bin/push_code_webhook.py"

  output="$(cd "${target}" && CODEX_THREAD_ID="thread-launcher-monitor" ./.codex/skills/push-code/bin/push-code-run.sh create-mr 2>&1)"
  assert_output_contains "${output}" '"mr_id": 123'

  output="$(python3 - "${db_path}" "${target}" "${target}/.codex/skills/push-code/bin/push-code-run.sh" <<'EOF'
import sqlite3
import sys

connection = sqlite3.connect(sys.argv[1])
row = connection.execute(
    "SELECT mr_id, thread_id, branch, project_root, launcher_path, active FROM mr_threads WHERE mr_id = ?",
    ("123",),
).fetchone()
if row != ("123", "thread-launcher-monitor", "feature/monitor", sys.argv[2], sys.argv[3], 1):
    raise SystemExit(f"unexpected row: {row}")
print("ok")
EOF
)"
  assert_output_contains "${output}" 'ok'
}

run_create_mr_uses_plain_title_test() {
  local target="${TMP_DIR}/launcher-title-target"
  local output=""
  local capture_file="${TMP_DIR}/launcher-title.json"

  mkdir -p "${target}"
  git -C "${target}" init >/dev/null 2>&1
  git -C "${target}" config user.name tester
  git -C "${target}" config user.email tester@example.com
  printf 'seed\n' > "${target}/README.md"
  git -C "${target}" add README.md
  git -C "${target}" commit -m "seed" >/dev/null 2>&1
  git -C "${target}" checkout -b feature/title >/dev/null 2>&1

  bash "${CODEX_INSTALLER}" \
    --no-prompt \
    --no-connectivity-check \
    --project-id team/title \
    --gitlab-base-url https://gitlab.example.com \
    --gitlab-api-token title-token \
    "${target}" >/dev/null

  cat > "${target}/.codex/skills/push-code/bin/push_code_webhook.py" <<'EOF'
#!/usr/bin/env python3
import json
import os
import sys

args = sys.argv[1:]
title = ""
for index, value in enumerate(args):
    if value == "--title" and index + 1 < len(args):
        title = args[index + 1]
with open(os.environ["PUSH_CODE_TEST_CAPTURE_FILE"], "w", encoding="utf-8") as handle:
    json.dump({"title": title}, handle)
print(json.dumps({
    "mr_id": 456,
    "mr_url": "https://gitlab.example.com/team/title/-/merge_requests/456"
}))
EOF
  chmod +x "${target}/.codex/skills/push-code/bin/push_code_webhook.py"

  output="$(cd "${target}" && PUSH_CODE_TEST_CAPTURE_FILE="${capture_file}" ./.codex/skills/push-code/bin/push-code-run.sh create-mr --title 'Custom title' 2>&1)"
  assert_output_contains "${output}" '"mr_id": 456'

  output="$(node - "${capture_file}" <<'EOF'
const fs = require("fs");
const payload = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
if (payload.title !== "Custom title") {
  throw new Error(`unexpected title: ${payload.title}`);
}
process.stdout.write("ok\n");
EOF
)"
  assert_output_contains "${output}" 'ok'
}

run_monitor_scan_notification_test() {
  local target="${TMP_DIR}/monitor-scan-target"
  local fake_codex="${TMP_DIR}/fake-codex-scan.sh"
  local args_file="${TMP_DIR}/scan-notify-args.txt"
  local stdin_file="${TMP_DIR}/scan-notify-stdin.txt"
  local output=""

  mkdir -p "${target}"
  bash "${CODEX_INSTALLER}" \
    --no-prompt \
    --no-connectivity-check \
    --project-id team/scan \
    --gitlab-base-url https://gitlab.example.com \
    --gitlab-api-token scan-token \
    --enable-mr-monitor \
    "${target}" >/dev/null

  cat > "${fake_codex}" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "${args_file}"
cat > "${stdin_file}"
EOF
  chmod +x "${fake_codex}"

  cat > "${target}/.codex/skills/push-code/bin/push-code-run.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1-}" != "status" || "${2-}" != "--mr-id" ]]; then
  echo "unexpected args: $*" >&2
  exit 1
fi
cat <<'JSON'
{
  "status": "changes_requested",
  "raw_status": "head_pipeline:failed",
  "meta": {
    "head_pipeline_status": "failed",
    "pipelines_failed": 1,
    "pipelines_pending": 1,
    "unresolved_threads": 1,
    "latest_non_system_note_id": 11,
    "latest_non_system_note_created_at": "2026-01-02T00:00:00Z",
    "latest_non_system_note_updated_at": "2026-01-02T00:00:01Z",
    "latest_non_system_note_revision_key": "note-revision-v1",
    "review_note_revisions_total": 1,
    "review_notes_fingerprint": "review-fingerprint-v1",
    "latest_non_system_note_author": "reviewer"
  },
  "notes": [
    {
      "id": 11,
      "author": "reviewer",
      "body": "please fix",
      "updated_at": "2026-01-02T00:00:01Z",
      "system": false
    }
  ],
  "merge_request": {
    "sha": "abc123"
  },
  "workflow_guidance": {
    "review_complete": false,
    "can_announce_completion": false,
    "recommended_next_action": "inspect_pipeline_failure_and_fix",
    "user_facing_state": "changes_requested"
  }
}
JSON
EOF
  chmod +x "${target}/.codex/skills/push-code/bin/push-code-run.sh"

  node "$(global_monitor_script_path)" registration-upsert \
    --db-path "$(global_monitor_db_path)" \
    --mr-id "88" \
    --thread-id "thread-scan-demo" \
    --branch "feature/scan" \
    --target-branch "main" \
    --mr-url "https://gitlab.example.com/team/scan/-/merge_requests/88" \
    --project-id "team/scan" \
    --project-root "${target}" \
    --launcher-path "${target}/.codex/skills/push-code/bin/push-code-run.sh" >/dev/null

  node "$(global_monitor_script_path)" config-set \
    --config-path "$(global_monitor_config_path)" \
    --codex-bin "${fake_codex}" >/dev/null

  output="$(node "$(global_monitor_script_path)" scan 2>&1)"
  assert_output_contains "${output}" '"needs_attention"'
  assert_output_contains "${output}" '"notified": true'

  output="$(node "$(global_monitor_script_path)" scan 2>&1)"
  assert_output_contains "${output}" '"notifications": []'

  sed -i.bak \
    -e 's/review-fingerprint-v1/review-fingerprint-v2/' \
    -e 's/note-revision-v1/note-revision-v2/' \
    -e 's/please fix/please fix edited/' \
    -e 's/2026-01-02T00:00:01Z/2026-01-02T00:05:00Z/g' \
    -e 's/"status": "changes_requested"/"status": "approved"/' \
    -e 's/"review_complete": false/"review_complete": true/' \
    -e 's/"can_announce_completion": false/"can_announce_completion": true/' \
    "${target}/.codex/skills/push-code/bin/push-code-run.sh"
  rm -f "${target}/.codex/skills/push-code/bin/push-code-run.sh.bak"

  output="$(node "$(global_monitor_script_path)" scan 2>&1)"
  assert_output_contains "${output}" '"notified": true'
  assert_output_contains "${output}" '"review_revision_changed": true'
  assert_output_contains "${output}" '"ready_to_submit": false'

  output="$(python3 - "$(global_monitor_db_path)" <<'EOF'
import json
import sqlite3
import sys

connection = sqlite3.connect(sys.argv[1])
row = connection.execute(
    "SELECT trigger_source, notification_count, result_json FROM scan_runs ORDER BY id DESC LIMIT 1"
).fetchone()
if row is None:
    raise SystemExit("missing scan_runs row")
trigger_source, notification_count, result_json = row
payload = json.loads(result_json)
if trigger_source != "scan":
    raise SystemExit(f"unexpected trigger_source: {trigger_source}")
if notification_count != 1:
    raise SystemExit(f"unexpected notification_count: {notification_count}")
if payload["notifications"][0]["thread_id"] != "thread-scan-demo":
    raise SystemExit(f"unexpected notification payload: {payload['notifications']}")
print("ok")
EOF
)"
  assert_output_contains "${output}" 'ok'

  for _ in $(seq 1 50); do
    [[ -f "${args_file}" && -f "${stdin_file}" ]] && break
    sleep 0.1
  done
  [[ -f "${args_file}" ]] || fail "fake codex args file not created"
  [[ -f "${stdin_file}" ]] || fail "fake codex stdin file not created"
  assert_contains "${args_file}" 'exec resume --skip-git-repo-check thread-scan-demo -'
  assert_contains "${stdin_file}" 'Push-code MR 定时巡检结果：'
  assert_contains "${stdin_file}" '检测到 reviewer note 内容新增或被编辑，请重新阅读对应 revision 后再判断是否可提交。'
}

run_monitor_invalid_registration_cleanup_test() {
  local output=""

  python3 - "$(global_monitor_db_path)" <<'EOF'
import sqlite3
import sys
db_path = sys.argv[1]
conn = sqlite3.connect(db_path)
conn.execute("DELETE FROM mr_threads WHERE mr_id = ?", ("188",))
conn.execute(
    """
    INSERT INTO mr_threads (
      mr_id, thread_id, branch, target_branch, mr_url, project_id, project_root, launcher_path,
      active, last_status, last_raw_status, last_head_sha, last_note_id, last_note_created_at,
      last_fingerprint, last_notified_fingerprint, last_checked_at, last_notified_at,
      closed_reason, created_at, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """,
    (
      "188", "thread-legacy-scan", "feature/legacy", "main",
      "https://gitlab.example.com/team/legacy-scan/-/merge_requests/188",
      "team/legacy-scan", "/tmp/legacy-project", "",
      1, "", "", "", "", "", "", "", 0, 0, "", 1, 1
    ),
)
conn.commit()
conn.close()
EOF

  output="$(node "$(global_monitor_script_path)" scan 2>&1)"
  assert_output_contains "${output}" 'missing project_root or launcher_path in monitor registration'

  output="$(python3 - "$(global_monitor_db_path)" <<'EOF'
import sqlite3
import sys
db_path = sys.argv[1]
conn = sqlite3.connect(db_path)
row = conn.execute("SELECT active, closed_reason FROM mr_threads WHERE mr_id = ?", ("188",)).fetchone()
if row != (0, "missing_monitor_registration_context"):
    raise SystemExit(f"unexpected row: {row}")
print("ok")
EOF
)"
  assert_output_contains "${output}" 'ok'
}

run_monitor_thread_running_test() {
  local codex_home="${TMP_DIR}/codex-home-thread-running"
  local output=""
  local sleeper_pid=""

  mkdir -p "${codex_home}/process_manager"
  sleep 5 &
  sleeper_pid=$!

  cat > "${codex_home}/process_manager/chat_processes.json" <<EOF
[
  {
    "conversationId": "thread-running-demo",
    "command": "sleep 5",
    "osPid": ${sleeper_pid},
    "processId": "demo-process",
    "turnId": "demo-turn",
    "updatedAtMs": 123
  }
]
EOF

  output="$(CODEX_HOME="${codex_home}" node "${ROOT_DIR}/common/bin/push-code-monitor.cjs" thread-running --thread-id thread-running-demo)"
  assert_output_contains "${output}" '"running": true'
  assert_output_contains "${output}" '"command": "sleep 5"'

  kill "${sleeper_pid}" >/dev/null 2>&1 || true
  wait "${sleeper_pid}" 2>/dev/null || true
}

run_monitor_notify_thread_test() {
  local target="${TMP_DIR}/notify-thread-target"
  local fake_codex="${TMP_DIR}/fake-codex-notify.sh"
  local args_file="${TMP_DIR}/notify-thread-args.txt"
  local stdin_file="${TMP_DIR}/notify-thread-stdin.txt"
  local prompt_file="${TMP_DIR}/notify-thread-prompt.txt"
  local output=""

  mkdir -p "${target}"
  bash "${CODEX_INSTALLER}" \
    --no-prompt \
    --no-connectivity-check \
    --project-id team/notify \
    --gitlab-base-url https://gitlab.example.com \
    --gitlab-api-token notify-token \
    --enable-mr-monitor \
    "${target}" >/dev/null

  cat > "${fake_codex}" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "${args_file}"
cat > "${stdin_file}"
EOF
  chmod +x "${fake_codex}"

  cat > "${prompt_file}" <<'EOF'
hello from monitor
EOF

  node "$(global_monitor_script_path)" config-set \
    --config-path "$(global_monitor_config_path)" \
    --codex-bin "${fake_codex}" >/dev/null

  output="$(
    node "$(global_monitor_script_path)" notify-thread \
      --config-path "$(global_monitor_config_path)" \
      --thread-id thread-notify-demo \
      --message-file "${prompt_file}"
  )"
  assert_output_contains "${output}" '"notified": true'

  for _ in $(seq 1 50); do
    [[ -f "${args_file}" && -f "${stdin_file}" ]] && break
    sleep 0.1
  done
  [[ -f "${args_file}" ]] || fail "fake codex args file not created"
  [[ -f "${stdin_file}" ]] || fail "fake codex stdin file not created"
  assert_contains "${args_file}" 'exec resume --skip-git-repo-check thread-notify-demo -'
  assert_contains "${stdin_file}" 'hello from monitor'
}

run_monitor_service_commands_test() {
  local target="${TMP_DIR}/monitor-service-target"
  local output=""
  local fake_codex="${TMP_DIR}/fake-codex-service.sh"
  mkdir -p "${target}"

  bash "${CODEX_INSTALLER}" \
    --no-prompt \
    --no-connectivity-check \
    --project-id team/service \
    --gitlab-base-url https://gitlab.example.com \
    --gitlab-api-token service-token \
    --enable-mr-monitor \
    "${target}" >/dev/null

  cat > "${target}/.codex/skills/push-code/bin/push-code-run.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1-}" != "status" || "${2-}" != "--mr-id" ]]; then
  exit 1
fi
cat <<'JSON'
{
  "status": "pending",
  "raw_status": "ci_still_running",
  "meta": {
    "head_pipeline_status": "running",
    "unresolved_threads": 0,
    "latest_non_system_note_id": null,
    "latest_non_system_note_created_at": null
  },
  "notes": [],
  "merge_request": {
    "sha": "service-sha"
  },
  "workflow_guidance": {
    "review_complete": false,
    "can_announce_completion": false,
    "recommended_next_action": "keep_waiting_for_ci_in_current_session",
    "user_facing_state": "ci_running"
  }
}
JSON
EOF
  chmod +x "${target}/.codex/skills/push-code/bin/push-code-run.sh"

  cat > "${fake_codex}" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
EOF
  chmod +x "${fake_codex}"

  node "$(global_monitor_script_path)" config-set \
    --config-path "$(global_monitor_config_path)" \
    --codex-bin "${fake_codex}" >/dev/null

  output="$(node "$(global_monitor_script_path)" status)"
  assert_output_contains "${output}" '"running": false'

  output="$(node "$(global_monitor_script_path)" start --interval-seconds 60 --dashboard-port 0)"
  assert_output_contains "${output}" '"started": true'
  assert_file "$(global_monitor_service_path)"

  for _ in $(seq 1 50); do
    output="$(node "$(global_monitor_script_path)" status)"
    if [[ "${output}" == *'"running": true'* ]] && [[ "${output}" != *'"dashboard_port": 0'* ]]; then
      break
    fi
    sleep 0.1
  done
  assert_output_contains "${output}" '"running": true'
  assert_output_contains "${output}" '"dashboard_url": "http://127.0.0.1:'

  output="$(python3 - "$(global_monitor_service_path)" <<'EOF'
import json
import sys
import urllib.request

service = json.load(open(sys.argv[1], "r", encoding="utf-8"))
url = str(service.get("dashboardUrl") or "")
if not url:
    raise SystemExit("missing dashboardUrl")
with urllib.request.urlopen(f"{url}api/dashboard") as response:
    payload = json.load(response)
if payload["service_status"]["running"] is not True:
    raise SystemExit("service_status.running should be true")
if not isinstance(payload["recent_scans"], list) or len(payload["recent_scans"]) == 0:
    raise SystemExit("recent_scans should not be empty")
if not isinstance(payload["active_mrs"], list):
    raise SystemExit("active_mrs should be an array")
print("ok")
EOF
)"
  assert_output_contains "${output}" 'ok'

  output="$(node "$(global_monitor_script_path)" stop)"
  assert_output_contains "${output}" '"stopped": true'
  assert_no_file "$(global_monitor_service_path)"
}

run_rebase_target_flow_test() {
  local bare="${TMP_DIR}/rebase-remote.git"
  local seed="${TMP_DIR}/rebase-seed"
  local target="${TMP_DIR}/rebase-target"
  local updater="${TMP_DIR}/rebase-updater"

  git init --bare --initial-branch=main "${bare}" >/dev/null 2>&1

  git init --initial-branch=main "${seed}" >/dev/null 2>&1
  git -C "${seed}" config user.name tester
  git -C "${seed}" config user.email tester@example.com
  printf 'base\n' > "${seed}/README.md"
  git -C "${seed}" add README.md
  git -C "${seed}" commit -m "base" >/dev/null 2>&1
  git -C "${seed}" remote add origin "${bare}"
  git -C "${seed}" push -u origin main >/dev/null 2>&1

  git clone "${bare}" "${target}" >/dev/null 2>&1
  git -C "${target}" config user.name tester
  git -C "${target}" config user.email tester@example.com

  bash "${CODEX_INSTALLER}" \
    --no-prompt \
    --no-connectivity-check \
    --target-branch main \
    --project-id team/project \
    --gitlab-base-url https://gitlab.example.com \
    --gitlab-api-token rebase-token \
    "${target}" >/dev/null
  printf '/.codex/\n/AGENTS.md\n' >> "${target}/.git/info/exclude"

  git -C "${target}" checkout -b feature/rebase >/dev/null 2>&1
  printf 'feature\n' > "${target}/FEATURE.txt"
  git -C "${target}" add FEATURE.txt
  git -C "${target}" commit -m "feature work" >/dev/null 2>&1
  git -C "${target}" push -u origin feature/rebase >/dev/null 2>&1

  git clone "${bare}" "${updater}" >/dev/null 2>&1
  git -C "${updater}" config user.name tester
  git -C "${updater}" config user.email tester@example.com
  printf 'main update\n' >> "${updater}/README.md"
  git -C "${updater}" add README.md
  git -C "${updater}" commit -m "main update" >/dev/null 2>&1
  git -C "${updater}" push origin main >/dev/null 2>&1

  (cd "${target}" && ./.codex/skills/push-code/bin/push-code-run.sh rebase-target >/dev/null)
  git -C "${target}" merge-base --is-ancestor origin/main HEAD || fail "feature branch was not rebased onto origin/main"

  (cd "${target}" && ./.codex/skills/push-code/bin/push-code-run.sh push --force-with-lease >/dev/null)
  git -C "${target}" fetch origin feature/rebase >/dev/null 2>&1
  [[ "$(git -C "${target}" rev-parse HEAD)" == "$(git -C "${target}" rev-parse origin/feature/rebase)" ]] || fail "rebased branch was not pushed with force-with-lease"
}

run_helper_status_detection_test() {
  local helper="${ROOT_DIR}/common/bin/push_code_webhook.py"

  python3 - "${helper}" <<'EOF'
import importlib.util
import sys

helper_path = sys.argv[1]
spec = importlib.util.spec_from_file_location("push_code_webhook", helper_path)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

mr_pipeline_failed = {
    "state": "opened",
    "detailed_merge_status": "status_checks_must_pass",
    "has_conflicts": False,
    "rebase_in_progress": False,
    "head_pipeline": {"status": "failed", "id": 42},
}
status, raw_status, meta = module.normalize_status(mr_pipeline_failed, None, [], None, [])
assert status == "changes_requested", (status, raw_status, meta)
assert raw_status == "status_checks_must_pass:failed", (status, raw_status, meta)
assert meta["head_pipeline_status"] == "failed", meta

mr_pipeline_failed_nonblocking = {
    "state": "opened",
    "detailed_merge_status": "mergeable",
    "has_conflicts": False,
    "rebase_in_progress": False,
    "head_pipeline": {"status": "failed", "id": 43},
}
status, raw_status, meta = module.normalize_status(mr_pipeline_failed_nonblocking, None, [], None, [])
assert status == "changes_requested", (status, raw_status, meta)
assert raw_status == "head_pipeline:failed", (status, raw_status, meta)

mr_note_only = {
    "state": "opened",
    "detailed_merge_status": "mergeable",
    "has_conflicts": False,
    "rebase_in_progress": False,
    "head_pipeline": {"status": "success", "id": 99},
}
status, raw_status, meta = module.normalize_status(mr_note_only, None, [], None, [])
assert status == "approved", (status, raw_status, meta)

mr_pipeline_running = {
    "state": "opened",
    "detailed_merge_status": "mergeable",
    "has_conflicts": False,
    "rebase_in_progress": False,
    "sha": "current-head-sha",
    "head_pipeline": {"status": "running", "id": 100},
}
status, raw_status, meta = module.normalize_status(mr_pipeline_running, None, [], None, [])
assert status == "pending", (status, raw_status, meta)
assert raw_status == "head_pipeline:running", (status, raw_status, meta)

parallel_pipelines = [
    {"id": 99, "sha": "old-head-sha", "status": "failed", "source": "merge_request_event"},
    {"id": 100, "sha": "current-head-sha", "status": "running", "source": "merge_request_event"},
    {"id": 101, "sha": "current-head-sha", "status": "failed", "source": "external"},
]
mr_parallel_pipeline_failed = dict(mr_pipeline_running)
mr_parallel_pipeline_failed["detailed_merge_status"] = "ci_still_running"
status, raw_status, meta = module.normalize_status(
    mr_parallel_pipeline_failed,
    None,
    [],
    None,
    [],
    parallel_pipelines,
)
assert status == "changes_requested", (status, raw_status, meta)
assert raw_status == "pipelines_failed:1", (status, raw_status, meta)
assert meta["pipelines_failed"] == 1, meta
assert meta["pipelines_pending"] == 1, meta
assert meta["pipeline_failed_ids"] == [101], meta

status, raw_status, meta = module.normalize_status(
    mr_pipeline_running,
    None,
    [],
    None,
    [],
    [{"id": 99, "sha": "old-head-sha", "status": "failed"}],
)
assert status == "pending", (status, raw_status, meta)
assert raw_status == "head_pipeline:running", (status, raw_status, meta)
assert meta["pipelines_failed"] == 0, meta

status_checks_failed = [
    {"id": 1, "name": "external", "status": "failed", "external_url": "https://example.test/check/1"},
]
status, raw_status, meta = module.normalize_status(mr_note_only, None, [], None, status_checks_failed)
assert status == "changes_requested", (status, raw_status, meta)
assert raw_status == "external_status_checks_failed:1", (status, raw_status, meta)
assert meta["status_checks_failed"] == 1, meta

status, raw_status, meta = module.normalize_status(
    mr_pipeline_running,
    None,
    [],
    None,
    status_checks_failed,
)
assert status == "changes_requested", (status, raw_status, meta)
assert raw_status == "external_status_checks_failed:1", (status, raw_status, meta)

status_checks_pending = [
    {"id": 2, "name": "external", "status": "pending", "external_url": "https://example.test/check/2"},
]
status, raw_status, meta = module.normalize_status(mr_note_only, None, [], None, status_checks_pending)
assert status == "pending", (status, raw_status, meta)
assert raw_status == "external_status_checks_pending:1", (status, raw_status, meta)
assert meta["status_checks_pending"] == 1, meta

mr_rebase_needed_by_divergence = {
    "state": "opened",
    "detailed_merge_status": "mergeable",
    "has_conflicts": False,
    "rebase_in_progress": False,
    "diverged_commits_count": 21,
    "head_pipeline": {"status": "success", "id": 101},
}
ff_only_project = {"merge_method": "ff"}
status, raw_status, meta = module.normalize_status(mr_rebase_needed_by_divergence, ff_only_project, [], None, [])
assert status == "needs_rebase", (status, raw_status, meta)
assert raw_status == "diverged_commits_count:21", (status, raw_status, meta)
assert meta["merge_method"] == "ff", meta

notes_called = {"value": False}
module.get_merge_request = lambda project_id, mr_id: mr_note_only
module.get_project = lambda project_id: None
module.get_approvals = lambda project_id, mr_id: None
module.list_status_checks = lambda project_id, mr_id: []
module.list_merge_request_pipelines = lambda project_id, mr_id: []
module.list_discussions = lambda project_id, mr_id: []

def capture_approved_notes(project_id, mr_id):
    notes_called["value"] = True
    return [
        {"id": 11, "body": "LGTM", "author": "review-bot", "created_at": "2026-01-01T00:00:00Z", "system": False, "internal": False},
    ]

module.list_merge_request_notes = capture_approved_notes
bundle = module.fetch_status_bundle("team/project", "1")
assert bundle["status"] == "approved", bundle
assert notes_called["value"] is True, notes_called
assert bundle["meta"]["non_system_notes_total"] == 1, bundle
assert bundle["meta"]["latest_non_system_note_id"] == 11, bundle
assert bundle["workflow_guidance"]["review_complete"] is True, bundle
assert bundle["workflow_guidance"]["can_announce_completion"] is True, bundle

notes_called["value"] = False
module.get_merge_request = lambda project_id, mr_id: mr_pipeline_failed_nonblocking
module.get_project = lambda project_id: None

def capture_notes(project_id, mr_id):
    notes_called["value"] = True
    return [{"id": 1, "body": "审核不通过", "author": "review-bot", "created_at": "2026-01-02T00:00:00Z", "system": False, "internal": False}]

module.list_merge_request_notes = capture_notes
bundle = module.fetch_status_bundle("team/project", "1")
assert bundle["status"] == "changes_requested", bundle
assert notes_called["value"] is True, notes_called
assert bundle["notes"][0]["body"] == "审核不通过", bundle
assert bundle["raw_status"] == "head_pipeline:failed", bundle
assert bundle["meta"]["latest_non_system_note_id"] == 1, bundle
assert bundle["workflow_guidance"]["review_complete"] is False, bundle
assert bundle["workflow_guidance"]["recommended_next_action"] == "inspect_pipeline_failure_and_fix", bundle

notes_called["value"] = False
module.get_merge_request = lambda project_id, mr_id: mr_note_only
module.list_status_checks = lambda project_id, mr_id: status_checks_failed
bundle = module.fetch_status_bundle("team/project", "1")
assert bundle["status"] == "changes_requested", bundle
assert notes_called["value"] is True, notes_called
assert bundle["raw_status"] == "external_status_checks_failed:1", bundle
assert bundle["meta"]["status_checks_failed"] == 1, bundle

notes_called["value"] = False
module.get_merge_request = lambda project_id, mr_id: mr_pipeline_running
module.list_status_checks = lambda project_id, mr_id: []
module.list_merge_request_notes = lambda project_id, mr_id: [
    {"id": 21, "body": "审核不通过：请修复", "author": "review-bot", "created_at": "2026-01-03T00:00:00Z", "system": False, "internal": False},
]
bundle = module.fetch_status_bundle("team/project", "1")
assert bundle["status"] == "pending", bundle
assert bundle["notes"][0]["id"] == 21, bundle
assert bundle["meta"]["non_system_notes_total"] == 1, bundle
assert bundle["meta"]["latest_non_system_note_id"] == 21, bundle
assert bundle["workflow_guidance"]["can_announce_completion"] is False, bundle
assert bundle["workflow_guidance"]["user_facing_state"] == "ci_running_with_pending_finding", bundle

original_note = module.normalize_note({
    "id": 31,
    "body": "LGTM",
    "author": {"username": "review-bot"},
    "created_at": "2026-01-04T00:00:00Z",
    "updated_at": "2026-01-04T00:00:00Z",
    "system": False,
})
edited_note = module.normalize_note({
    "id": 31,
    "body": "审核不通过：请修复并行状态判断",
    "author": {"username": "review-bot"},
    "created_at": "2026-01-04T00:00:00Z",
    "updated_at": "2026-01-04T00:05:00Z",
    "system": False,
})
later_note = module.normalize_note({
    "id": 32,
    "body": "later note",
    "author": {"username": "review-bot"},
    "created_at": "2026-01-04T00:01:00Z",
    "updated_at": "2026-01-04T00:01:00Z",
    "system": False,
})
assert original_note["revision_key"] != edited_note["revision_key"], (original_note, edited_note)
assert original_note["body_sha256"] != edited_note["body_sha256"], (original_note, edited_note)
original_fingerprint = module.review_notes_fingerprint([original_note, later_note], [])
edited_fingerprint = module.review_notes_fingerprint([edited_note, later_note], [])
assert original_fingerprint != edited_fingerprint, (original_fingerprint, edited_fingerprint)

discussion = module.normalize_discussion({
    "id": "discussion-1",
    "notes": [{
        "id": 41,
        "body": "edited discussion finding",
        "author": {"username": "review-bot"},
        "created_at": "2026-01-04T00:00:00Z",
        "updated_at": "2026-01-04T00:06:00Z",
        "system": False,
        "resolvable": True,
        "resolved": False,
    }],
})
assert discussion["notes"][0]["updated_at"] == "2026-01-04T00:06:00Z", discussion
assert discussion["notes"][0]["revision_key"], discussion
EOF
}

run_codex_install_test
run_root_install_test
run_global_monitor_install_test
run_type_module_project_monitor_test
run_monitor_config_persistence_test
run_interactive_reinit_test
run_reinstall_preserves_custom_env_test
run_git_connectivity_check_test
run_gitlab_connectivity_check_test
run_git_remote_inference_test
run_project_id_inference_https_test
run_project_id_inference_ssh_test
run_relative_path_inference_test
run_inferred_values_skip_prompt_test
run_launcher_exports_config_test
run_launcher_registers_monitor_mapping_test
run_create_mr_uses_plain_title_test
run_monitor_scan_notification_test
run_monitor_invalid_registration_cleanup_test
run_monitor_thread_running_test
run_monitor_notify_thread_test
run_monitor_service_commands_test
run_rebase_target_flow_test
run_helper_status_detection_test

echo "PASS: push-code root and codex installers"
