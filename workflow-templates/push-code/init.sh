#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_INSTALLER="${SCRIPT_DIR}/codex/init.sh"
CLAUDE_INSTALLER="${SCRIPT_DIR}/claude/init.sh"

usage() {
  cat >&2 <<'EOF'
用法:
  init.sh [--codex|--claude] [options] <target-project>

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
EOF
}

main() {
  local installer="${CODEX_INSTALLER}"
  case "${1-}" in
    --codex)
      shift
      ;;
    --claude)
      installer="${CLAUDE_INSTALLER}"
      shift
      ;;
  esac
  exec bash "${installer}" "$@"
}

main "$@"
