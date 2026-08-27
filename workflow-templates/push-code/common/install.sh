#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="${SCRIPT_DIR}"
HOST_KIND="${PUSH_CODE_HOST:-codex}"

case "${HOST_KIND}" in
  codex)
    HOST_LABEL="Codex"
    HOST_MR_PREFIX="[Codex]"
    HOST_HOME_DIR="${CODEX_HOME:-${HOME}/.codex}"
    ;;
  claude)
    HOST_LABEL="Claude Code"
    HOST_MR_PREFIX="[Claude]"
    HOST_HOME_DIR="${CLAUDE_HOME:-${HOME}/.claude}"
    ;;
  *)
    echo "错误: 不支持的宿主: ${HOST_KIND}" >&2
    exit 1
    ;;
esac

HOST_DIR="${SCRIPT_DIR}/../${HOST_KIND}"
HOST_PROJECT_DIR=".${HOST_KIND}"
HOST_SKILL_RELATIVE="${HOST_PROJECT_DIR}/skills/push-code"

BEGIN_MARKER="<!-- BEGIN push-code -->"
END_MARKER="<!-- END push-code -->"

usage() {
  cat >&2 <<'EOF'
用法:
  init.sh [options] <target-project>

选项:
  --prompt
  --no-prompt
  --check-connectivity
  --no-connectivity-check
  --remote <name>
  --target-branch <branch>
  --project-id <id>
  --mr-title-prefix <prefix>
  --gitlab-base-url <url>
  --gitlab-api-token <token>
  --gitlab-token-header-name <name>
  --gitlab-token-scheme <scheme>
  --gitlab-ca-bundle <path>
  --gitlab-skip-tls-verify <true|false>
  --extra-header-name <name>
  --extra-header-value <value>
  --poll-interval-seconds <n>
  --review-timeout-seconds <n>
  --initial-review-grace-seconds <n>
  --enable-mr-monitor
  --disable-mr-monitor
  --mr-monitor-interval-seconds <n>
  --approved-states <csv>
  --changes-requested-states <csv>
  --pending-states <csv>
  --claude-bin <path>

兼容旧参数:
  --install-mr-monitor
  --skip-mr-monitor-install
  --join-mr-monitor
  --skip-join-mr-monitor
  --mr-monitor-interval-minutes <n>
EOF
}

require_directory() {
  local path="$1"
  [[ -d "${path}" ]] || {
    echo "错误: 目标目录不存在或不是目录: ${path}" >&2
    exit 1
  }
}

canonicalize_directory() {
  local path="$1"
  (
    cd "${path}" >/dev/null 2>&1
    pwd
  )
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

copy_file() {
  local source="$1"
  local destination="$2"
  cp "${source}" "${destination}"
}

remove_if_exists() {
  local path="$1"
  if [[ -e "${path}" ]]; then
    rm -rf "${path}"
  fi
}

quote_env() {
  printf '%q' "$1"
}

default_label() {
  local value="$1"
  if [[ -n "${value}" ]]; then
    printf '%s' "${value}"
  else
    printf '%s' "<empty>"
  fi
}

prompt_value() {
  local label="$1"
  local var_name="$2"
  local current="${!var_name}"
  local reply=""
  printf "%s [%s]: " "${label}" "$(default_label "${current}")" >&2
  IFS= read -r reply || true
  if [[ -n "${reply}" ]]; then
    printf -v "${var_name}" '%s' "${reply}"
  fi
}

prompt_secret() {
  local label="$1"
  local var_name="$2"
  local current="${!var_name}"
  local marker="<empty>"
  local reply=""
  if [[ -n "${current}" ]]; then
    marker="<set>"
  fi
  printf "%s [%s]: " "${label}" "${marker}" >&2
  IFS= read -r -s reply || true
  printf "\n" >&2
  if [[ -n "${reply}" ]]; then
    printf -v "${var_name}" '%s' "${reply}"
  fi
}

normalize_yes_no() {
  case "${1-}" in
    y|Y|yes|YES|Yes|1|true|TRUE|True|on|ON|On)
      printf '%s' "yes"
      ;;
    n|N|no|NO|No|0|false|FALSE|False|off|OFF|Off)
      printf '%s' "no"
      ;;
    *)
      return 1
      ;;
  esac
}

prompt_yes_no() {
  local label="$1"
  local var_name="$2"
  local default_value="$3"
  local reply=""
  local normalized=""

  while true; do
    if [[ "${default_value}" == "yes" ]]; then
      printf "%s [Y/n]: " "${label}" >&2
    else
      printf "%s [y/N]: " "${label}" >&2
    fi
    IFS= read -r reply || true
    if [[ -z "${reply}" ]]; then
      printf -v "${var_name}" '%s' "${default_value}"
      return 0
    fi
    normalized="$(normalize_yes_no "${reply}" 2>/dev/null || true)"
    if [[ -n "${normalized}" ]]; then
      printf -v "${var_name}" '%s' "${normalized}"
      return 0
    fi
    printf "请输入 y 或 n。\n" >&2
  done
}

prompt_integer() {
  local label="$1"
  local var_name="$2"
  local current="${!var_name}"
  local reply=""
  while true; do
    printf "%s [%s]: " "${label}" "$(default_label "${current}")" >&2
    IFS= read -r reply || true
    if [[ -z "${reply}" ]]; then
      return 0
    fi
    if [[ "${reply}" =~ ^[0-9]+$ ]] && [[ "${reply}" -gt 0 ]]; then
      printf -v "${var_name}" '%s' "${reply}"
      return 0
    fi
    printf "请输入大于 0 的整数。\n" >&2
  done
}

apply_existing_config() {
  local config_file="$1"
  local key=""
  local value=""

  [[ -f "${config_file}" ]] || return 0

  while IFS='=' read -r key value; do
    [[ -n "${key}" ]] || continue
    [[ "${key}" == \#* ]] && continue
    case "${key}" in
      PUSH_CODE_GIT_REMOTE)
        eval "remote=${value}"
        ;;
      PUSH_CODE_TARGET_BRANCH)
        eval "target_branch=${value}"
        ;;
      PUSH_CODE_PROJECT_ID)
        eval "project_id=${value}"
        ;;
      PUSH_CODE_MR_TITLE_PREFIX)
        eval "mr_title_prefix=${value}"
        ;;
      PUSH_CODE_POLL_INTERVAL_SECONDS)
        eval "poll_interval_seconds=${value}"
        ;;
      PUSH_CODE_REVIEW_TIMEOUT_SECONDS)
        eval "review_timeout_seconds=${value}"
        ;;
      PUSH_CODE_GITLAB_BASE_URL)
        eval "gitlab_base_url=${value}"
        ;;
      PUSH_CODE_GITLAB_API_TOKEN)
        eval "gitlab_api_token=${value}"
        ;;
      PUSH_CODE_GITLAB_TOKEN_HEADER_NAME)
        eval "gitlab_token_header_name=${value}"
        ;;
      PUSH_CODE_GITLAB_TOKEN_SCHEME)
        eval "gitlab_token_scheme=${value}"
        ;;
      PUSH_CODE_GITLAB_CA_BUNDLE)
        eval "gitlab_ca_bundle=${value}"
        ;;
      PUSH_CODE_GITLAB_SKIP_TLS_VERIFY)
        eval "gitlab_skip_tls_verify=${value}"
        ;;
      PUSH_CODE_GITLAB_EXTRA_HEADER_NAME)
        eval "extra_header_name=${value}"
        ;;
      PUSH_CODE_GITLAB_EXTRA_HEADER_VALUE)
        eval "extra_header_value=${value}"
        ;;
      PUSH_CODE_GITLAB_INITIAL_REVIEW_GRACE_SECONDS)
        eval "initial_review_grace_seconds=${value}"
        ;;
      PUSH_CODE_WEBHOOK_AUTH_TOKEN)
        eval "gitlab_api_token=${value}"
        ;;
      PUSH_CODE_WEBHOOK_AUTH_HEADER_NAME)
        eval "gitlab_token_header_name=${value}"
        ;;
      PUSH_CODE_WEBHOOK_AUTH_SCHEME)
        eval "gitlab_token_scheme=${value}"
        ;;
      PUSH_CODE_WEBHOOK_EXTRA_HEADER_NAME)
        eval "extra_header_name=${value}"
        ;;
      PUSH_CODE_WEBHOOK_EXTRA_HEADER_VALUE)
        eval "extra_header_value=${value}"
        ;;
      PUSH_CODE_MR_MONITOR_ENABLED)
        eval "project_monitor_enabled=${value}"
        ;;
      PUSH_CODE_MR_MONITOR_INTERVAL_SECONDS)
        eval "monitor_interval_seconds=${value}"
        ;;
      PUSH_CODE_REVIEW_APPROVED_STATES)
        eval "approved_states=${value}"
        ;;
      PUSH_CODE_REVIEW_CHANGES_REQUESTED_STATES)
        eval "changes_requested_states=${value}"
        ;;
      PUSH_CODE_REVIEW_PENDING_STATES)
        eval "pending_states=${value}"
        ;;
    esac
  done < "${config_file}"
}

is_managed_config_key() {
  case "${1-}" in
    PUSH_CODE_GIT_REMOTE|\
    PUSH_CODE_TARGET_BRANCH|\
    PUSH_CODE_PROJECT_ID|\
    PUSH_CODE_MR_TITLE_PREFIX|\
    PUSH_CODE_POLL_INTERVAL_SECONDS|\
    PUSH_CODE_REVIEW_TIMEOUT_SECONDS|\
    PUSH_CODE_GITLAB_INITIAL_REVIEW_GRACE_SECONDS|\
    PUSH_CODE_GITLAB_BASE_URL|\
    PUSH_CODE_GITLAB_API_TOKEN|\
    PUSH_CODE_GITLAB_TOKEN_HEADER_NAME|\
    PUSH_CODE_GITLAB_TOKEN_SCHEME|\
    PUSH_CODE_GITLAB_CA_BUNDLE|\
    PUSH_CODE_GITLAB_SKIP_TLS_VERIFY|\
    PUSH_CODE_GITLAB_EXTRA_HEADER_NAME|\
    PUSH_CODE_GITLAB_EXTRA_HEADER_VALUE|\
    PUSH_CODE_MR_MONITOR_ENABLED|\
    PUSH_CODE_MR_MONITOR_DB_PATH|\
    PUSH_CODE_MR_MONITOR_CONFIG_PATH|\
    PUSH_CODE_MR_MONITOR_INTERVAL_SECONDS|\
    PUSH_CODE_REVIEW_APPROVED_STATES|\
    PUSH_CODE_REVIEW_CHANGES_REQUESTED_STATES|\
    PUSH_CODE_REVIEW_PENDING_STATES|\
    PUSH_CODE_WEBHOOK_AUTH_TOKEN|\
    PUSH_CODE_WEBHOOK_AUTH_HEADER_NAME|\
    PUSH_CODE_WEBHOOK_AUTH_SCHEME|\
    PUSH_CODE_WEBHOOK_EXTRA_HEADER_NAME|\
    PUSH_CODE_WEBHOOK_EXTRA_HEADER_VALUE)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

append_preserved_config_entries() {
  local source="$1"
  local destination="$2"
  local line=""
  local key=""
  local appended=0

  [[ -f "${source}" ]] || return 0

  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -n "${line}" ]] || continue
    [[ "${line}" == \#* ]] && continue
    [[ "${line}" == *=* ]] || continue
    key="${line%%=*}"
    if is_managed_config_key "${key}"; then
      continue
    fi
    if [[ "${appended}" -eq 0 ]]; then
      {
        echo
        echo "# Preserved custom entries from previous install"
      } >> "${destination}"
      appended=1
    fi
    printf "%s\n" "${line}" >> "${destination}"
  done < "${source}"
}

agent_home_dir() {
  printf '%s' "${HOST_HOME_DIR}"
}

global_monitor_dir() {
  printf '%s/push-code-monitor' "$(agent_home_dir)"
}

global_monitor_bin_dir() {
  printf '%s/bin' "$(global_monitor_dir)"
}

global_monitor_config_path() {
  printf '%s/config.json' "$(global_monitor_dir)"
}

global_monitor_db_path() {
  printf '%s/monitor.db' "$(global_monitor_dir)"
}

global_monitor_legacy_state_path() {
  printf '%s/state.json' "$(global_monitor_dir)"
}

global_monitor_script_path() {
  printf '%s/push-code-monitor.cjs' "$(global_monitor_bin_dir)"
}

project_monitor_dir() {
  local project_root="$1"
  printf '%s/%s/monitor' "${project_root}" "${HOST_SKILL_RELATIVE}"
}

project_monitor_config_path() {
  local project_root="$1"
  printf '%s/config.json' "$(project_monitor_dir "${project_root}")"
}

project_monitor_db_path() {
  local project_root="$1"
  printf '%s/monitor.db' "$(project_monitor_dir "${project_root}")"
}

project_monitor_legacy_state_path() {
  local project_root="$1"
  printf '%s/state.json' "$(project_monitor_dir "${project_root}")"
}

maybe_prompt_for_config() {
  local mode="$1"
  [[ "${mode}" == "prompt" ]] || return 0

  echo "进入 push-code 配置向导，直接回车会保留当前值。" >&2
  echo "高级参数将直接使用默认值写入 config.env，需要时再手动修改。" >&2
  if [[ "${inferred_remote:-0}" -eq 1 ]]; then
    echo "Git remote: 使用自动推断值 '${remote}'" >&2
  else
    prompt_value "Git remote" remote
  fi
  prompt_value "目标主分支" target_branch
  if [[ "${inferred_project_id:-0}" -eq 1 ]]; then
    echo "项目 ID: 使用自动推断值 '${project_id}'" >&2
  else
    prompt_value "项目 ID" project_id
  fi
  prompt_value "MR 标题前缀" mr_title_prefix
  prompt_value "GitLab 基础地址" gitlab_base_url
  prompt_secret "GitLab API token" gitlab_api_token
}

maybe_prompt_for_monitor() {
  local mode="$1"
  [[ "${mode}" == "prompt" ]] || return 0

  if [[ "${project_monitor_enabled}" == "true" ]]; then
    prompt_yes_no "检测到当前项目已接入全局 MR 定时巡检服务，是否继续保持启用" project_monitor_enabled_prompt "yes"
  else
    prompt_yes_no "是否启用全局 Node.js MR 定时巡检服务" project_monitor_enabled_prompt "no"
  fi
  if [[ "${project_monitor_enabled_prompt}" == "yes" ]]; then
    project_monitor_enabled="true"
    prompt_integer "MR 定时巡检间隔（秒）" monitor_interval_seconds
  else
    project_monitor_enabled="false"
  fi
}

is_git_repo() {
  local path="$1"
  local top_level=""
  has_command git || return 1
  top_level="$(git -C "${path}" rev-parse --show-toplevel 2>/dev/null)" || return 1
  [[ "${top_level}" == "${path}" ]]
}

git_remotes() {
  local path="$1"
  git -C "${path}" remote
}

remote_url() {
  local path="$1"
  local remote_name="$2"
  git -C "${path}" remote get-url "${remote_name}"
}

extract_project_id_from_remote_url() {
  local url="$1"
  local path_part=""

  case "${url}" in
    git@*:* )
      path_part="${url#*:}"
      ;;
    ssh://*|http://*|https://* )
      path_part="${url#*://}"
      path_part="${path_part#*/}"
      ;;
    * )
      return 1
      ;;
  esac

  path_part="${path_part#/}"
  path_part="${path_part%.git}"
  [[ -n "${path_part}" && "${path_part}" == */* ]] || return 1
  printf '%s' "${path_part}"
}

maybe_infer_remote_from_git() {
  local path="$1"
  local remotes=()

  if [[ "${remote}" != "origin" ]]; then
    return 0
  fi
  is_git_repo "${path}" || return 0

  while IFS= read -r line; do
    [[ -n "${line}" ]] && remotes+=("${line}")
  done < <(git_remotes "${path}")

  if (( ${#remotes[@]} > 0 )) && printf '%s\n' "${remotes[@]}" | grep -Fxq "origin"; then
    remote="origin"
    inferred_remote=1
    return 0
  fi

  if [[ "${#remotes[@]}" -eq 1 ]]; then
    remote="${remotes[0]}"
    inferred_remote=1
    echo "配置推断: 检测到唯一 git remote '${remote}'" >&2
  fi
}

maybe_infer_project_id_from_git() {
  local path="$1"
  local remote_name="$2"
  local url=""
  local inferred=""

  [[ -n "${project_id}" ]] && return 0
  is_git_repo "${path}" || return 0
  git -C "${path}" remote get-url "${remote_name}" >/dev/null 2>&1 || return 0

  url="$(remote_url "${path}" "${remote_name}" 2>/dev/null || true)"
  [[ -n "${url}" ]] || return 0

  inferred="$(extract_project_id_from_remote_url "${url}" 2>/dev/null || true)"
  [[ -n "${inferred}" ]] || return 0
  project_id="${inferred}"
  inferred_project_id=1
  echo "配置推断: 从 git remote URL 推断 project_id='${project_id}'" >&2
}

remote_exists() {
  local path="$1"
  local remote_name="$2"
  git -C "${path}" remote get-url "${remote_name}" >/dev/null 2>&1
}

check_git_remote_connectivity() {
  local path="$1"
  local remote_name="$2"

  if ! is_git_repo "${path}"; then
    echo "连接检查: 跳过 git remote 检查，目标目录不是 git 仓库" >&2
    return 0
  fi
  if ! remote_exists "${path}" "${remote_name}"; then
    echo "连接检查: 跳过 git remote 检查，未找到 remote '${remote_name}'" >&2
    return 0
  fi

  echo "连接检查: 验证 git remote '${remote_name}'" >&2
  if git -C "${path}" ls-remote "${remote_name}" >/dev/null 2>&1; then
    echo "连接检查: git remote 可用" >&2
    return 0
  fi

  echo "错误: git remote 检查失败: ${remote_name}" >&2
  return 1
}

urlencode_python() {
  local value="$1"
  python3 - "$value" <<'EOF'
import sys
import urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=''))
EOF
}

gitlab_curl() {
  local url="$1"
  local curl_args=()
  local token_value=""

  curl_args=(
    --silent
    --show-error
    --fail
  )

  if [[ -n "${gitlab_api_token}" ]]; then
    token_value="${gitlab_api_token}"
    if [[ -n "${gitlab_token_scheme}" ]]; then
      token_value="${gitlab_token_scheme} ${token_value}"
    fi
    curl_args+=(--header "${gitlab_token_header_name}: ${token_value}")
  fi

  if [[ -n "${extra_header_name}" && -n "${extra_header_value}" ]]; then
    curl_args+=(--header "${extra_header_name}: ${extra_header_value}")
  fi
  if [[ -n "${gitlab_ca_bundle}" ]]; then
    curl_args+=(--cacert "${gitlab_ca_bundle}")
  fi
  if [[ "${gitlab_skip_tls_verify}" == "true" ]]; then
    curl_args+=(--insecure)
  fi

  curl "${curl_args[@]}" "${url}"
}

gitlab_check_auth() {
  if [[ -z "${gitlab_base_url}" ]]; then
    echo "连接检查: 跳过 GitLab API 鉴权检查，未配置基础地址" >&2
    return 0
  fi
  if [[ -z "${gitlab_api_token}" ]]; then
    echo "连接检查: 跳过 GitLab API 鉴权检查，未配置 token" >&2
    return 0
  fi
  has_command curl || {
    echo "连接检查: 跳过 GitLab API 鉴权检查，当前环境缺少 curl" >&2
    return 0
  }

  echo "连接检查: 验证 GitLab API 鉴权" >&2
  if gitlab_curl "${gitlab_base_url%/}/api/v4/user" >/dev/null 2>&1; then
    echo "连接检查: GitLab API 鉴权通过" >&2
    return 0
  fi

  echo "错误: GitLab API 鉴权失败，请确认地址、token 和 TLS 配置。" >&2
  return 1
}

gitlab_check_project() {
  local encoded_project_id=""

  if [[ -z "${gitlab_base_url}" ]]; then
    echo "连接检查: 跳过 GitLab 项目检查，未配置基础地址" >&2
    return 0
  fi
  if [[ -z "${gitlab_api_token}" ]]; then
    echo "连接检查: 跳过 GitLab 项目检查，未配置 token" >&2
    return 0
  fi
  if [[ -z "${project_id}" ]]; then
    echo "连接检查: 跳过 GitLab 项目检查，未配置 project_id" >&2
    return 0
  fi
  has_command curl || {
    echo "连接检查: 跳过 GitLab 项目检查，当前环境缺少 curl" >&2
    return 0
  }

  encoded_project_id="$(urlencode_python "${project_id}")"
  echo "连接检查: 验证 GitLab 项目 ${project_id}" >&2
  if gitlab_curl "${gitlab_base_url%/}/api/v4/projects/${encoded_project_id}" >/dev/null 2>&1; then
    echo "连接检查: GitLab 项目可访问" >&2
    return 0
  fi

  echo "错误: GitLab 项目检查失败: ${project_id}" >&2
  echo "请确认 project_id 与 token 权限是否正确。" >&2
  return 1
}

run_connectivity_checks() {
  local target_project="$1"
  local mode="$2"
  local checked_any=0

  [[ "${mode}" == "check" ]] || {
    echo "连接检查: 已跳过（--no-connectivity-check）" >&2
    return 0
  }

  echo "开始执行 push-code 初始化连通性检查..." >&2

  if is_git_repo "${target_project}" && remote_exists "${target_project}" "${remote}"; then
    checked_any=1
  fi
  if [[ -n "${gitlab_base_url}${gitlab_api_token}" ]]; then
    checked_any=1
  fi

  if ! check_git_remote_connectivity "${target_project}" "${remote}"; then
    return 1
  fi
  if ! gitlab_check_auth; then
    return 1
  fi
  if ! gitlab_check_project; then
    return 1
  fi

  if [[ "${checked_any}" -eq 0 ]]; then
    echo "连接检查: 没有可执行的检查项，已跳过" >&2
  else
    echo "连接检查: 已完成" >&2
  fi
}

write_config() {
  local destination="$1"
  local monitor_db_path="$2"
  local monitor_config_path="$3"
  local previous_config_path="${4-}"

  {
    echo "# push-code skill runtime configuration"
    echo "# Fill empty GitLab values before using the workflow."
    printf "PUSH_CODE_GIT_REMOTE=%s\n" "$(quote_env "${remote}")"
    printf "PUSH_CODE_TARGET_BRANCH=%s\n" "$(quote_env "${target_branch}")"
    printf "PUSH_CODE_PROJECT_ID=%s\n" "$(quote_env "${project_id}")"
    printf "PUSH_CODE_MR_TITLE_PREFIX=%s\n" "$(quote_env "${mr_title_prefix}")"
    printf "PUSH_CODE_POLL_INTERVAL_SECONDS=%s\n" "$(quote_env "${poll_interval_seconds}")"
    printf "PUSH_CODE_REVIEW_TIMEOUT_SECONDS=%s\n" "$(quote_env "${review_timeout_seconds}")"
    printf "PUSH_CODE_GITLAB_INITIAL_REVIEW_GRACE_SECONDS=%s\n" "$(quote_env "${initial_review_grace_seconds}")"
    echo
    printf "PUSH_CODE_GITLAB_BASE_URL=%s\n" "$(quote_env "${gitlab_base_url}")"
    printf "PUSH_CODE_GITLAB_API_TOKEN=%s\n" "$(quote_env "${gitlab_api_token}")"
    printf "PUSH_CODE_GITLAB_TOKEN_HEADER_NAME=%s\n" "$(quote_env "${gitlab_token_header_name}")"
    printf "PUSH_CODE_GITLAB_TOKEN_SCHEME=%s\n" "$(quote_env "${gitlab_token_scheme}")"
    printf "PUSH_CODE_GITLAB_CA_BUNDLE=%s\n" "$(quote_env "${gitlab_ca_bundle}")"
    printf "PUSH_CODE_GITLAB_SKIP_TLS_VERIFY=%s\n" "$(quote_env "${gitlab_skip_tls_verify}")"
    printf "PUSH_CODE_GITLAB_EXTRA_HEADER_NAME=%s\n" "$(quote_env "${extra_header_name}")"
    printf "PUSH_CODE_GITLAB_EXTRA_HEADER_VALUE=%s\n" "$(quote_env "${extra_header_value}")"
    echo
    printf "PUSH_CODE_MR_MONITOR_ENABLED=%s\n" "$(quote_env "${project_monitor_enabled}")"
    printf "PUSH_CODE_MR_MONITOR_DB_PATH=%s\n" "$(quote_env "${monitor_db_path}")"
    printf "PUSH_CODE_MR_MONITOR_CONFIG_PATH=%s\n" "$(quote_env "${monitor_config_path}")"
    printf "PUSH_CODE_MR_MONITOR_INTERVAL_SECONDS=%s\n" "$(quote_env "${monitor_interval_seconds}")"
    echo
    printf "PUSH_CODE_REVIEW_APPROVED_STATES=%s\n" "$(quote_env "${approved_states}")"
    printf "PUSH_CODE_REVIEW_CHANGES_REQUESTED_STATES=%s\n" "$(quote_env "${changes_requested_states}")"
    printf "PUSH_CODE_REVIEW_PENDING_STATES=%s\n" "$(quote_env "${pending_states}")"
  } > "${destination}"

  if [[ -n "${previous_config_path}" ]]; then
    append_preserved_config_entries "${previous_config_path}" "${destination}"
  fi
}

agents_block() {
  cat <<'EOF'
<!-- BEGIN push-code -->
## Push Code 工作流

当用户显式要求使用 `push-code skill`、`push code workflow`、`推当前分支并创建 MR`、`跟进 GitLab review 到可提交状态` 时，优先使用项目级 skill：

- `.codex/skills/push-code/SKILL.md`

不要默认对所有普通请求启用该流程；只有用户明确要求时才触发。

该工作流要求当前分支处于 clean working tree，然后由当前 Codex 会话：

- 先 push 当前分支到 GitLab
- 如果 push 时命中本地 pre-push 检查失败，先分析并修复，再重新 commit + push
- 通过 GitLab REST API 创建一个合到主分支的 MR，并记录 `mr_id`
- 持续轮询 GitLab 上的 review 状态、discussions、普通 MR notes 与 mergeability blockers，直到 MR 达到可提交状态或出现明确 blocker
- 如果 GitLab 判定当前源分支必须先 rebase 到目标分支，先本地 rebase，再用 `push --force-with-lease` 更新远端分支
- 对有争议的问题通过 GitLab discussions 或普通 MR note 回复
- 对已经修复完成的 unresolved discussion thread，显式标记为 resolved
- 对无争议的问题修复代码后重新 commit + push，直到 MR 达到可提交状态
- 最终提交或合并必须交由人工完成，不能自动 merge MR

相关资源位于：

- `.codex/skills/push-code/config.env`
- `.codex/skills/push-code/bin/push-code-run.sh`
- `.codex/skills/push-code/bin/push_code_webhook.py`
- `.codex/skills/push-code/reference.md`
<!-- END push-code -->
EOF
}

upsert_agents_block() {
  local file="$1"
  local block
  local block_file
  local tmp_file

  block="$(agents_block)"
  block_file="$(mktemp)"
  tmp_file="$(mktemp)"
  printf "%s\n" "${block}" > "${block_file}"

  if [[ -f "${file}" ]]; then
    awk \
      -v begin1="${BEGIN_MARKER}" \
      -v end1="${END_MARKER}" \
      -v block_file="${block_file}" '
      function print_block(   line) {
        while ((getline line < block_file) > 0) {
          print line
        }
        close(block_file)
      }
      BEGIN {
        inside = 0
      }
      $0 == begin1 {
        inside = 1
        next
      }
      $0 == end1 {
        inside = 0
        next
      }
      inside {
        next
      }
      {
        print
      }
      END {
        if (NR > 0) {
          print ""
        }
        print_block()
      }
    ' "${file}" > "${tmp_file}"
  else
    printf "%s\n" "${block}" > "${tmp_file}"
  fi

  mv "${tmp_file}" "${file}"
  rm -f "${block_file}"
}

clean_previous_install() {
  local target_project="$1"
  remove_if_exists "${target_project}/${HOST_SKILL_RELATIVE}"
}

main() {
  local target_project=""
  local prompt_mode="auto"
  local connectivity_check_mode="auto"
  local remote="origin"
  local target_branch="main"
  local project_id=""
  local mr_title_prefix="${HOST_MR_PREFIX}"
  local gitlab_base_url=""
  local gitlab_api_token=""
  local gitlab_token_header_name="PRIVATE-TOKEN"
  local gitlab_token_scheme=""
  local gitlab_ca_bundle=""
  local gitlab_skip_tls_verify="false"
  local extra_header_name=""
  local extra_header_value=""
  local poll_interval_seconds="30"
  local review_timeout_seconds="3600"
  local initial_review_grace_seconds="60"
  local project_monitor_enabled="false"
  local project_monitor_enabled_prompt=""
  local monitor_interval_seconds="300"
  local approved_states="approved,pass"
  local changes_requested_states="changes_requested,fail,blocked"
  local pending_states="pending,running,queued,waiting"
  local existing_config=""
  local inferred_remote=0
  local inferred_project_id=0
  local cli_remote=""
  local cli_target_branch=""
  local cli_project_id=""
  local cli_mr_title_prefix=""
  local cli_gitlab_base_url=""
  local cli_gitlab_api_token=""
  local cli_gitlab_token_header_name=""
  local cli_gitlab_token_scheme=""
  local cli_gitlab_ca_bundle=""
  local cli_gitlab_skip_tls_verify=""
  local cli_extra_header_name=""
  local cli_extra_header_value=""
  local cli_poll_interval_seconds=""
  local cli_review_timeout_seconds=""
  local cli_initial_review_grace_seconds=""
  local cli_monitor_interval_seconds=""
  local cli_approved_states=""
  local cli_changes_requested_states=""
  local cli_pending_states=""
  local cli_claude_bin=""
  local set_remote=0
  local set_target_branch=0
  local set_project_id=0
  local set_mr_title_prefix=0
  local set_gitlab_base_url=0
  local set_gitlab_api_token=0
  local set_gitlab_token_header_name=0
  local set_gitlab_token_scheme=0
  local set_gitlab_ca_bundle=0
  local set_gitlab_skip_tls_verify=0
  local set_extra_header_name=0
  local set_extra_header_value=0
  local set_poll_interval_seconds=0
  local set_review_timeout_seconds=0
  local set_initial_review_grace_seconds=0
  local set_project_monitor_enabled=0
  local set_monitor_interval_seconds=0
  local set_approved_states=0
  local set_changes_requested_states=0
  local set_pending_states=0
  local previous_config_tmp=""
  local previous_monitor_config_tmp=""
  local previous_monitor_db_tmp=""
  local previous_monitor_state_tmp=""
  local monitor_state_path=""
  local monitor_db_path=""
  local monitor_config_path=""

  while [[ $# -gt 0 ]]; do
    case "${1-}" in
      --prompt)
        prompt_mode="prompt"
        shift
        ;;
      --no-prompt)
        prompt_mode="no-prompt"
        shift
        ;;
      --check-connectivity)
        connectivity_check_mode="check"
        shift
        ;;
      --no-connectivity-check)
        connectivity_check_mode="skip"
        shift
        ;;
      --remote)
        cli_remote="${2-}"
        remote="${cli_remote}"
        set_remote=1
        shift 2
        ;;
      --target-branch)
        cli_target_branch="${2-}"
        target_branch="${cli_target_branch}"
        set_target_branch=1
        shift 2
        ;;
      --project-id)
        cli_project_id="${2-}"
        project_id="${cli_project_id}"
        set_project_id=1
        shift 2
        ;;
      --mr-title-prefix)
        cli_mr_title_prefix="${2-}"
        mr_title_prefix="${cli_mr_title_prefix}"
        set_mr_title_prefix=1
        shift 2
        ;;
      --gitlab-base-url)
        cli_gitlab_base_url="${2-}"
        gitlab_base_url="${cli_gitlab_base_url}"
        set_gitlab_base_url=1
        shift 2
        ;;
      --gitlab-api-token)
        cli_gitlab_api_token="${2-}"
        gitlab_api_token="${cli_gitlab_api_token}"
        set_gitlab_api_token=1
        shift 2
        ;;
      --gitlab-token-header-name)
        cli_gitlab_token_header_name="${2-}"
        gitlab_token_header_name="${cli_gitlab_token_header_name}"
        set_gitlab_token_header_name=1
        shift 2
        ;;
      --gitlab-token-scheme)
        cli_gitlab_token_scheme="${2-}"
        gitlab_token_scheme="${cli_gitlab_token_scheme}"
        set_gitlab_token_scheme=1
        shift 2
        ;;
      --gitlab-ca-bundle)
        cli_gitlab_ca_bundle="${2-}"
        gitlab_ca_bundle="${cli_gitlab_ca_bundle}"
        set_gitlab_ca_bundle=1
        shift 2
        ;;
      --gitlab-skip-tls-verify)
        cli_gitlab_skip_tls_verify="${2-}"
        gitlab_skip_tls_verify="${cli_gitlab_skip_tls_verify}"
        set_gitlab_skip_tls_verify=1
        shift 2
        ;;
      --extra-header-name)
        cli_extra_header_name="${2-}"
        extra_header_name="${cli_extra_header_name}"
        set_extra_header_name=1
        shift 2
        ;;
      --extra-header-value)
        cli_extra_header_value="${2-}"
        extra_header_value="${cli_extra_header_value}"
        set_extra_header_value=1
        shift 2
        ;;
      --poll-interval-seconds)
        cli_poll_interval_seconds="${2-}"
        poll_interval_seconds="${cli_poll_interval_seconds}"
        set_poll_interval_seconds=1
        shift 2
        ;;
      --review-timeout-seconds)
        cli_review_timeout_seconds="${2-}"
        review_timeout_seconds="${cli_review_timeout_seconds}"
        set_review_timeout_seconds=1
        shift 2
        ;;
      --initial-review-grace-seconds)
        cli_initial_review_grace_seconds="${2-}"
        initial_review_grace_seconds="${cli_initial_review_grace_seconds}"
        set_initial_review_grace_seconds=1
        shift 2
        ;;
      --enable-mr-monitor|--install-mr-monitor|--join-mr-monitor)
        project_monitor_enabled="true"
        set_project_monitor_enabled=1
        shift
        ;;
      --disable-mr-monitor|--skip-mr-monitor-install|--skip-join-mr-monitor)
        project_monitor_enabled="false"
        set_project_monitor_enabled=1
        shift
        ;;
      --mr-monitor-interval-seconds)
        cli_monitor_interval_seconds="${2-}"
        monitor_interval_seconds="${cli_monitor_interval_seconds}"
        set_monitor_interval_seconds=1
        shift 2
        ;;
      --mr-monitor-interval-minutes)
        cli_monitor_interval_seconds="$(( ${2-} * 60 ))"
        monitor_interval_seconds="${cli_monitor_interval_seconds}"
        set_monitor_interval_seconds=1
        shift 2
        ;;
      --approved-states)
        cli_approved_states="${2-}"
        approved_states="${cli_approved_states}"
        set_approved_states=1
        shift 2
        ;;
      --changes-requested-states)
        cli_changes_requested_states="${2-}"
        changes_requested_states="${cli_changes_requested_states}"
        set_changes_requested_states=1
        shift 2
        ;;
      --pending-states)
        cli_pending_states="${2-}"
        pending_states="${cli_pending_states}"
        set_pending_states=1
        shift 2
        ;;
      --claude-bin)
        cli_claude_bin="${2-}"
        shift 2
        ;;
      --)
        shift
        break
        ;;
      -*)
        usage
        exit 1
        ;;
      *)
        break
        ;;
    esac
  done

  [[ $# -eq 1 ]] || {
    usage
    exit 1
  }

  target_project="$1"
  require_directory "${target_project}"
  target_project="$(canonicalize_directory "${target_project}")"

  existing_config="${target_project}/${HOST_SKILL_RELATIVE}/config.env"
  apply_existing_config "${existing_config}"
  (( set_remote )) && remote="${cli_remote}"
  (( set_target_branch )) && target_branch="${cli_target_branch}"
  (( set_project_id )) && project_id="${cli_project_id}"
  (( set_mr_title_prefix )) && mr_title_prefix="${cli_mr_title_prefix}"
  (( set_gitlab_base_url )) && gitlab_base_url="${cli_gitlab_base_url}"
  (( set_gitlab_api_token )) && gitlab_api_token="${cli_gitlab_api_token}"
  (( set_gitlab_token_header_name )) && gitlab_token_header_name="${cli_gitlab_token_header_name}"
  (( set_gitlab_token_scheme )) && gitlab_token_scheme="${cli_gitlab_token_scheme}"
  (( set_gitlab_ca_bundle )) && gitlab_ca_bundle="${cli_gitlab_ca_bundle}"
  (( set_gitlab_skip_tls_verify )) && gitlab_skip_tls_verify="${cli_gitlab_skip_tls_verify}"
  (( set_extra_header_name )) && extra_header_name="${cli_extra_header_name}"
  (( set_extra_header_value )) && extra_header_value="${cli_extra_header_value}"
  (( set_poll_interval_seconds )) && poll_interval_seconds="${cli_poll_interval_seconds}"
  (( set_review_timeout_seconds )) && review_timeout_seconds="${cli_review_timeout_seconds}"
  (( set_initial_review_grace_seconds )) && initial_review_grace_seconds="${cli_initial_review_grace_seconds}"
  (( set_monitor_interval_seconds )) && monitor_interval_seconds="${cli_monitor_interval_seconds}"
  (( set_approved_states )) && approved_states="${cli_approved_states}"
  (( set_changes_requested_states )) && changes_requested_states="${cli_changes_requested_states}"
  (( set_pending_states )) && pending_states="${cli_pending_states}"

  maybe_infer_remote_from_git "${target_project}"
  maybe_infer_project_id_from_git "${target_project}" "${remote}"

  if [[ "${prompt_mode}" == "auto" ]]; then
    if [[ -t 0 && -t 1 ]]; then
      prompt_mode="prompt"
    else
      prompt_mode="no-prompt"
    fi
  fi

  if [[ "${connectivity_check_mode}" == "auto" ]]; then
    connectivity_check_mode="check"
  fi

  maybe_prompt_for_config "${prompt_mode}"
  maybe_prompt_for_monitor "${prompt_mode}"

  if [[ "${prompt_mode}" == "no-prompt" && "${set_project_monitor_enabled}" -eq 0 ]]; then
    project_monitor_enabled="${project_monitor_enabled:-false}"
  fi

  has_command node || {
    echo "错误: 初始化 push-code 模板需要 node 命令，以便安装全局 MR 定时巡检工具" >&2
    exit 1
  }

  monitor_config_path="$(global_monitor_config_path)"
  monitor_db_path="$(global_monitor_db_path)"
  monitor_state_path="$(global_monitor_legacy_state_path)"
  local_project_monitor_config_path="$(project_monitor_config_path "${target_project}")"
  local_project_monitor_db_path="$(project_monitor_db_path "${target_project}")"
  local_project_monitor_state_path="$(project_monitor_legacy_state_path "${target_project}")"

  if [[ -f "${existing_config}" ]]; then
    previous_config_tmp="$(mktemp)"
    cp "${existing_config}" "${previous_config_tmp}"
  fi
  if [[ -f "${local_project_monitor_config_path}" ]]; then
    previous_monitor_config_tmp="$(mktemp)"
    cp "${local_project_monitor_config_path}" "${previous_monitor_config_tmp}"
  fi
  if [[ -f "${local_project_monitor_db_path}" ]]; then
    previous_monitor_db_tmp="$(mktemp)"
    cp "${local_project_monitor_db_path}" "${previous_monitor_db_tmp}"
  fi
  if [[ -f "${local_project_monitor_state_path}" ]]; then
    previous_monitor_state_tmp="$(mktemp)"
    cp "${local_project_monitor_state_path}" "${previous_monitor_state_tmp}"
  fi

  clean_previous_install "${target_project}"

  mkdir -p \
    "${target_project}/${HOST_SKILL_RELATIVE}/bin" \
    "$(global_monitor_bin_dir)"

  remove_if_exists "$(global_monitor_bin_dir)/install-dingtalk-webhook.sh"

  copy_file "${HOST_DIR}/skill/SKILL.md" "${target_project}/${HOST_SKILL_RELATIVE}/SKILL.md"
  if [[ -f "${HOST_DIR}/reference.md" ]]; then
    copy_file "${HOST_DIR}/reference.md" "${target_project}/${HOST_SKILL_RELATIVE}/reference.md"
  else
    copy_file "${COMMON_DIR}/reference.md" "${target_project}/${HOST_SKILL_RELATIVE}/reference.md"
  fi
  copy_file "${COMMON_DIR}/bin/push-code-run.sh" "${target_project}/${HOST_SKILL_RELATIVE}/bin/push-code-run.sh"
  copy_file "${COMMON_DIR}/bin/push_code_webhook.py" "${target_project}/${HOST_SKILL_RELATIVE}/bin/push_code_webhook.py"
  copy_file "${COMMON_DIR}/bin/push-code-monitor.cjs" "${target_project}/${HOST_SKILL_RELATIVE}/bin/push-code-monitor.cjs"
  copy_file "${COMMON_DIR}/bin/push-code-monitor.cjs" "$(global_monitor_script_path)"

  chmod +x \
    "${target_project}/${HOST_SKILL_RELATIVE}/bin/push-code-run.sh" \
    "${target_project}/${HOST_SKILL_RELATIVE}/bin/push_code_webhook.py" \
    "${target_project}/${HOST_SKILL_RELATIVE}/bin/push-code-monitor.cjs" \
    "$(global_monitor_script_path)"

  if [[ -n "${previous_monitor_config_tmp}" && ! -f "${monitor_config_path}" ]]; then
    mkdir -p "$(dirname "${monitor_config_path}")"
    cp "${previous_monitor_config_tmp}" "${monitor_config_path}"
  fi

  node "$(global_monitor_script_path)" init \
    --config-path "${monitor_config_path}" \
    --db-path "${monitor_db_path}" \
    --legacy-state-path "${previous_monitor_state_tmp:-${monitor_state_path}}" \
    --legacy-db-path "${previous_monitor_db_tmp:-}" \
    --enabled "${project_monitor_enabled}" \
    --interval-seconds "${monitor_interval_seconds}" >/dev/null

  if [[ -n "${cli_claude_bin}" ]]; then
    node "$(global_monitor_script_path)" config-set \
      --config-path "${monitor_config_path}" \
      --claude-bin "${cli_claude_bin}" >/dev/null
  fi

  if [[ -n "${previous_monitor_config_tmp}" ]]; then
    rm -f "${previous_monitor_config_tmp}"
  fi
  if [[ -n "${previous_monitor_db_tmp}" ]]; then
    rm -f "${previous_monitor_db_tmp}"
  fi
  if [[ -n "${previous_monitor_state_tmp}" ]]; then
    rm -f "${previous_monitor_state_tmp}"
  fi

  write_config \
    "${target_project}/${HOST_SKILL_RELATIVE}/config.env" \
    "${monitor_db_path}" \
    "${monitor_config_path}" \
    "${previous_config_tmp}"

  if [[ -n "${previous_config_tmp}" ]]; then
    rm -f "${previous_config_tmp}"
  fi

  if [[ "${HOST_KIND}" == "codex" ]]; then
    upsert_agents_block "${target_project}/AGENTS.md"
  fi

  echo "已初始化 ${HOST_LABEL} 版 push-code 工作流:"
  echo "- 目标项目: ${target_project}"
  echo "- skill: ${HOST_SKILL_RELATIVE}/SKILL.md"
  echo "- config: ${HOST_SKILL_RELATIVE}/config.env"
  echo "- launcher: ${HOST_SKILL_RELATIVE}/bin/push-code-run.sh"
  echo "- project monitor bridge: ${HOST_SKILL_RELATIVE}/bin/push-code-monitor.cjs"
  if [[ "${project_monitor_enabled}" == "true" ]]; then
    echo "- 全局 MR 定时巡检: 已启用"
    echo "- MR 定时巡检间隔（秒）: ${monitor_interval_seconds}"
    echo "- global monitor script: $(global_monitor_script_path)"
    echo "- global monitor db: ${monitor_db_path}"
    echo "- monitor service: 未启动（请手动执行 $(global_monitor_script_path) start）"
  else
    echo "- 全局 MR 定时巡检: 未启用"
  fi

  run_connectivity_checks "${target_project}" "${connectivity_check_mode}"
}

main "$@"
