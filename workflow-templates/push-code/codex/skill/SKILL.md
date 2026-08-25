---
name: push-code
description: 当用户显式要求使用 "push-code skill"、"push code workflow"、"推当前分支并创建 MR"、"跟进 GitLab code review 到可提交状态" 时使用。适用于需要把当前分支推送到 GitLab、直接调用 GitLab REST API 创建合到主分支的 MR、轮询 online review discussions / 普通 MR notes / mergeability 状态，并根据 review 评论继续修复或发起异议回复的场景。
---

# Push Code 工作流

## 触发条件

只在用户明确要求时启用，例如：

- `使用 push-code skill`
- `请走 push code workflow`
- `把当前分支推上去并创建 MR`
- `跟进这次 GitLab code review 到可提交状态`

如果用户没有显式要求，不要默认启用。

## 目标

该 skill 用于驱动一个可重复的 push / MR / review 闭环：

1. 先验证当前工作区能否安全 push
2. 把当前分支 push 到远端
3. 直接调用 GitLab REST API 创建一个当前分支合到目标主分支的 MR，并拿到 `mr_id`
4. 轮询 review 状态、discussions、普通 MR notes 与 mergeability blockers
5. 如果 GitLab 判定源分支必须先 rebase 到目标分支，则先处理 rebase
6. 对 review 结果做两类处理：
   - 有异议：通过 GitLab discussions 回复评论
   - 无异议：修复代码后重新 `git add`、`git commit`、`git push`
7. 循环以上步骤，直到 MR 达到可提交状态，或出现明确 blocker 需要暂停

## 必要前提

开始前必须检查：

- 当前目录是 git 仓库
- 当前工作区没有 staged / unstaged / untracked 变更
- 当前不处于 detached HEAD
- `.codex/skills/push-code/config.env` 已存在且 GitLab 配置完整
- `git`、`python3` 可用

如果当前分支不是 clean working tree，必须立即终止流程，不要替用户自动提交，也不要带着未提交改动去 push。

## 必须使用的资源

进入该 workflow 后，优先复用安装后的 launcher 和 helper，而不是在对话里手写 `curl`：

- `.codex/skills/push-code/bin/push-code-run.sh`
- `.codex/skills/push-code/bin/push_code_webhook.py`
- `.codex/skills/push-code/config.env`
- `.codex/skills/push-code/reference.md`

## 标准执行顺序

### 1. Preflight

先执行：

```bash
.codex/skills/push-code/bin/push-code-run.sh preflight
```

如果失败：

- 直接向用户说明 blocker
- 不要继续创建 MR
- 不要替用户生成兜底 commit

### 2. Push 当前分支

预检通过后执行：

```bash
.codex/skills/push-code/bin/push-code-run.sh push
```

要求：

- push 的对象必须是当前分支
- 优先复用 `config.env` 中配置的 remote，默认 `origin`
- 如果当前分支还没有 upstream，可以由 launcher 自动加 `--set-upstream`
- 如果本地 pre-push 检查脚本报错，必须先阅读报错并分析根因；修复完成后重新 `git add`、`git commit`，再重新执行 `push`

### 3. 创建 MR

push 成功后执行：

```bash
.codex/skills/push-code/bin/push-code-run.sh create-mr
```

要求：

- 目标分支默认取 `config.env` 中的 `PUSH_CODE_TARGET_BRANCH`
- 成功后记录返回的 `mr_id`
- 如果返回里同时有 `mr_url` 或 `web_url`，对用户同步出来
- 在同一次流程里，不要为同一个源分支反复创建重复 MR；已有 `mr_id` 后，应复用该 MR 继续等待 review

### 4. 等待在线 review

拿到 `mr_id` 后执行：

```bash
.codex/skills/push-code/bin/push-code-run.sh wait-review --mr-id <mr_id>
```

处理规则：

- 如果返回通过态，仍要先检查本轮 `review_notes_fingerprint` 和所有 note `revision_key`；只有不存在尚未阅读的新 revision 时，才能说明 MR 已达到可提交状态
- 如果返回 `needs_rebase`，先处理本地 rebase，再继续等待 review
- 如果返回变更请求态，继续拉取 discussions
- `pending`、`ci_still_running`、`head_pipeline:running`、`external_status_checks_pending:*`、`awaiting_first_review_signal` 都不是完成态；只要还处于这些状态，就不能把 push-code 流程表述成“已完成 / 已通过 / 可以收口”
- 在提交 MR 之后，当前会话必须自己继续定时轮询并跟进，直到 MR 达到可提交状态、超时或遇到明确 blocker
- 即使返回 `pending`，也要读取这次返回里的全部非 system `notes`，与上一轮已处理 note revision 集合按 `id` / `updated_at` / `body_sha256` 做差；新增 note 或已有 note 内容被编辑都必须视为待处理 finding，而不是直接口径收敛成“仅等待 CI”
- 如果超时或 GitLab API 返回无法识别的状态，向用户说明并暂停自动循环
- `status` / `wait-review` 的 JSON 里如果带有 `workflow_guidance.can_announce_completion=false`，就绝不能向用户发送“本次 push-code 已完成”的 final answer
- `workflow_guidance.can_announce_completion=true` 只是结构化检查通过的必要信号，不会替代 note revision 检查；存在尚未阅读的新建或被编辑 note 时仍禁止收口
- 当 `workflow_guidance.recommended_next_action` 是 `keep_waiting_for_ci_in_current_session`、`keep_waiting_in_current_session_and_treat_note_as_pending_finding` 或 `keep_waiting_for_review_signal_in_current_session` 时，按字面执行：继续由当前会话轮询
- 只要当前状态仍是 `pending` / `ci_still_running` / `head_pipeline:running`，且没有出现“需要用户现在介入”的新 blocker，就必须继续停留在当前 turn 内轮询；可以发 commentary 进度，但不能发送 final answer 结束本轮
- 即使你想表达“目前只是等 CI”，也只能用 commentary 同步阶段性状态，不能用 final answer 把线程收口

### 5. 处理 need rebase 分支

如果 `wait-review` 返回 `needs_rebase`，或者 `status` 输出中的 `raw_status` / `meta.detailed_merge_status` 表示当前源分支必须先 rebase 到目标分支，则应先执行：

```bash
.codex/skills/push-code/bin/push-code-run.sh rebase-target
.codex/skills/push-code/bin/push-code-run.sh push --force-with-lease
```

处理规则：

- launcher 会先 `git fetch <remote> <target-branch>`，再把当前分支 rebase 到 `<remote>/<target-branch>`
- 如果 rebase 出现冲突，先解决冲突并完成 `git rebase --continue`
- rebase 完成后必须使用 `push --force-with-lease` 更新远端分支，不能使用裸 `--force`
- 如果 rebase 后的 push 仍然命中本地 pre-push 检查失败，依然要先修复检查问题，再继续 MR / review 闭环

### 6. 读取 discussions / 普通 MR notes 并分类处理

当 review 未通过时，执行：

```bash
.codex/skills/push-code/bin/push-code-run.sh threads --mr-id <mr_id>
```

读取 discussions 和普通 MR notes 后，对每条问题做判断：

- `accepted`：意见成立，应修改代码
- `questioned`：意见可能不完整或存在误判，应先回复 discussion
- `rejected`：意见明显不成立，应在 discussion 中说明依据

如果需要回复 discussion，优先把回复内容写到临时文件，再执行：

```bash
.codex/skills/push-code/bin/push-code-run.sh comment \
  --mr-id <mr_id> \
  --thread-id <thread_id> \
  --body-file <reply-file>
```

不要在没有阅读 discussion 内容的情况下直接回复“已修复”或“已知悉”。

如果某条 discussion 的意见你已经接受、代码也已经修复并 push 完成，还需要显式把对应 thread 标记为 resolved：

```bash
.codex/skills/push-code/bin/push-code-run.sh resolve-thread \
  --mr-id <mr_id> \
  --thread-id <thread_id>
```

如果后续发现该 thread 其实不该关闭，也可以重新打开：

```bash
.codex/skills/push-code/bin/push-code-run.sh reopen-thread \
  --mr-id <mr_id> \
  --thread-id <thread_id>
```

如果问题是普通 MR note，而不是 thread/discussion，可直接在 MR 下追加一条普通评论：

```bash
.codex/skills/push-code/bin/push-code-run.sh note \
  --mr-id <mr_id> \
  --body-file <reply-file>
```

如果 `wait-review` 返回的阻塞来自 mergeability / pipeline / external review stage，而不是 discussion，则先读取 `status` / `threads` 输出里的 `meta`、`notes` 和 `raw.merge_request`，再判断是需要修代码、回复普通 note，还是仅等待检查继续运行。

每次 push 之后重新进入 `wait-review` 时，都要把全部非 system MR notes 重新过一遍，不能因为 `unresolved_threads = 0` 就跳过。推荐至少维护一份“已处理 note revision 集合”，按 note 的 `revision_key` 去重；若没有该字段，则使用 `id` / `updated_at` / `body_sha256` 组合。只要发现新增 reviewer note，或已有 note 的 revision 发生变化，就要明确标成“待处理 review finding / 待确认 finding”。

### 7. 修复并再次 push

如果你接受 review 意见，则：

1. 修改代码
2. 运行必要验证
3. `git add`
4. `git commit`
5. `push`
6. 对已确认修复完成的 unresolved threads 执行 `resolve-thread`
7. 再次执行：

```bash
.codex/skills/push-code/bin/push-code-run.sh push
.codex/skills/push-code/bin/push-code-run.sh wait-review --mr-id <mr_id>
```

不要在没有新 commit 的情况下空转轮询 review。

如果在第 5 步 push 时触发本地 pre-push 检查失败：

1. 先读取 pre-push 脚本输出
2. 区分是测试失败、lint 失败、构建失败还是环境配置问题
3. 基于失败原因继续修复
4. 修复后重新 `git add`、`git commit`
5. 再次执行 `push`

不要为了“尽快过掉检查”而跳过 hook、强推、或忽略检查结果继续创建 MR。

## 终态约束

push-code 工作流只有两类允许收口的终态：

- `approved`，或 `workflow_guidance.review_complete=true`，并且当前不存在尚未阅读的 reviewer note revision
- 明确超时 / API 失败 / 需要用户介入，且你已经把 blocker 讲清楚

以下状态一律不是完成态：

- `pending`
- `needs_rebase`
- `changes_requested`
- `ci_still_running`
- `head_pipeline.status` 仍是 `running` / `pending` / `preparing`
- 任何 `workflow_guidance.can_announce_completion=false` 的返回

因此：

- 只要 MR 还没进入完成态，就不能在 final answer 里写“流程完成”“MR 已通过”“现在只差人工 merge”
- 只要 MR 还没进入完成态，而且也没有新的明确 blocker 需要用户当下决策，就根本不能发送 final answer；此时只允许继续轮询并发送 commentary 更新
- 只有在最新 head pipeline 已经结束、且 review 通过或 `workflow_guidance.review_complete=true` 时，才能把状态表述成“MR 已达到可提交状态”
- 如果还在 `pending` 但同时已经出现 reviewer finding，要明确说明“CI 仍在运行，同时已有待处理 review finding”

## 决策原则

### 证据优先

面对 review finding 时：

- 先读 discussion 原文
- 再读对应代码与 diff
- 最后决定接受、质疑还是拒绝

不要仅凭“看起来像误报”就直接回复 reviewer。

### 最小动作面

进入修订轮后，只修改与当前 findings 直接相关的内容。

不要顺手做无关重构，否则会让 MR 在下一轮 review 中引入新的噪音。

### 明确区分两种动作

- `回复 discussion / note`：用于解释、追问、反驳、同步修复计划
- `resolve thread`：用于在修复代码并 push 完成后，显式关闭已经处理完的 review thread
- `修改代码并 push`：用于实际消除 review 问题

二者不要混淆；如果只是有疑问，不应直接修改大量代码来“碰碰运气”。

## 推荐输出骨架

在向用户同步进度时，尽量按这个顺序：

1. 当前 preflight / push / MR / review 所处阶段
2. 已拿到的 `mr_id`
3. 当前 review 结论：达到可提交状态 / 待处理 / 超时
   - 如果是 `pending`，要区分“纯等待检查”还是“等待检查 + 已出现待处理 reviewer note”
4. 如果当前存在 mergeability blocker：
   - 是否需要 rebase
   - 是否有冲突需要先解决
5. 如果有 findings：
   - 哪些准备接受并修复
   - 哪些准备通过 discussion 提问或反驳
6. 下一步动作

## 失败处理

- preflight 失败：终止流程并说明是 dirty working tree、detached HEAD 还是缺配置
- push 失败：不要擅自改 remote 或强推；如果是本地 pre-push 检查失败，先分析并修复，再重新 commit + push
- need rebase：先执行 `rebase-target`，完成后用 `push --force-with-lease` 更新远端分支
- 外部 review / pipeline blocker：不要因为没有 thread 就判通过；先看当前 head SHA 的全部 `pipelines`、`detailed_merge_status`、`head_pipeline.status`、`status_checks` 和普通 MR notes。任意当前 head pipeline / status check 失败都优先于其他 running / pending 信号
- unresolved threads 未关闭：即使 reviewer 已口头通过，MR 仍可能因为 `discussions_not_resolved` 无法合并；修复并 push 后记得 `resolve-thread`
- create MR 失败：不要伪造 `mr_id`
- wait review 超时：向用户报告当前 `mr_id`、最后一次状态和已知 discussions
- discussion 回复失败：保留准备回复的文本，并向用户说明 GitLab API 调用失败

## Final Answer 约束

- `final answer` 只允许出现在两类场景：
  1. MR 已达到可提交状态
  2. 出现明确 blocker，需要用户介入、授权或后续人工接手
- 如果只是 “MR 已创建成功，但 CI 还在 running / pending”，这不是 `final answer` 场景
- 如果只是 “review note 看起来通过，但 pipeline 还没结束”，这也不是 `final answer` 场景
- 如果 helper 返回的 `workflow_guidance` 明确要求 `keep_waiting_*_in_current_session`，那就把它当成禁止 final 收口的硬门禁

## 明确禁止

- 不要自动 merge MR
- 不要调用任何自动合并、squash merge、rebase merge、merge when pipeline succeeds 之类动作
- MR 是否最终合并，必须交由人工确认和执行

## 配置说明

安装后配置位于：

- `.codex/skills/push-code/config.env`

字段说明见：

- `.codex/skills/push-code/reference.md`

如果 GitLab 实例有额外认证或代理要求，优先调整配置或 helper，不要在主流程里内联一套新的手写请求逻辑。
