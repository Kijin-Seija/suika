#!/usr/bin/env bash

set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SELF_DIR}/.." && pwd)"
PROMPTS_DIR="${SKILL_DIR}/prompts"
SCHEMAS_DIR="${SKILL_DIR}/schemas"

CLAUDE_BIN="${WRITER_CLAUDE_BIN:-${IMPLEMENTATION_LOOP_CLAUDE_BIN:-claude}}"
CODEX_BIN="${WRITER_CODEX_BIN:-${IMPLEMENTATION_LOOP_CODEX_BIN:-codex}}"
CLAUDE_WRITER_MODEL="${WRITER_CLAUDE_WRITER_MODEL:-${WRITER_CLAUDE_MODEL:-${IMPLEMENTATION_LOOP_CLAUDE_MODEL:-}}}"
CODEX_WRITER_MODEL="${WRITER_CODEX_WRITER_MODEL:-${WRITER_CODEX_MODEL:-${IMPLEMENTATION_LOOP_CODEX_MODEL:-}}}"
CODEX_REVIEW_MODEL="${WRITER_CODEX_REVIEW_MODEL:-${WRITER_CODEX_MODEL:-${IMPLEMENTATION_LOOP_CODEX_MODEL:-}}}"
CLAUDE_PERMISSION_MODE="${WRITER_CLAUDE_PERMISSION_MODE:-${IMPLEMENTATION_LOOP_CLAUDE_PERMISSION_MODE:-bypassPermissions}}"
CLAUDE_MAX_ATTEMPTS="${WRITER_CLAUDE_MAX_ATTEMPTS:-3}"
CLAUDE_RETRY_BACKOFF_SECONDS="${WRITER_CLAUDE_RETRY_BACKOFF_SECONDS:-2}"
CLAUDE_COMPACT_RETRY="${WRITER_CLAUDE_COMPACT_RETRY:-1}"

usage() {
  cat >&2 <<'EOF'
用法:
  writer-run.sh run --task <task> [--artifact-type <code|openspec-artifacts>] [--writer <claude|codex>] [--topic <slug>] [--max-rounds <n>] [--workdir <dir>]
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

normalize_artifact_type() {
  local raw="${1:-code}"

  case "${raw}" in
    ""|code)
      printf 'code\n'
      ;;
    openspec|openspec-artifacts)
      printf 'openspec-artifacts\n'
      ;;
    *)
      return 1
      ;;
  esac
}

slugify() {
  local raw="$1"
  local slug
  slug="$(printf '%s' "${raw}" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g' | cut -c1-48)"
  if [[ -z "${slug}" ]]; then
    slug="writer-$(date +%Y%m%d-%H%M%S)"
  fi
  printf '%s\n' "${slug}"
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
  local response_json="$2"
  python3 - "$review_json" "$response_json" <<'PY'
import json
import sys

review_path, response_path = sys.argv[1:3]

with open(review_path, "r", encoding="utf-8") as fh:
    review = json.load(fh)
with open(response_path, "r", encoding="utf-8") as fh:
    response = json.load(fh)

review_ids = [issue["id"] for issue in review.get("issues", [])]
response_ids = [item["issue_id"] for item in response.get("responses", [])]

missing = [issue_id for issue_id in review_ids if issue_id not in response_ids]
if missing:
    print(", ".join(missing))
    sys.exit(1)
PY
}

append_untracked_to_index() {
  local untracked=()
  local path=""

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
  local max_rounds="$4"
  local baseline="$5"
  local writer_kind="$6"
  local artifact_type="$7"

  cat > "${brief_path}" <<EOF
# Writer Brief

- topic-slug: ${topic}
- artifact-type: ${artifact_type}
- max-review-rounds: ${max_rounds}
- current-round: 1
- execution-mode: writer
- writer: ${writer_kind}
- git-baseline: ${baseline}
- claude-bin: ${CLAUDE_BIN}
- codex-bin: ${CODEX_BIN}

## 原始任务

${task}

## 标准化后的任务

${task}
EOF
}

write_revision_handoff() {
  local handoff_path="$1"
  local task="$2"
  local topic="$3"
  local round="$4"
  local max_rounds="$5"
  local writer_kind="$6"
  local artifact_type="$7"
  local latest_review="$8"
  local latest_writer_json="$9"
  local latest_artifact="${10}"

  python3 - "$handoff_path" "$task" "$topic" "$round" "$max_rounds" "$writer_kind" "$artifact_type" "$latest_review" "$latest_writer_json" "$latest_artifact" <<'PY'
import json
import os
import sys

handoff_path, task, topic, round_no, max_rounds, writer_kind, artifact_type, review_path, writer_json_path, artifact_path = sys.argv[1:11]

def load_json(path):
    if not path or path == "none" or not os.path.exists(path):
        return None
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)

review = load_json(review_path) or {}
writer = load_json(writer_json_path) or {}

lines = [
    "# Writer Revision Handoff",
    "",
    f"- topic slug: {topic}",
    f"- artifact type: {artifact_type}",
    f"- writer: {writer_kind}",
    f"- current round: {round_no}",
    f"- max rounds: {max_rounds}",
    f"- latest review: {review_path}",
    f"- latest writer json: {writer_json_path}",
    f"- latest artifact: {artifact_path}",
    "",
    "## Task",
    "",
    task,
    "",
]

summary = (writer.get("summary") or "").strip()
verification = (writer.get("verification") or "").strip()
changed_files = writer.get("changed_files") or []
responses = writer.get("responses") or []
remaining_questions = writer.get("remaining_questions") or writer.get("questions") or []

if summary:
    lines.extend([
        "## Last Writer Summary",
        "",
        summary,
        "",
    ])

if verification:
    lines.extend([
        "## Last Verification",
        "",
        verification,
        "",
    ])

lines.append("## Recently Changed Files")
lines.append("")
if changed_files:
    for item in changed_files:
      path = item.get("path", "").strip() or "unknown"
      item_summary = item.get("summary", "").strip() or "no summary"
      lines.append(f"- {path}: {item_summary}")
else:
    lines.append("- none")
lines.append("")

lines.append("## Issues To Address")
lines.append("")
issues = review.get("issues") or []
if issues:
    for issue in issues:
        issue_id = issue.get("id", "").strip() or "unknown"
        severity = issue.get("severity", "").strip() or "unknown"
        location = issue.get("location", "").strip() or "unknown"
        description = issue.get("description", "").strip() or "no description"
        suggestion = issue.get("fix_suggestion", "").strip() or "no suggestion"
        lines.extend([
            f"- [{issue_id}] severity={severity} location={location}",
            f"  description: {description}",
            f"  fix suggestion: {suggestion}",
        ])
else:
    lines.append("- none")
lines.append("")

if responses:
    lines.append("## Previous Issue Decisions")
    lines.append("")
    for item in responses:
        issue_id = item.get("issue_id", "").strip() or "unknown"
        decision = item.get("decision", "").strip() or "unknown"
        action = item.get("action", "").strip() or "no action"
        rationale = item.get("rationale", "").strip() or "no rationale"
        lines.extend([
            f"- [{issue_id}] decision={decision}",
            f"  action: {action}",
            f"  rationale: {rationale}",
        ])
    lines.append("")

lines.append("## Remaining Questions")
lines.append("")
if remaining_questions:
    for item in remaining_questions:
        lines.append(f"- {item}")
else:
    lines.append("- none")
lines.extend([
    "",
    "## Context Control",
    "",
    "- Start from this handoff and the latest review.",
    "- Do not open artifact markdown unless this handoff is insufficient, because artifact files embed full diffs.",
    "- Do not scan unrelated historical files under .codex/plans/.",
    "- Prefer targeted reads on the files mentioned above instead of broad repository sweeps.",
    "",
])

with open(handoff_path, "w", encoding="utf-8") as fh:
    fh.write("\n".join(lines))
PY
}

compose_artifact_markdown() {
  local json_path="$1"
  local output_path="$2"
  local diff_path="$3"
  local artifact_type="$4"

  python3 - "$json_path" "$output_path" "$diff_path" "$artifact_type" <<'PY'
import json
import sys

json_path, output_path, diff_path, artifact_type = sys.argv[1:5]

with open(json_path, "r", encoding="utf-8") as fh:
    data = json.load(fh)
with open(diff_path, "r", encoding="utf-8") as fh:
    diff_text = fh.read()

summary = data.get("summary", "").strip()
verification = data.get("verification", "").strip()
changed_files = data.get("changed_files", [])
title = {
    "code": "代码变更摘要",
    "openspec-artifacts": "OpenSpec 制品变更摘要",
}.get(artifact_type, "工作区变更摘要")

lines = [
    f"# {title}",
    "",
    "## 变更概述",
    summary or "none",
    "",
    "## 验证",
    verification or "not run",
    "",
    "## 变更文件",
]

if changed_files:
    for item in changed_files:
        lines.append(f"- {item['path']}: {item['summary']}")
else:
    lines.append("- none")

lines.extend([
    "",
    "## Diff",
    "```diff",
    diff_text.rstrip("\n"),
    "```",
    "",
])

with open(output_path, "w", encoding="utf-8") as fh:
    fh.write("\n".join(lines))
PY
}

write_final_md() {
  local latest_artifact="$1"
  local final_path="$2"
  local topic="$3"
  local review_json="$4"
  local rounds="$5"
  local writer_kind="$6"
  local artifact_type="$7"

  local summary
  summary="$(json_get "${review_json}" "summary")"

  {
    printf '# 审查通过\n\n'
    printf -- '- topic: %s\n' "${topic}"
    printf -- '- artifact-type: %s\n' "${artifact_type}"
    printf -- '- writer: %s\n' "${writer_kind}"
    printf -- '- rounds-run: %s\n' "${rounds}"
    printf -- '- latest-review: %s\n' "$(basename "${review_json}")"
    printf -- '- review-summary: %s\n\n' "${summary}"
    cat "${latest_artifact}"
  } > "${final_path}"
}

build_writer_draft_prompt() {
  local task="$1"
  local topic="$2"
  local round="$3"
  local max_rounds="$4"
  local brief_path="$5"
  local writer_kind="$6"
  local artifact_type="$7"
  local context_mode="${8:-normal}"

  cat "${PROMPTS_DIR}/claude-code-draft.md"
  cat <<EOF

## 运行信息

- 用户任务: ${task}
- 制品类型: ${artifact_type}
- writer: ${writer_kind}
- topic slug: ${topic}
- 当前轮次: ${round}
- 最大轮次: ${max_rounds}
- brief 路径: ${brief_path}

## 上下文控制

- 优先用 'rg' 和按文件精读来定位，不要先通读整个仓库
- 除调用方明确给出的文件外，不要主动读取 '.codex/plans/' 下的历史产物
- 非必要不要读取 lockfile、构建产物、coverage、vendor、dist 等大文件
- 优先交付与任务直接相关的最小可接受改动，不要顺手做大范围重构
EOF

  if [[ "${artifact_type}" == "openspec-artifacts" ]]; then
    cat <<EOF

## OpenSpec 任务约束

- 目标是产出或修订仓库中的 OpenSpec proposal/design/spec/tasks 制品，而不是只给分析意见
- 如果仓库已有 'openspec' 相关命令、模板或目录约定，优先沿用
- 保持 proposal/design/spec/tasks 之间的信息一致性，不要只更新其中一部分
EOF
  fi

  if [[ "${context_mode}" == "compact" ]]; then
    cat <<EOF

## 紧凑模式

这次调用正在做上下文降载重试。

- 除 '${brief_path}' 外，不要读取 '.codex/plans/' 下的其他文件
- 每次只展开少量直接相关文件；如果需要补充上下文，逐步增加，不要一次读很多
- 如果仓库很大，优先先完成最小闭环交付，再把残余问题写入 'questions'
EOF
  fi

  cat <<EOF

请直接在当前工作区内完成任务要求的制品。
EOF
}

build_writer_revision_prompt() {
  local task="$1"
  local topic="$2"
  local round="$3"
  local max_rounds="$4"
  local handoff_path="$5"
  local latest_artifact="$6"
  local latest_review="$7"
  local latest_response="$8"
  local writer_kind="$9"
  local artifact_type="${10}"
  local context_mode="${11:-normal}"

  cat "${PROMPTS_DIR}/claude-code-revision.md"
  cat <<EOF

## 运行信息

- 用户任务: ${task}
- 制品类型: ${artifact_type}
- writer: ${writer_kind}
- topic slug: ${topic}
- 当前轮次: ${round}
- 最大轮次: ${max_rounds}
- 最新 handoff: ${handoff_path}
- 最新 artifact: ${latest_artifact}
- 最新 review: ${latest_review}
- 上一轮 response: ${latest_response}

## 上下文控制

- 先阅读 '${handoff_path}'，再阅读 '${latest_review}'
- 非必要不要打开 '${latest_artifact}'，因为 artifact 内含完整 diff 快照，体积更大
- 非必要不要扫描 '.codex/plans/' 下其他历史文件
- 优先从 issue 指向的文件和上一轮已改动文件开始定位
EOF

  if [[ "${artifact_type}" == "openspec-artifacts" ]]; then
    cat <<EOF

## OpenSpec 修订约束

- 优先修正 proposal/design/spec/tasks 之间的不一致
- 不要为了回应 review 而擅自把 OpenSpec 任务改写成代码实现任务
- 如果仓库已有 'openspec' 相关命令、模板或目录约定，继续沿用
EOF
  fi

  if [[ "${context_mode}" == "compact" ]]; then
    cat <<EOF

## 紧凑模式

这次调用正在做上下文降载重试。

- 以 '${handoff_path}' 和 '${latest_review}' 为主，不要再读取其他 plans 文件，除非它们是解决某个具体 issue 的唯一途径
- 每次只补读一小组必要文件，不要做大范围目录扫描
- 先解决 'blocking' 与 'important' 问题；避免额外重构
EOF
  fi

  cat <<EOF

请先阅读最新 handoff 和最新 review，再修改当前工作区文件，并逐条回应所有 issue。
EOF
}

build_codex_review_prompt() {
  local task="$1"
  local topic="$2"
  local round="$3"
  local max_rounds="$4"
  local baseline="$5"
  local artifact_path="$6"
  local review_path="$7"
  local response_path="$8"
  local writer_kind="$9"
  local artifact_type="${10}"

  cat "${PROMPTS_DIR}/codex-review.md"
  cat <<EOF

## 审查上下文

- 用户任务: ${task}
- 制品类型: ${artifact_type}
- writer: ${writer_kind}
- topic slug: ${topic}
- 当前轮次: ${round}
- 最大轮次: ${max_rounds}
- git baseline: ${baseline}
- 当前 artifact: ${artifact_path}
- 上一轮 review: ${review_path}
- writer 最新 response: ${response_path}

优先审查当前未提交工作区改动；如有必要，再读取上述文件。
EOF
}

build_dispute_prompt() {
  local task="$1"
  local topic="$2"
  local max_rounds="$3"
  local latest_artifact="$4"
  local latest_review="$5"
  local latest_response="$6"
  local writer_kind="$7"
  local artifact_type="$8"

  cat "${PROMPTS_DIR}/dispute-report.md"
  cat <<EOF

## 工作流上下文

- 用户任务: ${task}
- 制品类型: ${artifact_type}
- writer: ${writer_kind}
- topic slug: ${topic}
- 最大轮次: ${max_rounds}
- 最新 artifact: ${latest_artifact}
- 最新 review: ${latest_review}
- 最新 response: ${latest_response}

请生成最终争议报告。
EOF
}

run_claude_json() {
  local prompt_builder="$1"
  local output_json="$2"
  local schema_path="$3"
  shift 3

  local args
  local output_prefix="${output_json%.*}"
  local attempt=1
  local context_mode="normal"
  local sleep_seconds="${CLAUDE_RETRY_BACKOFF_SECONDS}"
  local max_attempts="${CLAUDE_MAX_ATTEMPTS}"

  while (( attempt <= max_attempts )); do
    local prompt_path="${output_prefix}.claude-prompt-a${attempt}.md"
    local stderr_path="${output_prefix}.claude-stderr-a${attempt}.log"
    local output_tmp="${output_json}.tmp"
    local exit_code=0
    local failure_kind="fatal"

    "${prompt_builder}" "$@" "${context_mode}" > "${prompt_path}"

    args=("${CLAUDE_BIN}" -p --output-format json --json-schema "${schema_path}" --permission-mode "${CLAUDE_PERMISSION_MODE}" --add-dir "${PWD}" --no-session-persistence)
    if [[ -n "${CLAUDE_WRITER_MODEL}" ]]; then
      args+=(--model "${CLAUDE_WRITER_MODEL}")
    fi

    if "${args[@]}" < "${prompt_path}" > "${output_tmp}" 2> "${stderr_path}"; then
      mv "${output_tmp}" "${output_json}"
      return 0
    fi

    exit_code=$?
    rm -f "${output_tmp}"
    failure_kind="$(python3 - "${stderr_path}" <<'PY'
import pathlib
import sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8", errors="ignore").lower()

context_markers = [
    "context window",
    "prompt is too long",
    "request too large",
    "input is too long",
    "too many tokens",
    "context length",
    "input length",
    "invalid_request_error",
]
transient_markers = [
    "rate limit",
    "overloaded",
    "timeout",
    "timed out",
    "connection reset",
    "temporarily unavailable",
    "internal server error",
    "server error",
    "bad gateway",
]

if any(marker in text for marker in context_markers):
    print("context")
elif "400" in text and ("context" in text or "too long" in text or "too large" in text):
    print("context")
elif any(marker in text for marker in transient_markers):
    print("transient")
elif any(code in text for code in ["429", "500", "502", "503", "504", "529"]):
    print("transient")
else:
    print("fatal")
PY
)"

    if (( attempt >= max_attempts )); then
      echo "ERROR: Claude 调用失败，已达到最大重试次数 (${max_attempts})，最后一次退出码: ${exit_code}" >&2
      tail -n 80 "${stderr_path}" >&2 || true
      return "${exit_code}"
    fi

    if [[ "${failure_kind}" == "context" && "${CLAUDE_COMPACT_RETRY}" == "1" ]]; then
      echo "[writer] Claude attempt ${attempt} hit context overflow; retrying in compact mode" >&2
      context_mode="compact"
    elif [[ "${failure_kind}" == "transient" ]]; then
      echo "[writer] Claude attempt ${attempt} hit transient failure; retrying" >&2
    else
      echo "ERROR: Claude 调用失败，未命中可重试错误类型，退出码: ${exit_code}" >&2
      tail -n 80 "${stderr_path}" >&2 || true
      return "${exit_code}"
    fi

    sleep "${sleep_seconds}"
    attempt=$((attempt + 1))
  done
}

run_codex_writer_json() {
  local prompt_builder="$1"
  local output_json="$2"
  local schema_path="$3"
  shift 3

  local args
  args=("${CODEX_BIN}" exec -C "${PWD}" --full-auto --output-schema "${schema_path}" -o "${output_json}" --color never -)
  if [[ -n "${CODEX_WRITER_MODEL}" ]]; then
    args=( "${CODEX_BIN}" exec -C "${PWD}" --full-auto --output-schema "${schema_path}" -o "${output_json}" --color never -m "${CODEX_WRITER_MODEL}" - )
  fi

  "${prompt_builder}" "$@" | "${args[@]}"
}

run_codex_review_json() {
  local prompt_builder="$1"
  local output_json="$2"
  local schema_path="$3"
  shift 3

  local args
  args=("${CODEX_BIN}" exec -C "${PWD}" -s read-only --output-schema "${schema_path}" -o "${output_json}" --color never -)
  if [[ -n "${CODEX_REVIEW_MODEL}" ]]; then
    args=( "${CODEX_BIN}" exec -C "${PWD}" -s read-only --output-schema "${schema_path}" -o "${output_json}" --color never -m "${CODEX_REVIEW_MODEL}" - )
  fi

  "${prompt_builder}" "$@" | "${args[@]}"
}

run_codex_markdown() {
  local prompt_builder="$1"
  local output_path="$2"
  shift 2

  local args
  args=("${CODEX_BIN}" exec -C "${PWD}" -s read-only -o "${output_path}" --color never -)
  if [[ -n "${CODEX_REVIEW_MODEL}" ]]; then
    args=( "${CODEX_BIN}" exec -C "${PWD}" -s read-only -o "${output_path}" --color never -m "${CODEX_REVIEW_MODEL}" - )
  fi

  "${prompt_builder}" "$@" | "${args[@]}"
}

run_writer_json() {
  local writer_kind="$1"
  shift

  case "${writer_kind}" in
    claude)
      run_claude_json "$@"
      ;;
    codex)
      run_codex_writer_json "$@"
      ;;
    *)
      fail "未知 writer: ${writer_kind}"
      ;;
  esac
}

run_loop() {
  local task="$1"
  local topic="$2"
  local max_rounds="$3"
  local writer_kind="$4"
  local artifact_type="$5"

  require_cmd git
  require_cmd python3
  require_cmd "${CODEX_BIN}"
  if [[ "${writer_kind}" == "claude" ]]; then
    require_cmd "${CLAUDE_BIN}"
  fi

  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "当前目录不是 git 仓库"
  if [[ -n "$(git status --porcelain)" ]]; then
    fail "启动 writer 前，工作区必须是 clean working tree"
  fi

  local plans_dir=".codex/plans/${topic}"
  local brief_path="${plans_dir}/brief.md"
  local baseline
  baseline="$(git rev-parse HEAD)"

  mkdir -p "${plans_dir}"
  write_brief "${brief_path}" "${topic}" "${task}" "${max_rounds}" "${baseline}" "${writer_kind}" "${artifact_type}"

  local round=1
  local artifact_path="${plans_dir}/draft-r1.md"
  local review_path=""
  local response_path="none"
  local handoff_path=""
  local latest_artifact=""
  local latest_review=""
  local latest_response="none"
  local latest_writer_json="${plans_dir}/writer-draft-r1.json"

  echo "[writer] round ${round}: ${writer_kind} draft"
  run_writer_json "${writer_kind}" build_writer_draft_prompt "${latest_writer_json}" "${SCHEMAS_DIR}/claude-draft.schema.json" "${task}" "${topic}" "${round}" "${max_rounds}" "${brief_path}" "${writer_kind}" "${artifact_type}"

  append_untracked_to_index
  git diff --patch --unified=3 > "${plans_dir}/diff-r1.patch"
  compose_artifact_markdown "${latest_writer_json}" "${artifact_path}" "${plans_dir}/diff-r1.patch" "${artifact_type}"

  while true; do
    review_path="${plans_dir}/review-r${round}.json"
    echo "[writer] round ${round}: Codex review"
    run_codex_review_json build_codex_review_prompt "${review_path}" "${SCHEMAS_DIR}/codex-review.schema.json" "${task}" "${topic}" "${round}" "${max_rounds}" "${baseline}" "${artifact_path}" "${latest_review:-none}" "${latest_response:-none}" "${writer_kind}" "${artifact_type}"

    local status
    local next_action
    status="$(json_get "${review_path}" "status")"
    next_action="$(json_get "${review_path}" "next_action")"
    latest_artifact="${artifact_path}"
    latest_review="${review_path}"

    if [[ "${status}" == "pass" && "${next_action}" == "approve" ]]; then
      write_final_md "${latest_artifact}" "${plans_dir}/final.md" "${topic}" "${review_path}" "${round}" "${writer_kind}" "${artifact_type}"
      echo "[writer] completed: pass"
      return 0
    fi

    if (( round >= max_rounds )); then
      echo "[writer] reached max rounds, generating dispute report"
      run_codex_markdown build_dispute_prompt "${plans_dir}/dispute-report.md" "${task}" "${topic}" "${max_rounds}" "${latest_artifact}" "${latest_review}" "${latest_response}" "${writer_kind}" "${artifact_type}"
      echo "[writer] completed: unresolved"
      return 1
    fi

    round=$((round + 1))
    response_path="${plans_dir}/response-r${round}.json"
    artifact_path="${plans_dir}/revision-r${round}.md"
    handoff_path="${plans_dir}/writer-handoff-r${round}.md"

    write_revision_handoff "${handoff_path}" "${task}" "${topic}" "${round}" "${max_rounds}" "${writer_kind}" "${artifact_type}" "${latest_review}" "${latest_writer_json}" "${latest_artifact}"

    echo "[writer] round ${round}: ${writer_kind} revision"
    run_writer_json "${writer_kind}" build_writer_revision_prompt "${response_path}" "${SCHEMAS_DIR}/claude-response.schema.json" "${task}" "${topic}" "${round}" "${max_rounds}" "${handoff_path}" "${latest_artifact}" "${latest_review}" "${latest_response:-none}" "${writer_kind}" "${artifact_type}"
    local missing_issues=""
    if ! missing_issues="$(validate_response_coverage "${latest_review}" "${response_path}" 2>/dev/null)"; then
      fail "writer response 未覆盖上一轮全部 issue: ${missing_issues}"
    fi

    append_untracked_to_index
    git diff --patch --unified=3 > "${plans_dir}/diff-r${round}.patch"
    compose_artifact_markdown "${response_path}" "${artifact_path}" "${plans_dir}/diff-r${round}.patch" "${artifact_type}"

    latest_response="${response_path}"
    latest_writer_json="${response_path}"
  done
}

main() {
  local subcommand="${1-}"
  local task=""
  local artifact_type="code"
  local writer_kind="claude"
  local topic=""
  local max_rounds="5"
  local workdir=""

  case "${subcommand}" in
    run)
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
      --writer)
        writer_kind="${2-}"
        shift 2
        ;;
      --topic)
        topic="${2-}"
        shift 2
        ;;
      --max-rounds)
        max_rounds="${2-}"
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
  artifact_type="$(normalize_artifact_type "${artifact_type}")" || fail "--artifact-type 只能是 code、openspec 或 openspec-artifacts"
  [[ "${writer_kind}" == "claude" || "${writer_kind}" == "codex" ]] || fail "--writer 只能是 claude 或 codex"
  [[ "${max_rounds}" =~ ^[0-9]+$ ]] || fail "--max-rounds 必须是正整数"
  (( max_rounds >= 1 )) || fail "--max-rounds 必须大于等于 1"
  [[ "${CLAUDE_MAX_ATTEMPTS}" =~ ^[0-9]+$ ]] || fail "WRITER_CLAUDE_MAX_ATTEMPTS 必须是正整数"
  (( CLAUDE_MAX_ATTEMPTS >= 1 )) || fail "WRITER_CLAUDE_MAX_ATTEMPTS 必须大于等于 1"
  [[ "${CLAUDE_RETRY_BACKOFF_SECONDS}" =~ ^[0-9]+$ ]] || fail "WRITER_CLAUDE_RETRY_BACKOFF_SECONDS 必须是非负整数"
  [[ "${CLAUDE_COMPACT_RETRY}" == "0" || "${CLAUDE_COMPACT_RETRY}" == "1" ]] || fail "WRITER_CLAUDE_COMPACT_RETRY 只能是 0 或 1"

  if [[ -n "${workdir}" ]]; then
    cd "${workdir}"
  fi

  if [[ -z "${topic}" ]]; then
    topic="$(slugify "${task}")"
  fi

  run_loop "${task}" "${topic}" "${max_rounds}" "${writer_kind}" "${artifact_type}"
}

main "$@"
