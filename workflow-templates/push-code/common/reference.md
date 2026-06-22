# Push Code 参考

该工作流依赖安装后的：

- `bin/push-code-run.sh`
- `bin/push_code_webhook.py`
- `config.env`

如果项目启用了可选 monitor，还会额外提供：

- `bin/push-code-monitor.cjs`
- `$CODEX_HOME/push-code-monitor/config.json`
- `$CODEX_HOME/push-code-monitor/monitor.db`

主 agent 负责业务判断；脚本负责直接调用 GitLab REST API。可选 monitor 是系统级总服务，负责跨项目定时巡检和固定模板通知，不参与业务推理。

默认情况下，GitLab helper 会优先尝试使用 `curl` 发请求；如果环境里没有 `curl`，再回退到 Python `urllib`。

## 初始化连通性检查

安装器 `init.sh` 会在写入配置后尽量做两类检查：

- git remote 检查：如果目标目录是 git 仓库且存在配置的 remote，则执行 `git ls-remote <remote>`
- GitLab API 检查：
  - 如果配置了 `PUSH_CODE_GITLAB_BASE_URL` 和 token，则调用 `GET /api/v4/user`
  - 如果同时配置了 `PUSH_CODE_PROJECT_ID`，则继续调用 `GET /api/v4/projects/:id`

如果初始化阶段报 `CERTIFICATE_VERIFY_FAILED`，通常不是 token/header 错误，而是当前 Python 运行时或证书链环境和 GitLab TLS 链不兼容。此时优先考虑：

- 配置 `PUSH_CODE_GITLAB_CA_BUNDLE` 指向可用 CA bundle
- 或先依赖默认的 `curl` 传输路径
- 只有在临时排障时，才把 `PUSH_CODE_GITLAB_SKIP_TLS_VERIFY='true'` 作为兜底

如果条件不足，安装器会明确打印 `跳过`，不会假装检查成功。

## config.env

安装器会写入以下配置：

```sh
PUSH_CODE_GIT_REMOTE='origin'
PUSH_CODE_TARGET_BRANCH='main'
PUSH_CODE_PROJECT_ID=''
PUSH_CODE_MR_TITLE_PREFIX='[Codex]'
PUSH_CODE_POLL_INTERVAL_SECONDS='30'
PUSH_CODE_REVIEW_TIMEOUT_SECONDS='3600'
PUSH_CODE_GITLAB_INITIAL_REVIEW_GRACE_SECONDS='60'

PUSH_CODE_GITLAB_BASE_URL=''
PUSH_CODE_GITLAB_API_TOKEN=''
PUSH_CODE_GITLAB_TOKEN_HEADER_NAME='PRIVATE-TOKEN'
PUSH_CODE_GITLAB_TOKEN_SCHEME=''
PUSH_CODE_GITLAB_CA_BUNDLE=''
PUSH_CODE_GITLAB_SKIP_TLS_VERIFY='false'
PUSH_CODE_GITLAB_EXTRA_HEADER_NAME=''
PUSH_CODE_GITLAB_EXTRA_HEADER_VALUE=''

PUSH_CODE_MR_MONITOR_ENABLED='false'
PUSH_CODE_MR_MONITOR_DB_PATH='/absolute/path/to/.codex/push-code-monitor/monitor.db'
PUSH_CODE_MR_MONITOR_CONFIG_PATH='/absolute/path/to/.codex/push-code-monitor/config.json'
PUSH_CODE_MR_MONITOR_INTERVAL_SECONDS='300'

PUSH_CODE_REVIEW_APPROVED_STATES='approved,pass'
PUSH_CODE_REVIEW_CHANGES_REQUESTED_STATES='changes_requested,fail,blocked'
PUSH_CODE_REVIEW_PENDING_STATES='pending,running,queued,waiting'
```

交互式初始化默认只提示常用字段；像 token header、TLS、额外 header、轮询间隔和 review 状态映射这类高级参数，会直接沿用默认值或旧配置写入 `config.env`。安装器不直接管理的自定义环境变量，也会在重装时保留。

如果启用了全局 MR monitor，`$CODEX_HOME/push-code-monitor/config.json` 里默认会包含：

```json
{
  "version": 1,
  "enabled": true,
  "intervalSeconds": 300,
  "codexBin": "",
  "dashboardHost": "127.0.0.1",
  "dashboardPort": 4635
}
```

`$CODEX_HOME/push-code-monitor/monitor.db` 里会保存所有项目已登记的 MR / thread 映射、项目路径、launcher 路径、最近一次巡检指纹，以及最近巡检历史。

安装器不会自动启动 monitor 后台服务。默认只会写入脚本、配置和数据库；如果需要常驻巡检，需要显式执行 `start`。

### 必填字段

以下字段在真正执行 GitLab API 动作前必须有值：

- `PUSH_CODE_GITLAB_BASE_URL`
- `PUSH_CODE_GITLAB_API_TOKEN`
- `PUSH_CODE_PROJECT_ID`

`PUSH_CODE_GITLAB_TOKEN_HEADER_NAME` 默认是 `PRIVATE-TOKEN`。如果你使用 `Authorization: Bearer <token>` 风格，也可以改成：

```sh
PUSH_CODE_GITLAB_TOKEN_HEADER_NAME='Authorization'
PUSH_CODE_GITLAB_TOKEN_SCHEME='Bearer'
```

如果你的 GitLab 证书链需要自定义 CA bundle，可以额外配置：

```sh
PUSH_CODE_GITLAB_CA_BUNDLE='/path/to/cacert.pem'
```

只有在明确接受风险时，才建议这样临时跳过 TLS 校验：

```sh
PUSH_CODE_GITLAB_SKIP_TLS_VERIFY='true'
```

## launcher 命令

### `preflight`

检查：

- 当前目录是 git 仓库
- worktree clean
- 非 detached HEAD
- 当前分支不是目标主分支

输出 JSON，例如：

```json
{
  "branch": "feature/foo",
  "remote": "origin",
  "target_branch": "main",
  "clean": true
}
```

### `push`

把当前分支推到配置的 remote。

如果当前分支没有 upstream，脚本会自动使用 `--set-upstream`。

如果当前分支刚做过 rebase，需要改用：

```bash
push-code-run.sh push --force-with-lease
```

如果 `git push` 触发了本地 pre-push 检查并失败：

- 不要跳过 hook
- 先阅读 hook 输出并判断失败类别
- 修复问题后重新 `git add`、`git commit`
- 再次执行 `push`

### `rebase-target`

先执行：

- `git fetch <remote> <target-branch>`
- `git rebase <remote>/<target-branch>`

适用场景：

- `wait-review` 返回 `needs_rebase`
- `status` 输出里的 `raw_status` 是 `need_rebase` 或 `conflict`
- `meta.detailed_merge_status` 表示当前源分支必须先 rebase 到目标分支

如果 rebase 冲突：

- 先解决冲突
- 再执行 `git rebase --continue`
- 完成后使用 `push --force-with-lease`

### `create-mr`

调用 GitLab REST API：

- `POST /api/v4/projects/:id/merge_requests`

默认请求体为：

```json
{
  "source_branch": "feature/foo",
  "target_branch": "main",
  "title": "[Codex] feature/foo",
  "description": ""
}
```

返回里会优先使用 `iid` 作为工作流里的 `mr_id`，因为后续 discussions / approvals / merge request 详情接口都使用 MR IID。

如果项目配置里的 `PUSH_CODE_MR_MONITOR_ENABLED=true`，且当前环境存在 `CODEX_THREAD_ID`，launcher 会在 `create-mr` 成功后自动把 `thread_id -> mr_id` 连同 `project_root`、`launcher_path` 一起登记到全局 `monitor.db`。

建议响应摘要示例：

```json
{
  "mr_id": 123,
  "mr_global_id": 456,
  "mr_url": "https://gitlab.example.com/group/project/-/merge_requests/123"
}
```

### `status`

查询：

- `GET /api/v4/projects/:id/merge_requests/:iid`
- `GET /api/v4/projects/:id`
- `GET /api/v4/projects/:id/merge_requests/:iid/status_checks`（如果实例支持且当前 token 有权限）
- `GET /api/v4/projects/:id/merge_requests/:iid/discussions`
- `GET /api/v4/projects/:id/merge_requests/:iid/approvals`（如果实例支持且当前 token 有权限）

状态归一化规则：

- `detailed_merge_status=need_rebase`、存在 merge conflict，或 GitLab 明确返回 rebase blocker：`needs_rebase`
- 如果项目 `merge_method` 是 `ff` / `rebase_merge`，且 `diverged_commits_count > 0`，即使 `detailed_merge_status` 还没刷新成 `need_rebase`，也按 `needs_rebase` 处理
- `detailed_merge_status=ci_must_pass` / `status_checks_must_pass` 且 `head_pipeline.status=failed`：`changes_requested`
- 只要 `head_pipeline.status=failed|canceled|canceling|skipped`，即使 `detailed_merge_status=mergeable`，也按 `changes_requested` 处理，避免把红色 pipeline 误判为通过
- `status_checks` 里只要存在 `failed` 项：`changes_requested`
- `status_checks` 里只要还存在 `pending` 项：`pending`
- 只要 `head_pipeline.status` 仍处于 `running` / `pending` / `preparing` 等未完成状态，即使 `detailed_merge_status=mergeable` 也仍然是 `pending`
- 存在未解决的可解析 discussion：`changes_requested`
- 没有未解决 discussion，且 approval 规则已满足：`approved`
- 没有未解决 discussion，且已经出现过 review discussion：`approved`
- 没有任何 discussion，且 MR 创建时间仍在 `PUSH_CODE_GITLAB_INITIAL_REVIEW_GRACE_SECONDS` 宽限内：`pending`
- 没有任何 discussion，且超过宽限：`approved`

### `threads`

查询：

- `GET /api/v4/projects/:id/merge_requests/:iid/discussions`
- `GET /api/v4/projects/:id/merge_requests/:iid/notes`

输出会被归一化成：

```json
{
  "threads": [
    {
      "id": "abc",
      "individual_note": false,
      "resolved": false,
      "resolvable": true,
      "notes": [
        {
          "id": 1,
          "body": "...",
          "author": "review-bot"
        }
      ]
    }
  ],
  "notes": [
    {
      "id": 101,
      "body": "审核不通过...",
      "author": "review-bot"
    }
  ],
  "summary": {
    "total": 1,
    "unresolved": 1,
    "notes": 1
  }
}
```

### `wait-review`

轮询 `status`，并在遇到变更请求、通过或超时时退出：

- 退出码 `0`：通过
- 退出码 `10`：review 要求修改
- 退出码 `11`：当前 MR 必须先 rebase 到目标分支
- 退出码 `124`：超时

输出 JSON 会附带当前 discussions 和 MR 摘要，便于主 agent 决策。

`status` / `wait-review` 现在无论当前是 `pending`、`changes_requested` 还是 `approved`，都会附带完整 `notes`，并在 `meta` 中补充：

- `notes_total`
- `non_system_notes_total`
- `latest_non_system_note_id`
- `latest_non_system_note_created_at`
- `latest_non_system_note_author`

同时还会附带 `workflow_guidance`，至少包含：

- `review_complete`
- `workflow_complete`
- `can_announce_completion`
- `recommended_next_action`
- `user_facing_state`

推荐主 agent 直接把 `workflow_guidance.can_announce_completion` 当成硬约束：

- `true`：当前轮允许按“MR 已达到可提交状态”口径收口
- `false`：当前轮绝不能把 push-code 流程说成已完成
- `false` 且没有新的用户决策 blocker：当前轮也不允许发送 final answer；只能继续在同一 turn 内轮询并发送 commentary

另外，`workflow_guidance.recommended_next_action` 里以 `_in_current_session` 结尾的值也应被视为硬约束，表示当前会话必须自己继续轮询并处理。例如：

- `keep_waiting_for_ci_in_current_session`
- `keep_waiting_in_current_session_and_treat_note_as_pending_finding`
- `keep_waiting_for_review_signal_in_current_session`

这些值出现时，说明最新 head pipeline / review 信号仍属于当前会话必须继续跟进的范围。

对业务 agent 来说，这里还有一个更严格的收口规则：

- `pending` / `ci_still_running` / `head_pipeline:running` 本身不是 final 收口条件
- “MR 已创建、review note 看起来通过、现在只等 CI” 也不是 final 收口条件
- 只有 MR 达到可提交状态，或出现明确 blocker 需要用户立刻介入时，才允许发送 final answer

### `comment`

调用：

- `POST /api/v4/projects/:id/merge_requests/:iid/discussions/:thread_id/notes`

用于回复 discussion。

### `note`

调用：

- `POST /api/v4/projects/:id/merge_requests/:iid/notes`

用于追加普通 MR note。

### `resolve-thread`

调用：

- `PUT /api/v4/projects/:id/merge_requests/:iid/discussions/:thread_id`

请求体会把 `resolved=true`。

### `reopen-thread`

调用：

- `PUT /api/v4/projects/:id/merge_requests/:iid/discussions/:thread_id`

请求体会把 `resolved=false`。

## 可选 monitor 命令

全局 Node.js monitor 只做定时巡检和固定模板通知，可选命令包括：

```bash
push-code-monitor.cjs init
push-code-monitor.cjs start --interval-seconds 300
push-code-monitor.cjs stop
push-code-monitor.cjs status
push-code-monitor.cjs registration-upsert --db-path "$CODEX_HOME/push-code-monitor/monitor.db" --mr-id 123 --thread-id thread-1 --branch feature/foo --project-root /path/to/project --launcher-path /path/to/project/.codex/skills/push-code/bin/push-code-run.sh
push-code-monitor.cjs scan
push-code-monitor.cjs run-loop --interval-seconds 300
push-code-monitor.cjs thread-running --thread-id thread-1
push-code-monitor.cjs notify-thread --thread-id thread-1 --message-file /tmp/message.txt
push-code-monitor.cjs config-set --config-path "$CODEX_HOME/push-code-monitor/config.json" --codex-bin "$(command -v codex)"
push-code-monitor.cjs dashboard-data --config-path "$CODEX_HOME/push-code-monitor/config.json" --db-path "$CODEX_HOME/push-code-monitor/monitor.db"
```

其中：

- `start`：后台拉起一个 monitor 服务；它会一边执行 `scan` 循环，一边在本地启动 dashboard，并把 PID / 日志路径 / dashboard 地址写到 `$CODEX_HOME/push-code-monitor/service.json`
- `stop`：停止由 `start` 拉起的后台巡检服务
- `status`：检查后台巡检服务当前是否还在运行
- `scan`：逐个读取全局 `monitor.db` 里登记过的 MR，并按每条记录里的 `project_root` / `launcher_path` 回到对应项目调用 `push-code-run.sh status --mr-id`
- `run-loop`：按固定间隔持续执行 `scan`
- `thread-running`：检查某个会话当前是否仍在运行，避免重复插入并发消息
- `notify-thread`：通过 `codex exec resume --skip-git-repo-check` 用固定模板通知指定会话
- `dashboard-data`：输出 dashboard 背后的聚合 JSON，包含 monitor 运行状态、当前活跃会话 / MR 映射，以及最近巡检记录

## 终态约束

- 只要 `workflow_guidance.can_announce_completion=false`，就不能把本次 push-code 流程表述成完成
- 即使 `status=pending`，只要最新非 system note 已经出现 reviewer finding，也不能说成“现在只是等 CI”
- 不提供 merge 命令；最终提交或合并必须由人工完成
