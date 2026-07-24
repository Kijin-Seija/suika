# Reviewer workflow template

该模板安装一个“外层独立盲审 + 内层主 agent 修复/同一 reviewer 复查”的 reviewer skill，支持 Codex 原生 subagent 和 Claude + 外部 Codex 两种宿主。

## 收敛规则

reviewer 不再要求零 finding。只有同时满足以下条件的 issue 才阻塞交付：

- `blocking|important`
- `change_introduced|task_related`
- blocking 为 `high|medium` confidence；important 必须为 `high`
- code 必须是当前已观察到的 failing check、runtime reproduction 或 safe PoC；doc 可使用 document observation
- 必须提供当前可达、observed=true 的完整复现包
- 不处理会破坏原始任务交付

未来风险、静态路径推断、无法实际复现以及“可能导致”类结论不阻塞。主 agent 修改前必须独立执行复现；无法复现时不得修改。

minor、历史/范围外问题、低置信度推测、medium-confidence important 和纯优化进入持久 `review-backlog.json`，不触发修复循环。一次全新的独立盲审没有交付 blocker 后稳定收敛；普通模式也可在最大盲审次数结束。

## 隔离与记忆

每只新 reviewer 都是独立盲审，只接收：

- 原始任务
- 固定 baseline 和当前 baseline diff/完整文档
- 真实工作区
- `consensus-exclusions.json`
- `review-backlog.json`

它不会接收历史 review、主 agent 回应、当前轮次或最大轮次。当前轮发现 blocker 后，由主 agent 修改，再让同一个 reviewer 带本轮上下文复查。

## 安装

默认安装 Codex 版：

```bash
bash workflow-templates/reviewer/init.sh /path/to/project
```

显式选择宿主：

```bash
bash workflow-templates/reviewer/init.sh --codex /path/to/project
bash workflow-templates/reviewer/init.sh --claude /path/to/project
```

安装器会写入项目级 skill、prompts、schemas、兼容 launcher，并更新 AGENTS.md 或 CLAUDE.md 的受控区块。

## 执行方式

Codex 版优先使用 reviewer subagent。`.codex/skills/reviewer/bin/reviewer-run.sh` 仅用于兼容、回归测试和排障。

Claude 版通过：

```bash
.claude/skills/reviewer/bin/reviewer-run.sh blind ...
.claude/skills/reviewer/bin/reviewer-run.sh followup ...
```

默认 reviewer 模型为 `gpt-5.4`，可通过 `REVIEWER_CODEX_REVIEW_MODEL` 覆盖。

## 长周期运行

每个主会话最多完成 10 次独立盲审。仍需继续时写入 `workflow-state.json` 和 `session-handoff.md`，然后在相同 local checkout 的无历史新会话中 resume。不要 fork，不要创建 worktree。

goal 模式全局最多 20 次独立盲审；任意一次新盲审无 delivery blocker 即结束。第 20 轮内层收敛后以 `review-budget-completed` 停止，不要求零 finding。

## 持久文件

- `brief.md`
- `consensus-exclusions.json`
- `review-backlog.json`
- `workflow-state.json`
- 必要的 `session-handoff.md`、`final.md`、`dispute-report.md`

每轮完成后清理该轮 artifact/review/response/revision 文件，避免长期运行累积中间产物。
