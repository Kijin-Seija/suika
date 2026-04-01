#!/usr/bin/env bash

set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SELF_DIR}/.." && pwd)"
PROMPTS_DIR="${SKILL_DIR}/prompts"
SCHEMAS_DIR="${SKILL_DIR}/schemas"

CODEX_BIN="${REVIEWER_CODEX_BIN:-${IMPLEMENTATION_LOOP_CODEX_BIN:-codex}}"
CODEX_REVIEW_MODEL="${REVIEWER_CODEX_REVIEW_MODEL:-${REVIEWER_CODEX_MODEL:-${IMPLEMENTATION_LOOP_CODEX_MODEL:-gpt-5.4}}}"

usage() {
  cat >&2 <<'EOF'
用法:
  reviewer-run.sh review --task <task> --artifact-type <code|doc> --topic <slug> --round <n> --max-rounds <n> --artifact <path> [--latest-review <path>] [--latest-response <path>] [--plans-dir <dir>] [--workdir <dir>]
  reviewer-run.sh dispute --task <task> --artifact-type <code|doc> --topic <slug> --max-rounds <n> --latest-artifact <path> --latest-review <path> [--latest-response <path>] [--plans-dir <dir>] [--workdir <dir>]
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || fail "缺少命令: ${cmd}"
}

json_get() {
  local path="$1"
  local expr="$2"
  python3 - "$path" "$expr" <<'PY'
import json
import sys

path = sys.argv[1]
expr = sys.argv[2]

with open(path, "r", encoding="utf-8") as fh:
    value = json.load(fh)

for part in expr.split("."):
    if part.isdigit():
        value = value[int(part)]
    else:
        value = value[part]

if isinstance(value, bool):
    print("true" if value else "false")
elif value is None:
    print("null")
elif isinstance(value, (dict, list)):
    print(json.dumps(value, ensure_ascii=False))
else:
    print(value)
PY
}

validate_response_coverage() {
  local review_json="$1"
  local response_path="$2"

  [[ -f "${review_json}" ]] || fail "review 文件不存在: ${review_json}"
  [[ -f "${response_path}" ]] || fail "response 文件不存在: ${response_path}"

  python3 - "$review_json" "$response_path" <<'PY'
import json
import re
import sys

review_path, response_path = sys.argv[1:3]

with open(review_path, "r", encoding="utf-8") as fh:
    review = json.load(fh)
with open(response_path, "r", encoding="utf-8") as fh:
    response = fh.read()

review_ids = [issue["id"] for issue in review.get("issues", [])]
missing = []
for issue_id in review_ids:
    pattern = re.compile(r"^\s*\d+\.\s+.*\b" + re.escape(issue_id) + r"\b", re.MULTILINE)
    if not pattern.search(response):
        missing.append(issue_id)

if missing:
    print(", ".join(missing))
    sys.exit(1)
PY
}

append_untracked_to_index() {
  local -a untracked=()
  local path

  while IFS= read -r path; do
    untracked+=("${path}")
  done < <(git ls-files --others --exclude-standard)

  if [[ ${#untracked[@]} -gt 0 ]]; then
    git add -N -- "${untracked[@]}"
  fi
}

write_brief() {
  local brief_path="$1"
  local topic="$2"
  local task="$3"
  local artifact_type="$4"
  local max_rounds="$5"
  local baseline="$6"

  cat > "${brief_path}" <<EOF
# Reviewer Brief

- topic-slug: ${topic}
- artifact-type: ${artifact_type}
- max-review-rounds: ${max_rounds}
- current-round: 1
- execution-mode: explicit-reviewer-skill
- codex-bin: ${CODEX_BIN}
- codex-review-model: ${CODEX_REVIEW_MODEL}
- launcher: ${SKILL_DIR}/bin/reviewer-run.sh
EOF

  if [[ -n "${baseline}" ]]; then
    cat >> "${brief_path}" <<EOF
- git-baseline: ${baseline}
EOF
  fi

  cat >> "${brief_path}" <<EOF

## 原始任务

${task}

## 标准化后的任务

${task}
EOF
}

compose_artifact_markdown() {
  local artifact_type="$1"
  local source_path="$2"
  local output_path="$3"

  [[ -f "${source_path}" ]] || fail "artifact 文件不存在: ${source_path}"

  case "${artifact_type}" in
    code|doc)
      if [[ "${source_path}" != "${output_path}" ]]; then
        cp "${source_path}" "${output_path}"
      fi
      ;;
    *)
      fail "未知制品类型: ${artifact_type}"
      ;;
  esac
}

write_final_md() {
  local latest_artifact="$1"
  local final_path="$2"
  local topic="$3"
  local review_json="$4"
  local rounds="$5"
  local artifact_type="$6"

  local summary
  summary="$(json_get "${review_json}" "summary")"

  {
    printf '# 审查通过\n\n'
    printf -- '- topic: %s\n' "${topic}"
    printf -- '- artifact-type: %s\n' "${artifact_type}"
    printf -- '- rounds-run: %s\n' "${rounds}"
    printf -- '- latest-review: %s\n' "$(basename "${review_json}")"
    printf -- '- review-summary: %s\n\n' "${summary}"
    cat "${latest_artifact}"
  } > "${final_path}"
}

read_file_or_none() {
  local path="$1"

  if [[ -z "${path}" || "${path}" == "none" ]]; then
    printf 'none\n'
    return 0
  fi

  [[ -f "${path}" ]] || fail "文件不存在: ${path}"
  cat "${path}"
}

build_codex_review_prompt() {
  local task="$1"
  local artifact_type="$2"
  local topic="$3"
  local round="$4"
  local max_rounds="$5"
  local artifact_path="$6"
  local review_path="$7"
  local response_path="$8"

  python3 - \
    "${PROMPTS_DIR}/codex-review-request.md" \
    "$task" \
    "$artifact_type" \
    "$topic" \
    "$round" \
    "$max_rounds" \
    "$artifact_path" \
    "$review_path" \
    "$response_path" <<'PY'
import pathlib
import sys

(
    template_path,
    task,
    artifact_type,
    topic,
    round_num,
    max_rounds,
    artifact_path,
    review_path,
    response_path,
) = sys.argv[1:10]

def read_or_none(path: str) -> str:
    if not path or path == "none":
        return "none"
    return pathlib.Path(path).read_text(encoding="utf-8")

content = pathlib.Path(template_path).read_text(encoding="utf-8")
replacements = {
    "{{USER_TASK}}": task,
    "{{ARTIFACT_TYPE}}": artifact_type,
    "{{TOPIC_SLUG}}": topic,
    "{{ROUND}}": round_num,
    "{{MAX_ROUNDS}}": max_rounds,
    "{{CURRENT_ARTIFACT}}": read_or_none(artifact_path),
    "{{LATEST_REVIEW}}": read_or_none(review_path),
    "{{LATEST_CLAUDE_RESPONSE}}": read_or_none(response_path),
}
for key, value in replacements.items():
    content = content.replace(key, value)
print(content, end="")
PY
}

build_dispute_prompt() {
  local task="$1"
  local artifact_type="$2"
  local topic="$3"
  local max_rounds="$4"
  local latest_artifact="$5"
  local latest_review="$6"
  local latest_response="$7"

  python3 - \
    "${PROMPTS_DIR}/dispute-report.md" \
    "$task" \
    "$artifact_type" \
    "$topic" \
    "$max_rounds" \
    "$latest_artifact" \
    "$latest_review" \
    "$latest_response" <<'PY'
import pathlib
import sys

(
    template_path,
    task,
    artifact_type,
    topic,
    max_rounds,
    latest_artifact,
    latest_review,
    latest_response,
) = sys.argv[1:9]

def read_or_none(path: str) -> str:
    if not path or path == "none":
        return "none"
    return pathlib.Path(path).read_text(encoding="utf-8")

content = pathlib.Path(template_path).read_text(encoding="utf-8")
replacements = {
    "{{USER_TASK}}": task,
    "{{ARTIFACT_TYPE}}": artifact_type,
    "{{TOPIC_SLUG}}": topic,
    "{{MAX_ROUNDS}}": max_rounds,
    "{{LATEST_ARTIFACT}}": read_or_none(latest_artifact),
    "{{LATEST_REVIEW}}": read_or_none(latest_review),
    "{{LATEST_CLAUDE_RESPONSE}}": read_or_none(latest_response),
}
for key, value in replacements.items():
    content = content.replace(key, value)
print(content, end="")
PY
}

run_codex_review_json() {
  local prompt_builder="$1"
  local output_json="$2"
  local schema_path="$3"
  shift 3

  local args
  args=("${CODEX_BIN}" exec -C "${PWD}" -s read-only --output-schema "${schema_path}" -o "${output_json}" --color never -m "${CODEX_REVIEW_MODEL}" -)

  "${prompt_builder}" "$@" | "${args[@]}"
}

run_codex_markdown() {
  local prompt_builder="$1"
  local output_path="$2"
  shift 2

  local args
  args=("${CODEX_BIN}" exec -C "${PWD}" -s read-only -o "${output_path}" --color never -m "${CODEX_REVIEW_MODEL}" -)

  "${prompt_builder}" "$@" | "${args[@]}"
}

ensure_plans_dir() {
  local plans_dir="$1"
  mkdir -p "${plans_dir}"
}

run_review() {
  local task="$1"
  local artifact_type="$2"
  local topic="$3"
  local round="$4"
  local max_rounds="$5"
  local artifact_path="$6"
  local latest_review="$7"
  local latest_response="$8"
  local plans_dir="$9"

  require_cmd git
  require_cmd python3
  require_cmd "${CODEX_BIN}"
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "当前目录不是 git 仓库"
  [[ -f "${artifact_path}" ]] || fail "artifact 文件不存在: ${artifact_path}"
  [[ "${artifact_type}" == "code" || "${artifact_type}" == "doc" ]] || fail "--artifact-type 只能是 code 或 doc"

  ensure_plans_dir "${plans_dir}"

  local brief_path="${plans_dir}/brief.md"
  local review_path="${plans_dir}/review-r${round}.md"
  local final_path="${plans_dir}/final.md"
  local baseline=""

  if [[ "${artifact_type}" == "code" ]]; then
    append_untracked_to_index
    baseline="$(git rev-parse HEAD)"
  fi

  write_brief "${brief_path}" "${topic}" "${task}" "${artifact_type}" "${max_rounds}" "${baseline}"
  compose_artifact_markdown "${artifact_type}" "${artifact_path}" "${artifact_path}"

  echo "[reviewer] round ${round}: Codex review"
  run_codex_review_json build_codex_review_prompt "${review_path}" "${SCHEMAS_DIR}/codex-review.schema.json" "${task}" "${artifact_type}" "${topic}" "${round}" "${max_rounds}" "${artifact_path}" "${latest_review:-none}" "${latest_response:-none}"

  local status
  local next_action
  status="$(json_get "${review_path}" "status")"
  next_action="$(json_get "${review_path}" "next_action")"

  if [[ "${status}" == "pass" && "${next_action}" == "approve" ]]; then
    write_final_md "${artifact_path}" "${final_path}" "${topic}" "${review_path}" "${round}" "${artifact_type}"
    echo "[reviewer] completed: pass"
  else
    echo "[reviewer] completed: fail"
  fi
}

run_dispute() {
  local task="$1"
  local artifact_type="$2"
  local topic="$3"
  local max_rounds="$4"
  local latest_artifact="$5"
  local latest_review="$6"
  local latest_response="$7"
  local plans_dir="$8"

  require_cmd python3
  require_cmd "${CODEX_BIN}"
  [[ -f "${latest_artifact}" ]] || fail "latest artifact 文件不存在: ${latest_artifact}"
  [[ -f "${latest_review}" ]] || fail "latest review 文件不存在: ${latest_review}"
  [[ "${artifact_type}" == "code" || "${artifact_type}" == "doc" ]] || fail "--artifact-type 只能是 code 或 doc"

  ensure_plans_dir "${plans_dir}"

  echo "[reviewer] reached max rounds, generating dispute report"
  run_codex_markdown build_dispute_prompt "${plans_dir}/dispute-report.md" "${task}" "${artifact_type}" "${topic}" "${max_rounds}" "${latest_artifact}" "${latest_review}" "${latest_response:-none}"
  echo "[reviewer] completed: unresolved"
}

main() {
  local subcommand="${1-}"
  local task=""
  local artifact_type=""
  local topic=""
  local round=""
  local max_rounds="5"
  local artifact_path=""
  local latest_review="none"
  local latest_response="none"
  local latest_artifact=""
  local plans_dir=""
  local workdir=""

  case "${subcommand}" in
    review|dispute)
      shift
      ;;
    *)
      usage
      exit 1
      ;;
  esac

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --task)
        task="${2-}"
        shift 2
        ;;
      --artifact-type)
        artifact_type="${2-}"
        shift 2
        ;;
      --topic)
        topic="${2-}"
        shift 2
        ;;
      --round)
        round="${2-}"
        shift 2
        ;;
      --max-rounds)
        max_rounds="${2-}"
        shift 2
        ;;
      --artifact)
        artifact_path="${2-}"
        shift 2
        ;;
      --latest-review)
        latest_review="${2-}"
        shift 2
        ;;
      --latest-response)
        latest_response="${2-}"
        shift 2
        ;;
      --latest-artifact)
        latest_artifact="${2-}"
        shift 2
        ;;
      --plans-dir)
        plans_dir="${2-}"
        shift 2
        ;;
      --workdir)
        workdir="${2-}"
        shift 2
        ;;
      *)
        fail "未知参数: $1"
        ;;
    esac
  done

  [[ -n "${task}" ]] || fail "必须提供 --task"
  [[ -n "${artifact_type}" ]] || fail "必须提供 --artifact-type"
  [[ -n "${topic}" ]] || fail "必须提供 --topic"
  [[ "${max_rounds}" =~ ^[0-9]+$ ]] || fail "--max-rounds 必须是正整数"
  (( max_rounds >= 1 )) || fail "--max-rounds 必须大于等于 1"

  if [[ -n "${workdir}" ]]; then
    cd "${workdir}"
  fi

  if [[ -z "${plans_dir}" ]]; then
    plans_dir=".claude/plans/${topic}"
  fi

  case "${subcommand}" in
    review)
      [[ -n "${round}" ]] || fail "review 必须提供 --round"
      [[ "${round}" =~ ^[0-9]+$ ]] || fail "--round 必须是正整数"
      (( round >= 1 )) || fail "--round 必须大于等于 1"
      [[ -n "${artifact_path}" ]] || fail "review 必须提供 --artifact"
      run_review "${task}" "${artifact_type}" "${topic}" "${round}" "${max_rounds}" "${artifact_path}" "${latest_review}" "${latest_response}" "${plans_dir}"
      ;;
    dispute)
      [[ -n "${latest_artifact}" ]] || fail "dispute 必须提供 --latest-artifact"
      [[ -n "${latest_review}" && "${latest_review}" != "none" ]] || fail "dispute 必须提供 --latest-review"
      run_dispute "${task}" "${artifact_type}" "${topic}" "${max_rounds}" "${latest_artifact}" "${latest_review}" "${latest_response}" "${plans_dir}"
      ;;
  esac
}

main "$@"
