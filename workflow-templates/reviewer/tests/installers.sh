#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT_INSTALLER="${ROOT_DIR}/init.sh"
CODEX_INSTALLER="${ROOT_DIR}/codex/init.sh"
TMP_ROOT="${ROOT_DIR}/.tmp-tests"
TMP_DIR="${TMP_ROOT}/installers"
FAKE_CODEX="${TMP_DIR}/fake-codex.sh"
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

assert_not_exists() {
  local path="$1"
  [[ ! -e "${path}" ]] || fail "expected path to be removed: ${path}"
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

assert_not_contains() {
  local path="$1"
  local unexpected="$2"
  if grep -Fq "${unexpected}" "${path}"; then
    fail "did not expect '${unexpected}' in ${path}"
  fi
}

assert_json_value() {
  local path="$1"
  local expression="$2"
  local expected="$3"

  python3 - "${path}" "${expression}" "${expected}" <<'PY'
import json
import sys

path, expression, expected = sys.argv[1:4]
with open(path, "r", encoding="utf-8") as fh:
    value = json.load(fh)
for part in expression.split("."):
    value = value[int(part)] if part.isdigit() else value[part]
actual = json.dumps(value, ensure_ascii=False, sort_keys=True)
if actual != expected:
    raise SystemExit(f"expected {expression}={expected}, got {actual}")
PY
}

assert_backlog_count() {
  local path="$1"
  local expected="$2"

  python3 - "${path}" "${expected}" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    count = len(json.load(fh)["items"])
if count != int(sys.argv[2]):
    raise SystemExit(f"expected backlog count {sys.argv[2]}, got {count}")
PY
}

assert_backlog_has() {
  local path="$1"
  local field="$2"
  local expected="$3"

  python3 - "${path}" "${field}" "${expected}" <<'PY'
import json
import sys

path, field, expected = sys.argv[1:4]
with open(path, "r", encoding="utf-8") as fh:
    items = json.load(fh)["items"]
if not any(str(item.get(field)) == expected for item in items):
    raise SystemExit(f"expected backlog item with {field}={expected}")
PY
}

init_git_target() {
  local target="$1"

  mkdir -p "${target}"
  (
    cd "${target}"
    git init -q
    git config user.email reviewer-test@example.com
    git config user.name reviewer-test
    printf 'base\n' > src.txt
    git add .
    git commit -qm baseline
    printf 'changed\n' > src.txt
  )
}

write_fake_codex() {
  cat > "${FAKE_CODEX}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

output=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o)
      output="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

prompt="$(cat)"
printf '%s' "${prompt}" > "${FAKE_CODEX_PROMPT_LOG}"

python3 - "${FAKE_CODEX_STATUS}" "${output}" <<'PY'
import json
import pathlib
import sys

status, output = sys.argv[1:3]

def repro(actual="changed", expected="base"):
    return {
        "preconditions": "current workspace contains changed src.txt",
        "steps_or_command": "test $(cat src.txt) = base",
        "expected": expected,
        "actual": actual,
        "observed": True,
    }

def issue(issue_id, *, severity="important", origin="task_related", confidence="high",
          evidence_kind="runtime_reproduction", evidence="current command observed changed",
          description="current behavior violates the task", fix="restore required behavior",
          location="src.txt:1", blocking=True, reason=None, current=True,
          reproduction=None, reopens=None):
    return {
        "id": issue_id,
        "severity": severity,
        "origin": origin,
        "confidence": confidence,
        "evidence_kind": evidence_kind,
        "evidence": evidence,
        "current_state_reachable": current,
        "reproduction": repro() if reproduction is None and blocking else reproduction,
        "description": description,
        "fix_suggestion": fix,
        "location": location,
        "delivery_blocking": blocking,
        "non_blocking_reason": reason,
        "reopens_consensus_id": reopens,
        "related_backlog_id": None,
    }

minor = issue(
    "minor-repeat", severity="minor", evidence_kind="best_practice",
    evidence="src.txt:1 uses a generic message", description="the optional message could be clearer",
    fix="improve it later", blocking=False, reason="does not affect task correctness",
    current=True, reproduction=None,
)
blocker = issue(
    "issue-1", origin="change_introduced",
    evidence="running the current command returns changed instead of base",
    description="the current change returns the wrong required value",
)

result = {"status": "pass", "summary": "no delivery blockers", "issues": [], "new_consensus_exclusions": [], "next_action": "approve"}
if status == "minor":
    result.update(summary="minor only", issues=[minor])
elif status == "preexisting":
    result.update(summary="pre-existing only", issues=[issue(
        "legacy-1", origin="pre_existing", evidence_kind="best_practice",
        evidence="behavior existed at baseline", description="legacy behavior should be improved",
        blocking=False, reason="pre-existing and not required", current=True, reproduction=None,
    )])
elif status == "low_confidence":
    result.update(summary="low confidence only", issues=[issue(
        "guess-1", confidence="low", evidence_kind="insufficient_evidence",
        evidence="no current failure was observed", description="a theoretical edge case may exist",
        blocking=False, reason="not reproduced", current=False, reproduction=None,
    )])
elif status == "nonblocking_mix":
    result.update(summary="only non-blocking findings", issues=[
        issue("legacy-1", origin="pre_existing", evidence_kind="best_practice", evidence="existed at baseline", description="legacy behavior should be improved", blocking=False, reason="pre-existing", current=True, reproduction=None),
        issue("scope-1", origin="out_of_scope", evidence_kind="best_practice", evidence="another module is outside the task", description="unrelated module could be refactored", location="other.txt:1", blocking=False, reason="out of scope", current=False, reproduction=None),
        issue("guess-1", confidence="low", evidence_kind="future_risk", evidence="requires a future caller", description="a future caller may expose an edge case", location="src.txt:2", blocking=False, reason="future-only risk", current=False, reproduction=None),
        issue("medium-1", confidence="medium", evidence_kind="static_suspicion", evidence="inspection only; no failure observed", description="possible edge case lacks runtime evidence", location="src.txt:3", blocking=False, reason="not reproduced", current=True, reproduction=None),
    ])
elif status == "blocker":
    result.update(status="fail", summary="delivery blocker", issues=[blocker], next_action="revise")
elif status == "blocker_with_minor":
    result.update(status="fail", summary="one blocker and one minor", issues=[blocker, minor], next_action="revise")
elif status == "consensus_pass":
    result["summary"] = "agreed exclusion"
    result["new_consensus_exclusions"] = [{
        "consensus_id": "consensus-old", "source_issue_id": "issue-1",
        "disposition": "not_a_problem", "description": "legacy behavior is intentional",
        "location": "src.txt:1", "rationale": "the task requires this behavior",
        "applies_while": "the task contract remains unchanged",
        "reopen_if": "the task contract or implementation premise changes",
    }]
elif status == "reopen":
    reopened = issue("issue-reopen", evidence="current command contradicts the revised task contract", description="the active behavior directly violates the revised contract", reopens="consensus-old")
    result.update(status="fail", summary="consensus premise changed", issues=[reopened], next_action="revise")
elif status == "invalid_low_blocking":
    invalid = issue("invalid-1", confidence="low")
    result.update(status="fail", summary="invalid low blocker", issues=[invalid], next_action="revise")
elif status == "invalid_medium_important_blocking":
    invalid = issue("invalid-medium", confidence="medium")
    result.update(status="fail", summary="invalid medium blocker", issues=[invalid], next_action="revise")
elif status == "invalid_future_blocking":
    invalid = issue("future-1", evidence_kind="future_risk", evidence="requires future configuration", description="future configuration may expose a bug", current=False, reproduction=None)
    result.update(status="fail", summary="invalid future blocker", issues=[invalid], next_action="revise")
elif status == "invalid_uncertain_blocking":
    invalid = issue("uncertain-1", description="this may cause incorrect behavior")
    result.update(status="fail", summary="invalid uncertain wording", issues=[invalid], next_action="revise")
elif status != "pass":
    raise SystemExit(f"unknown fake status: {status}")

pathlib.Path(output).write_text(json.dumps(result, ensure_ascii=False) + "\n", encoding="utf-8")
PY
EOF
  chmod +x "${FAKE_CODEX}"
}

run_codex_install_test() {
  local target="${TMP_DIR}/codex-target"
  mkdir -p "${target}"
  bash "${CODEX_INSTALLER}" "${target}"

  assert_file "${target}/.codex/skills/reviewer/SKILL.md"
  assert_file "${target}/.codex/skills/reviewer/reference.md"
  assert_file "${target}/.codex/skills/reviewer/prompts/codex-blind-review-request.md"
  assert_file "${target}/.codex/skills/reviewer/schemas/codex-review.schema.json"
  assert_file "${target}/.codex/skills/reviewer/schemas/consensus-exclusions.schema.json"
  assert_file "${target}/.codex/skills/reviewer/schemas/review-backlog.schema.json"
  assert_file "${target}/.codex/skills/reviewer/schemas/workflow-state.schema.json"
  assert_executable "${target}/.codex/skills/reviewer/bin/reviewer-run.sh"
  assert_contains "${target}/AGENTS.md" 'spawn_agent(..., fork_turns="none")'
  assert_contains "${target}/AGENTS.md" 'review-backlog.json'
  assert_contains "${target}/AGENTS.md" '一次独立盲审'
  assert_contains "${target}/.codex/skills/reviewer/SKILL.md" '20 (goal-mode)'
  assert_contains "${target}/.codex/skills/reviewer/SKILL.md" '只有主 agent 可以修改代码或文档'
  assert_contains "${target}/.codex/skills/reviewer/SKILL.md" 'stable-convergence'
  assert_contains "${target}/.codex/skills/reviewer/prompts/codex-blind-review-request.md" 'delivery_blocking'
  assert_contains "${target}/.codex/skills/reviewer/prompts/codex-blind-review-request.md" 'runtime_reproduction'
  assert_contains "${target}/.codex/skills/reviewer/prompts/codex-review-response.md" 'verification-result'
  assert_contains "${target}/.codex/skills/reviewer/schemas/codex-review.schema.json" 'current_state_reachable'
  assert_contains "${target}/.codex/skills/reviewer/reference.md" 'review-backlog.schema.json'
  assert_contains "${target}/.codex/skills/reviewer/bin/reviewer-run.sh" 'SESSION_ROLLOVER_ROUNDS=10'
  assert_not_contains "${target}/.codex/skills/reviewer/SKILL.md" '.cursor/'
}

run_root_install_tests() {
  local target

  target="${TMP_DIR}/root-default-target"
  mkdir -p "${target}"
  bash "${ROOT_INSTALLER}" "${target}"
  assert_file "${target}/.codex/skills/reviewer/SKILL.md"

  target="${TMP_DIR}/root-codex-target"
  mkdir -p "${target}"
  bash "${ROOT_INSTALLER}" --codex "${target}"
  assert_file "${target}/.codex/skills/reviewer/SKILL.md"
}

run_convergence_flow_test() {
  local target="${TMP_DIR}/convergence-target"
  local plans_dir=".codex/plans/convergence-test"
  local prompt_log="${TMP_DIR}/convergence-prompt.log"
  local baseline

  init_git_target "${target}"
  bash "${CODEX_INSTALLER}" "${target}"
  (
    cd "${target}"
    baseline="$(git rev-parse HEAD)"
    mkdir -p "${plans_dir}"
    printf 'preserve\n' > "${plans_dir}/keep-me.txt"

    printf '# artifact 1\n' > "${plans_dir}/artifact-r1.md"
    REVIEWER_CODEX_BIN="${FAKE_CODEX}" FAKE_CODEX_PROMPT_LOG="${prompt_log}" FAKE_CODEX_STATUS=blocker_with_minor \
      .codex/skills/reviewer/bin/reviewer-run.sh blind \
        --task "修复登录校验" --artifact-type code --topic convergence-test \
        --audit-round 1 --max-blind-audits '20 (goal-mode)' \
        --baseline "${baseline}" --artifact "${plans_dir}/artifact-r1.md"

    assert_json_value "${plans_dir}/workflow-state.json" consecutive_qualifying_blind_audits '0'
    assert_json_value "${plans_dir}/workflow-state.json" status '"running"'
    assert_backlog_count "${plans_dir}/review-backlog.json" 1
    assert_backlog_has "${plans_dir}/review-backlog.json" severity minor
    assert_not_contains "${prompt_log}" '独立盲审轮次：`1`'
    assert_not_contains "${prompt_log}" '最大独立盲审次数'
    printf '# response\n\n1. issue-1\n   - decision: accepted\n   - verification-result: not_reproduced\n   - verification-evidence: rerun did not show the reported failure\n   - action: fixed anyway\n   - rationale: invalid acceptance\n   - open-question: none\n' > "${plans_dir}/response-invalid.md"
    printf '# invalid revision\n' > "${plans_dir}/revision-invalid.md"
    if REVIEWER_CODEX_BIN="${FAKE_CODEX}" FAKE_CODEX_PROMPT_LOG="${prompt_log}" FAKE_CODEX_STATUS=pass \
      .codex/skills/reviewer/bin/reviewer-run.sh followup \
        --task "修复登录校验" --artifact-type code --topic convergence-test \
        --audit-round 1 --inner-iteration 99 --max-blind-audits '20 (goal-mode)' \
        --baseline "${baseline}" --artifact "${plans_dir}/revision-invalid.md" \
        --latest-review "${plans_dir}/blind-review-r1.md" \
        --latest-response "${plans_dir}/response-invalid.md"; then
      fail "accepted blocker must be independently reproduced"
    fi
    printf '# response\n\n1. issue-1\n   - decision: accepted\n   - verification-result: reproduced\n   - verification-evidence: test command returned changed instead of base\n   - action: fixed\n   - rationale: valid\n   - open-question: none\n' > "${plans_dir}/response-r1-i1.md"
    printf '# revision 1\n' > "${plans_dir}/revision-r1-i1.md"
    REVIEWER_CODEX_BIN="${FAKE_CODEX}" FAKE_CODEX_PROMPT_LOG="${prompt_log}" FAKE_CODEX_STATUS=pass \
      .codex/skills/reviewer/bin/reviewer-run.sh followup \
        --task "修复登录校验" --artifact-type code --topic convergence-test \
        --audit-round 1 --inner-iteration 1 --max-blind-audits '20 (goal-mode)' \
        --baseline "${baseline}" --artifact "${plans_dir}/revision-r1-i1.md" \
        --latest-review "${plans_dir}/blind-review-r1.md" \
        --latest-response "${plans_dir}/response-r1-i1.md"

    assert_json_value "${plans_dir}/workflow-state.json" next_blind_audit '2'
    assert_json_value "${plans_dir}/workflow-state.json" consecutive_qualifying_blind_audits '0'
    assert_backlog_count "${plans_dir}/review-backlog.json" 1
    assert_not_exists "${plans_dir}/blind-review-r1.md"

    printf '# artifact 2\n' > "${plans_dir}/artifact-r2.md"
    REVIEWER_CODEX_BIN="${FAKE_CODEX}" FAKE_CODEX_PROMPT_LOG="${prompt_log}" FAKE_CODEX_STATUS=nonblocking_mix \
      .codex/skills/reviewer/bin/reviewer-run.sh blind \
        --task "修复登录校验" --artifact-type code --topic convergence-test \
        --audit-round 2 --max-blind-audits '20 (goal-mode)' \
        --baseline "${baseline}" --artifact "${plans_dir}/artifact-r2.md"

    assert_file "${plans_dir}/final.md"
    assert_contains "${plans_dir}/final.md" 'stop-reason: stable-convergence'
    assert_json_value "${plans_dir}/workflow-state.json" consecutive_qualifying_blind_audits '1'
    assert_json_value "${plans_dir}/workflow-state.json" status '"complete"'
    assert_backlog_count "${plans_dir}/review-backlog.json" 5
    assert_backlog_has "${plans_dir}/review-backlog.json" confidence low
    assert_backlog_has "${plans_dir}/review-backlog.json" confidence medium
    assert_backlog_has "${plans_dir}/review-backlog.json" origin out_of_scope
    assert_file "${plans_dir}/keep-me.txt"
  )
}

run_invalid_classification_test() {
  local target="${TMP_DIR}/invalid-target"
  local plans_dir=".codex/plans/invalid-test"
  local prompt_log="${TMP_DIR}/invalid-prompt.log"
  local baseline

  init_git_target "${target}"
  bash "${CODEX_INSTALLER}" "${target}"
  (
    cd "${target}"
    baseline="$(git rev-parse HEAD)"
    mkdir -p "${plans_dir}"
    printf '# artifact\n' > "${plans_dir}/artifact-r1.md"
    if REVIEWER_CODEX_BIN="${FAKE_CODEX}" FAKE_CODEX_PROMPT_LOG="${prompt_log}" FAKE_CODEX_STATUS=invalid_low_blocking \
      .codex/skills/reviewer/bin/reviewer-run.sh blind \
        --task "分类校验" --artifact-type code --topic invalid-test \
        --audit-round 1 --max-blind-audits 2 --baseline "${baseline}" \
        --artifact "${plans_dir}/artifact-r1.md"; then
      fail "low-confidence important issue must not block delivery"
    fi
    assert_file "${plans_dir}/blind-review-r1.md"
    assert_not_exists "${plans_dir}/final.md"
    if REVIEWER_CODEX_BIN="${FAKE_CODEX}" FAKE_CODEX_PROMPT_LOG="${prompt_log}" FAKE_CODEX_STATUS=invalid_medium_important_blocking \
      .codex/skills/reviewer/bin/reviewer-run.sh blind \
        --task "分类校验" --artifact-type code --topic invalid-test \
        --audit-round 1 --max-blind-audits 2 --baseline "${baseline}" \
        --artifact "${plans_dir}/artifact-r1.md"; then
      fail "medium-confidence important issue must not block delivery"
    fi
    if REVIEWER_CODEX_BIN="${FAKE_CODEX}" FAKE_CODEX_PROMPT_LOG="${prompt_log}" FAKE_CODEX_STATUS=invalid_future_blocking \
      .codex/skills/reviewer/bin/reviewer-run.sh blind \
        --task "分类校验" --artifact-type code --topic invalid-test \
        --audit-round 1 --max-blind-audits 2 --baseline "${baseline}" \
        --artifact "${plans_dir}/artifact-r1.md"; then
      fail "future-only risk must not block delivery"
    fi
    if REVIEWER_CODEX_BIN="${FAKE_CODEX}" FAKE_CODEX_PROMPT_LOG="${prompt_log}" FAKE_CODEX_STATUS=invalid_uncertain_blocking \
      .codex/skills/reviewer/bin/reviewer-run.sh blind \
        --task "分类校验" --artifact-type code --topic invalid-test \
        --audit-round 1 --max-blind-audits 2 --baseline "${baseline}" \
        --artifact "${plans_dir}/artifact-r1.md"; then
      fail "uncertain wording must not be accepted as a blocker"
    fi
  )
}

run_state_migration_test() {
  local target="${TMP_DIR}/migration-target"
  local plans_dir=".codex/plans/migration-test"
  local budget_dir=".codex/plans/legacy-budget-test"
  local prompt_log="${TMP_DIR}/migration-prompt.log"
  local baseline

  init_git_target "${target}"
  bash "${CODEX_INSTALLER}" "${target}"
  (
    cd "${target}"
    baseline="$(git rev-parse HEAD)"
    mkdir -p "${plans_dir}"
    printf '%s\n' "{\"version\":2,\"topic_slug\":\"migration-test\",\"artifact_type\":\"code\",\"git_baseline\":\"${baseline}\",\"max_blind_audits\":\"unlimited (goal-mode)\",\"rollover_every\":10,\"required_qualifying_blind_audits\":2,\"consecutive_qualifying_blind_audits\":0,\"completed_blind_audits\":0,\"next_blind_audit\":1,\"session_segment\":1,\"completed_in_current_session\":0,\"status\":\"running\"}" > "${plans_dir}/workflow-state.json"
    printf '%s\n' '{"items":[{"backlog_id":"backlog-0123456789ab","severity":"minor","origin":"task_related","confidence":"low","description":"legacy backlog item","evidence":"old free-form evidence","location":"src.txt:1","reason_non_blocking":"not proven"}]}' > "${plans_dir}/review-backlog.json"
    printf '# artifact\n' > "${plans_dir}/artifact-r1.md"
    REVIEWER_CODEX_BIN="${FAKE_CODEX}" FAKE_CODEX_PROMPT_LOG="${prompt_log}" FAKE_CODEX_STATUS=pass \
      .codex/skills/reviewer/bin/reviewer-run.sh blind \
        --task "状态迁移" --artifact-type code --topic migration-test \
        --audit-round 1 --max-blind-audits '20 (goal-mode)' --baseline "${baseline}" \
        --artifact "${plans_dir}/artifact-r1.md"
    assert_json_value "${plans_dir}/workflow-state.json" version '3'
    assert_json_value "${plans_dir}/workflow-state.json" max_blind_audits '"20 (goal-mode)"'
    assert_json_value "${plans_dir}/workflow-state.json" required_qualifying_blind_audits '1'
    assert_json_value "${plans_dir}/workflow-state.json" consecutive_qualifying_blind_audits '1'
    assert_json_value "${plans_dir}/workflow-state.json" status '"complete"'
    assert_json_value "${plans_dir}/review-backlog.json" items.0.evidence_kind '"insufficient_evidence"'
    assert_json_value "${plans_dir}/review-backlog.json" items.0.current_state_reachable 'false'
    assert_json_value "${plans_dir}/review-backlog.json" items.0.reproduction 'null'

    mkdir -p "${budget_dir}"
    printf '%s\n' "{\"version\":2,\"topic_slug\":\"legacy-budget-test\",\"artifact_type\":\"code\",\"git_baseline\":\"${baseline}\",\"max_blind_audits\":\"unlimited (goal-mode)\",\"rollover_every\":10,\"required_qualifying_blind_audits\":2,\"consecutive_qualifying_blind_audits\":0,\"completed_blind_audits\":20,\"next_blind_audit\":21,\"session_segment\":2,\"completed_in_current_session\":10,\"status\":\"handoff_required\"}" > "${budget_dir}/workflow-state.json"
    printf '# handoff\n' > "${budget_dir}/session-handoff.md"
    .codex/skills/reviewer/bin/reviewer-run.sh resume --topic legacy-budget-test
    assert_json_value "${budget_dir}/workflow-state.json" version '3'
    assert_json_value "${budget_dir}/workflow-state.json" max_blind_audits '"20 (goal-mode)"'
    assert_json_value "${budget_dir}/workflow-state.json" status '"complete"'
    assert_contains "${budget_dir}/final.md" 'stop-reason: review-budget-completed'
    assert_not_exists "${budget_dir}/session-handoff.md"
  )
}

run_consensus_flow_test() {
  local target="${TMP_DIR}/consensus-target"
  local plans_dir=".codex/plans/consensus-test"
  local prompt_log="${TMP_DIR}/consensus-prompt.log"
  local baseline

  init_git_target "${target}"
  bash "${CODEX_INSTALLER}" "${target}"
  (
    cd "${target}"
    baseline="$(git rev-parse HEAD)"
    mkdir -p "${plans_dir}"
    printf '# artifact 1\n' > "${plans_dir}/artifact-r1.md"
    REVIEWER_CODEX_BIN="${FAKE_CODEX}" FAKE_CODEX_PROMPT_LOG="${prompt_log}" FAKE_CODEX_STATUS=blocker \
      .codex/skills/reviewer/bin/reviewer-run.sh blind \
        --task "共识测试" --artifact-type code --topic consensus-test \
        --audit-round 1 --max-blind-audits 2 --baseline "${baseline}" \
        --artifact "${plans_dir}/artifact-r1.md"

    printf '# response\n\n1. issue-1\n   - decision: rejected\n   - verification-result: not_reproduced\n   - verification-evidence: rerun showed the task-required behavior\n   - action: none\n   - rationale: required behavior\n   - open-question: none\n' > "${plans_dir}/response-r1-i1.md"
    printf '# revision\n' > "${plans_dir}/revision-r1-i1.md"
    REVIEWER_CODEX_BIN="${FAKE_CODEX}" FAKE_CODEX_PROMPT_LOG="${prompt_log}" FAKE_CODEX_STATUS=consensus_pass \
      .codex/skills/reviewer/bin/reviewer-run.sh followup \
        --task "共识测试" --artifact-type code --topic consensus-test \
        --audit-round 1 --inner-iteration 1 --max-blind-audits 2 --baseline "${baseline}" \
        --artifact "${plans_dir}/revision-r1-i1.md" \
        --latest-review "${plans_dir}/blind-review-r1.md" \
        --latest-response "${plans_dir}/response-r1-i1.md"
    assert_contains "${plans_dir}/consensus-exclusions.json" 'consensus-old'

    printf '# artifact 2\n' > "${plans_dir}/artifact-r2.md"
    REVIEWER_CODEX_BIN="${FAKE_CODEX}" FAKE_CODEX_PROMPT_LOG="${prompt_log}" FAKE_CODEX_STATUS=reopen \
      .codex/skills/reviewer/bin/reviewer-run.sh blind \
        --task "共识测试" --artifact-type code --topic consensus-test \
        --audit-round 2 --max-blind-audits 2 --baseline "${baseline}" \
        --artifact "${plans_dir}/artifact-r2.md"
    assert_contains "${prompt_log}" 'consensus-old'
    assert_not_contains "${plans_dir}/consensus-exclusions.json" 'consensus-old'
  )
}

run_session_rollover_test() {
  local target="${TMP_DIR}/rollover-target"
  local plans_dir=".codex/plans/rollover-test"
  local prompt_log="${TMP_DIR}/rollover-prompt.log"
  local baseline
  local audit_round

  init_git_target "${target}"
  bash "${CODEX_INSTALLER}" "${target}"
  (
    cd "${target}"
    baseline="$(git rev-parse HEAD)"
    mkdir -p "${plans_dir}"

    for ((audit_round = 1; audit_round <= 10; audit_round++)); do
      printf '# artifact %s\n' "${audit_round}" > "${plans_dir}/artifact-r${audit_round}.md"
      REVIEWER_CODEX_BIN="${FAKE_CODEX}" FAKE_CODEX_PROMPT_LOG="${prompt_log}" FAKE_CODEX_STATUS=blocker \
        .codex/skills/reviewer/bin/reviewer-run.sh blind \
          --task "长周期审查" --artifact-type code --topic rollover-test \
          --audit-round "${audit_round}" --max-blind-audits '20 (goal-mode)' --baseline "${baseline}" \
          --artifact "${plans_dir}/artifact-r${audit_round}.md"
      printf '# response\n\n1. issue-1\n   - decision: accepted\n   - verification-result: reproduced\n   - verification-evidence: test command returned changed instead of base\n   - action: fixed\n   - rationale: valid\n   - open-question: none\n' > "${plans_dir}/response-r${audit_round}-i1.md"
      printf '# revision\n' > "${plans_dir}/revision-r${audit_round}-i1.md"
      REVIEWER_CODEX_BIN="${FAKE_CODEX}" FAKE_CODEX_PROMPT_LOG="${prompt_log}" FAKE_CODEX_STATUS=pass \
        .codex/skills/reviewer/bin/reviewer-run.sh followup \
          --task "长周期审查" --artifact-type code --topic rollover-test \
          --audit-round "${audit_round}" --inner-iteration 1 --max-blind-audits '20 (goal-mode)' --baseline "${baseline}" \
          --artifact "${plans_dir}/revision-r${audit_round}-i1.md" \
          --latest-review "${plans_dir}/blind-review-r${audit_round}.md" \
          --latest-response "${plans_dir}/response-r${audit_round}-i1.md"
    done

    assert_json_value "${plans_dir}/workflow-state.json" completed_blind_audits '10'
    assert_json_value "${plans_dir}/workflow-state.json" status '"handoff_required"'
    assert_file "${plans_dir}/session-handoff.md"
    assert_contains "${plans_dir}/session-handoff.md" 'review-backlog.json'

    .codex/skills/reviewer/bin/reviewer-run.sh resume --topic rollover-test
    assert_json_value "${plans_dir}/workflow-state.json" session_segment '2'
    assert_json_value "${plans_dir}/workflow-state.json" completed_in_current_session '0'
    assert_not_exists "${plans_dir}/session-handoff.md"

    for ((audit_round = 11; audit_round <= 20; audit_round++)); do
      printf '# artifact %s\n' "${audit_round}" > "${plans_dir}/artifact-r${audit_round}.md"
      REVIEWER_CODEX_BIN="${FAKE_CODEX}" FAKE_CODEX_PROMPT_LOG="${prompt_log}" FAKE_CODEX_STATUS=blocker \
        .codex/skills/reviewer/bin/reviewer-run.sh blind \
          --task "长周期审查" --artifact-type code --topic rollover-test \
          --audit-round "${audit_round}" --max-blind-audits '20 (goal-mode)' --baseline "${baseline}" \
          --artifact "${plans_dir}/artifact-r${audit_round}.md"
      printf '# response\n\n1. issue-1\n   - decision: accepted\n   - verification-result: reproduced\n   - verification-evidence: test command returned changed instead of base\n   - action: fixed\n   - rationale: valid\n   - open-question: none\n' > "${plans_dir}/response-r${audit_round}-i1.md"
      printf '# revision\n' > "${plans_dir}/revision-r${audit_round}-i1.md"
      REVIEWER_CODEX_BIN="${FAKE_CODEX}" FAKE_CODEX_PROMPT_LOG="${prompt_log}" FAKE_CODEX_STATUS=pass \
        .codex/skills/reviewer/bin/reviewer-run.sh followup \
          --task "长周期审查" --artifact-type code --topic rollover-test \
          --audit-round "${audit_round}" --inner-iteration 1 --max-blind-audits '20 (goal-mode)' --baseline "${baseline}" \
          --artifact "${plans_dir}/revision-r${audit_round}-i1.md" \
          --latest-review "${plans_dir}/blind-review-r${audit_round}.md" \
          --latest-response "${plans_dir}/response-r${audit_round}-i1.md"
    done

    assert_json_value "${plans_dir}/workflow-state.json" completed_blind_audits '20'
    assert_json_value "${plans_dir}/workflow-state.json" status '"complete"'
    assert_contains "${plans_dir}/final.md" 'stop-reason: review-budget-completed'
  )
}

write_fake_codex
run_codex_install_test
run_root_install_tests
run_convergence_flow_test
run_invalid_classification_test
run_state_migration_test
run_consensus_flow_test
run_session_rollover_test

echo "PASS: reviewer installers, convergence, backlog, consensus, and rollover"
