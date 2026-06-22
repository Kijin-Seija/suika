#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${SKILL_DIR}/config.env"
PYTHON_BIN="${PYTHON_BIN:-python3}"
GITLAB_HELPER="${SCRIPT_DIR}/push_code_webhook.py"
MR_MONITOR_HELPER="${SCRIPT_DIR}/push-code-monitor.cjs"

usage() {
  cat >&2 <<'EOF'
用法:
  push-code-run.sh preflight
  push-code-run.sh push [--force-with-lease]
  push-code-run.sh rebase-target
  push-code-run.sh create-mr [--title <title>] [--description-file <path>]
  push-code-run.sh status --mr-id <id>
  push-code-run.sh threads --mr-id <id>
  push-code-run.sh wait-review --mr-id <id>
  push-code-run.sh comment --mr-id <id> --thread-id <id> (--body <text> | --body-file <path>)
  push-code-run.sh note --mr-id <id> (--body <text> | --body-file <path>)
  push-code-run.sh resolve-thread --mr-id <id> --thread-id <id>
  push-code-run.sh reopen-thread --mr-id <id> --thread-id <id>
  push-code-run.sh config
EOF
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "错误: 未找到命令: $1" >&2
    exit 1
  }
}

require_config_file() {
  [[ -f "${CONFIG_FILE}" ]] || {
    echo "错误: 缺少配置文件: ${CONFIG_FILE}" >&2
    exit 1
  }
}

load_config() {
  require_config_file
  local allexport_was_enabled=0
  case "$-" in
    *a*)
      allexport_was_enabled=1
      ;;
  esac
  set -a
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
  if [[ "${allexport_was_enabled}" -eq 0 ]]; then
    set +a
  fi
  : "${PUSH_CODE_GIT_REMOTE:=origin}"
  : "${PUSH_CODE_TARGET_BRANCH:=main}"
  : "${PUSH_CODE_PROJECT_ID:=}"
  : "${PUSH_CODE_MR_TITLE_PREFIX:=[Codex]}"
  : "${PUSH_CODE_POLL_INTERVAL_SECONDS:=30}"
  : "${PUSH_CODE_REVIEW_TIMEOUT_SECONDS:=3600}"
  : "${PUSH_CODE_GITLAB_BASE_URL:=}"
  : "${PUSH_CODE_GITLAB_API_TOKEN:=${PUSH_CODE_WEBHOOK_AUTH_TOKEN:-}}"
  : "${PUSH_CODE_GITLAB_TOKEN_HEADER_NAME:=${PUSH_CODE_WEBHOOK_AUTH_HEADER_NAME:-PRIVATE-TOKEN}}"
  : "${PUSH_CODE_GITLAB_TOKEN_SCHEME:=${PUSH_CODE_WEBHOOK_AUTH_SCHEME:-}}"
  : "${PUSH_CODE_GITLAB_CA_BUNDLE:=}"
  : "${PUSH_CODE_GITLAB_SKIP_TLS_VERIFY:=false}"
  : "${PUSH_CODE_MR_MONITOR_ENABLED:=false}"
  : "${PUSH_CODE_MR_MONITOR_DB_PATH:=}"
  : "${PUSH_CODE_MR_MONITOR_CONFIG_PATH:=}"
  : "${PUSH_CODE_MR_MONITOR_INTERVAL_SECONDS:=300}"
}

require_git_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "错误: 当前目录不是 git 仓库" >&2
    exit 1
  }
}

current_branch() {
  git rev-parse --abbrev-ref HEAD
}

ensure_not_detached() {
  local branch
  branch="$(current_branch)"
  [[ "${branch}" != "HEAD" ]] || {
    echo "错误: 当前处于 detached HEAD，无法执行 push-code 工作流" >&2
    exit 1
  }
}

ensure_clean_worktree() {
  git update-index -q --refresh
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "错误: 工作区存在未提交改动，push-code 工作流要求 clean working tree" >&2
    git status --short >&2 || true
    exit 1
  fi
}

ensure_not_target_branch() {
  local branch="$1"
  [[ "${branch}" != "${PUSH_CODE_TARGET_BRANCH}" ]] || {
    echo "错误: 当前分支就是目标分支 ${PUSH_CODE_TARGET_BRANCH}，拒绝为其创建 MR" >&2
    exit 1
  }
}

print_preflight_json() {
  local branch="$1"
  printf '{\n'
  printf '  "branch": "%s",\n' "${branch}"
  printf '  "remote": "%s",\n' "${PUSH_CODE_GIT_REMOTE}"
  printf '  "target_branch": "%s",\n' "${PUSH_CODE_TARGET_BRANCH}"
  printf '  "clean": true\n'
  printf '}\n'
}

cmd_preflight() {
  require_command git
  require_git_repo
  load_config
  ensure_not_detached
  ensure_clean_worktree
  local branch
  branch="$(current_branch)"
  ensure_not_target_branch "${branch}"
  print_preflight_json "${branch}"
}

cmd_push() {
  require_command git
  require_git_repo
  load_config
  ensure_not_detached
  ensure_clean_worktree
  local branch status push_mode=""
  while [[ $# -gt 0 ]]; do
    case "${1-}" in
      --force-with-lease)
        push_mode="--force-with-lease"
        shift
        ;;
      *)
        usage
        exit 1
        ;;
    esac
  done
  branch="$(current_branch)"
  ensure_not_target_branch "${branch}"
  if git rev-parse --verify --quiet "@{upstream}" >/dev/null 2>&1; then
    if git push ${push_mode:+${push_mode}} "${PUSH_CODE_GIT_REMOTE}" "${branch}"; then
      return 0
    fi
    status=$?
  else
    if git push ${push_mode:+${push_mode}} --set-upstream "${PUSH_CODE_GIT_REMOTE}" "${branch}"; then
      return 0
    fi
    status=$?
  fi
  cat >&2 <<'EOF'
错误: git push 失败。

如果失败来自本地 pre-push 检查脚本，请先阅读报错、分析失败原因，修复代码或配置后重新：
1. `git add`
2. `git commit`
3. 再次执行 `push-code-run.sh push`

不要跳过 pre-push 检查，也不要在没有新 commit 的情况下重复空推。
EOF
  exit "${status}"
}

print_rebase_json() {
  local branch="$1"
  printf '{\n'
  printf '  "branch": "%s",\n' "${branch}"
  printf '  "target_branch": "%s",\n' "${PUSH_CODE_TARGET_BRANCH}"
  printf '  "remote": "%s",\n' "${PUSH_CODE_GIT_REMOTE}"
  printf '  "rebased_onto": "%s/%s"\n' "${PUSH_CODE_GIT_REMOTE}" "${PUSH_CODE_TARGET_BRANCH}"
  printf '}\n'
}

cmd_rebase_target() {
  require_command git
  require_git_repo
  load_config
  ensure_not_detached
  ensure_clean_worktree
  local branch upstream_ref
  branch="$(current_branch)"
  ensure_not_target_branch "${branch}"
  upstream_ref="${PUSH_CODE_GIT_REMOTE}/${PUSH_CODE_TARGET_BRANCH}"

  if ! git fetch "${PUSH_CODE_GIT_REMOTE}" "${PUSH_CODE_TARGET_BRANCH}"; then
    echo "错误: 无法获取目标分支 ${upstream_ref}" >&2
    exit 1
  fi

  if git rebase "${upstream_ref}"; then
    print_rebase_json "${branch}"
    return 0
  fi

  cat >&2 <<EOF
错误: 将当前分支 rebase 到 ${upstream_ref} 时失败。

请先解决 rebase 冲突，然后根据实际情况执行：
1. git rebase --continue
2. 运行必要验证
3. .codex/skills/push-code/bin/push-code-run.sh push --force-with-lease

如果决定放弃本次 rebase，可执行：
- git rebase --abort
EOF
  exit 1
}

require_gitlab_prereqs() {
  require_command "${PYTHON_BIN}"
  [[ -x "${GITLAB_HELPER}" ]] || {
    echo "错误: helper 不可执行: ${GITLAB_HELPER}" >&2
    exit 1
  }
  [[ -n "${PUSH_CODE_GITLAB_BASE_URL}" ]] || {
    echo "错误: 缺少 GitLab 基础地址配置 PUSH_CODE_GITLAB_BASE_URL" >&2
    exit 1
  }
  [[ -n "${PUSH_CODE_PROJECT_ID}" ]] || {
    echo "错误: 缺少项目标识配置 PUSH_CODE_PROJECT_ID" >&2
    exit 1
  }
}

monitor_enabled() {
  [[ "${PUSH_CODE_MR_MONITOR_ENABLED}" == "true" ]] || return 1
  [[ -n "${PUSH_CODE_MR_MONITOR_DB_PATH}" ]] || return 1
  [[ -x "${MR_MONITOR_HELPER}" ]] || return 1
  return 0
}

register_mr_monitor_mapping() {
  local mr_json="$1"
  local branch="$2"
  local thread_id="${CODEX_THREAD_ID:-}"
  local mr_id="" mr_url=""

  monitor_enabled || return 0
  [[ -n "${thread_id}" ]] || return 0

  if ! mr_id="$(printf '%s' "${mr_json}" | "${PYTHON_BIN}" -c 'import json,sys; payload=json.load(sys.stdin); print(payload.get("mr_id",""))' 2>/dev/null)"; then
    return 0
  fi
  [[ -n "${mr_id}" ]] || return 0
  mr_url="$(printf '%s' "${mr_json}" | "${PYTHON_BIN}" -c 'import json,sys; payload=json.load(sys.stdin); print(payload.get("mr_url",""))' 2>/dev/null || true)"

  node "${MR_MONITOR_HELPER}" registration-upsert \
    --db-path "${PUSH_CODE_MR_MONITOR_DB_PATH}" \
    --mr-id "${mr_id}" \
    --thread-id "${thread_id}" \
    --branch "${branch}" \
    --target-branch "${PUSH_CODE_TARGET_BRANCH}" \
    --mr-url "${mr_url}" \
    --project-id "${PUSH_CODE_PROJECT_ID}" \
    --project-root "$(pwd -P)" \
    --launcher-path "${SCRIPT_DIR}/push-code-run.sh" >/dev/null 2>&1 || true
}

default_title() {
  local branch="$1"
  printf '%s %s' "${PUSH_CODE_MR_TITLE_PREFIX}" "${branch}"
}

cmd_create_mr() {
  require_command git
  require_git_repo
  load_config
  require_gitlab_prereqs
  local branch title="" description_file="" description="" result=""

  while [[ $# -gt 0 ]]; do
    case "${1-}" in
      --title)
        title="${2-}"
        shift 2
        ;;
      --description-file)
        description_file="${2-}"
        shift 2
        ;;
      *)
        usage
        exit 1
        ;;
    esac
  done

  branch="$(current_branch)"
  [[ -n "${title}" ]] || title="$(default_title "${branch}")"
  if [[ -n "${description_file}" ]]; then
    description="$(<"${description_file}")"
  fi

  result="$("${PYTHON_BIN}" "${GITLAB_HELPER}" create-mr \
    --branch "${branch}" \
    --target-branch "${PUSH_CODE_TARGET_BRANCH}" \
    --project-id "${PUSH_CODE_PROJECT_ID}" \
    --title "${title}" \
    --description "${description}")"
  printf '%s\n' "${result}"
  register_mr_monitor_mapping "${result}" "${branch}"
}

parse_mr_id_args() {
  local mr_id=""
  while [[ $# -gt 0 ]]; do
    case "${1-}" in
      --mr-id)
        mr_id="${2-}"
        shift 2
        ;;
      *)
        usage
        exit 1
        ;;
    esac
  done
  [[ -n "${mr_id}" ]] || {
    echo "错误: 缺少 --mr-id" >&2
    exit 1
  }
  printf '%s' "${mr_id}"
}

cmd_status() {
  load_config
  require_gitlab_prereqs
  local mr_id
  mr_id="$(parse_mr_id_args "$@")"
  exec "${PYTHON_BIN}" "${GITLAB_HELPER}" status \
    --mr-id "${mr_id}" \
    --project-id "${PUSH_CODE_PROJECT_ID}"
}

cmd_threads() {
  load_config
  require_gitlab_prereqs
  local mr_id
  mr_id="$(parse_mr_id_args "$@")"
  exec "${PYTHON_BIN}" "${GITLAB_HELPER}" threads \
    --mr-id "${mr_id}" \
    --project-id "${PUSH_CODE_PROJECT_ID}"
}

cmd_wait_review() {
  load_config
  require_gitlab_prereqs
  local mr_id
  mr_id="$(parse_mr_id_args "$@")"
  exec "${PYTHON_BIN}" "${GITLAB_HELPER}" wait-review \
    --mr-id "${mr_id}" \
    --project-id "${PUSH_CODE_PROJECT_ID}" \
    --poll-interval-seconds "${PUSH_CODE_POLL_INTERVAL_SECONDS}" \
    --review-timeout-seconds "${PUSH_CODE_REVIEW_TIMEOUT_SECONDS}"
}

cmd_comment() {
  load_config
  require_gitlab_prereqs
  local mr_id="" thread_id="" body="" body_file=""
  while [[ $# -gt 0 ]]; do
    case "${1-}" in
      --mr-id)
        mr_id="${2-}"
        shift 2
        ;;
      --thread-id)
        thread_id="${2-}"
        shift 2
        ;;
      --body)
        body="${2-}"
        shift 2
        ;;
      --body-file)
        body_file="${2-}"
        shift 2
        ;;
      *)
        usage
        exit 1
        ;;
    esac
  done

  [[ -n "${mr_id}" ]] || {
    echo "错误: 缺少 --mr-id" >&2
    exit 1
  }
  [[ -n "${thread_id}" ]] || {
    echo "错误: 缺少 --thread-id" >&2
    exit 1
  }
  if [[ -n "${body_file}" ]]; then
    body="$(<"${body_file}")"
  fi
  [[ -n "${body}" ]] || {
    echo "错误: 缺少评论正文" >&2
    exit 1
  }

  exec "${PYTHON_BIN}" "${GITLAB_HELPER}" comment \
    --mr-id "${mr_id}" \
    --thread-id "${thread_id}" \
    --project-id "${PUSH_CODE_PROJECT_ID}" \
    --body "${body}"
}

cmd_note() {
  load_config
  require_gitlab_prereqs
  local mr_id="" body="" body_file=""
  while [[ $# -gt 0 ]]; do
    case "${1-}" in
      --mr-id)
        mr_id="${2-}"
        shift 2
        ;;
      --body)
        body="${2-}"
        shift 2
        ;;
      --body-file)
        body_file="${2-}"
        shift 2
        ;;
      *)
        usage
        exit 1
        ;;
    esac
  done

  [[ -n "${mr_id}" ]] || {
    echo "错误: 缺少 --mr-id" >&2
    exit 1
  }
  if [[ -n "${body_file}" ]]; then
    body="$(<"${body_file}")"
  fi
  [[ -n "${body}" ]] || {
    echo "错误: 缺少评论正文" >&2
    exit 1
  }

  exec "${PYTHON_BIN}" "${GITLAB_HELPER}" note \
    --mr-id "${mr_id}" \
    --project-id "${PUSH_CODE_PROJECT_ID}" \
    --body "${body}"
}

cmd_resolve_thread() {
  load_config
  require_gitlab_prereqs
  local mr_id="" thread_id=""
  while [[ $# -gt 0 ]]; do
    case "${1-}" in
      --mr-id)
        mr_id="${2-}"
        shift 2
        ;;
      --thread-id)
        thread_id="${2-}"
        shift 2
        ;;
      *)
        usage
        exit 1
        ;;
    esac
  done

  [[ -n "${mr_id}" ]] || {
    echo "错误: 缺少 --mr-id" >&2
    exit 1
  }
  [[ -n "${thread_id}" ]] || {
    echo "错误: 缺少 --thread-id" >&2
    exit 1
  }

  exec "${PYTHON_BIN}" "${GITLAB_HELPER}" resolve-thread \
    --mr-id "${mr_id}" \
    --thread-id "${thread_id}" \
    --project-id "${PUSH_CODE_PROJECT_ID}"
}

cmd_reopen_thread() {
  load_config
  require_gitlab_prereqs
  local mr_id="" thread_id=""
  while [[ $# -gt 0 ]]; do
    case "${1-}" in
      --mr-id)
        mr_id="${2-}"
        shift 2
        ;;
      --thread-id)
        thread_id="${2-}"
        shift 2
        ;;
      *)
        usage
        exit 1
        ;;
    esac
  done

  [[ -n "${mr_id}" ]] || {
    echo "错误: 缺少 --mr-id" >&2
    exit 1
  }
  [[ -n "${thread_id}" ]] || {
    echo "错误: 缺少 --thread-id" >&2
    exit 1
  }

  exec "${PYTHON_BIN}" "${GITLAB_HELPER}" reopen-thread \
    --mr-id "${mr_id}" \
    --thread-id "${thread_id}" \
    --project-id "${PUSH_CODE_PROJECT_ID}"
}

cmd_config() {
  require_config_file
  cat "${CONFIG_FILE}"
}

main() {
  local subcommand="${1-}"
  [[ $# -gt 0 ]] || {
    usage
    exit 1
  }
  shift

  case "${subcommand}" in
    preflight)
      cmd_preflight "$@"
      ;;
    push)
      cmd_push "$@"
      ;;
    rebase-target)
      cmd_rebase_target "$@"
      ;;
    create-mr)
      cmd_create_mr "$@"
      ;;
    status)
      cmd_status "$@"
      ;;
    threads)
      cmd_threads "$@"
      ;;
    wait-review)
      cmd_wait_review "$@"
      ;;
    comment)
      cmd_comment "$@"
      ;;
    note)
      cmd_note "$@"
      ;;
    resolve-thread)
      cmd_resolve_thread "$@"
      ;;
    reopen-thread)
      cmd_reopen_thread "$@"
      ;;
    config)
      cmd_config "$@"
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
