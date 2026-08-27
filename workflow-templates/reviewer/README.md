# Reviewer 工作流

该模板为 Codex 和 Claude Code 安装 reviewer skill，执行“外层独立盲审 + 内层主 agent 修复/同一 reviewer 复查”。

## 核心流程

1. 当前 Codex 或 Claude Code 会话完成主任务。
2. Codex 版使用上下文隔离的只读 reviewer subagent；Claude Code 版通过 launcher 启动外部只读 Codex reviewer。
3. 只有当前状态下可复现、与任务相关且会阻塞交付的问题才进入修订循环。
4. 主 agent 独立复现问题、修改工作区，再让同一 reviewer 复查。
5. 当前轮通过后启动新的独立盲审；一次新盲审没有交付阻塞问题即稳定收敛。
6. 非 goal 模式默认最多 10 轮；goal 模式全局最多 20 轮，并支持跨会话 checkpoint。

## 安装

```bash
bash workflow-templates/reviewer/init.sh /path/to/project
```

也可以显式指定 Codex：

```bash
bash workflow-templates/reviewer/init.sh --codex /path/to/project
```

Claude Code 版：

```bash
bash workflow-templates/reviewer/init.sh --claude /path/to/project
```

安装器会写入：

- `.codex/skills/reviewer/SKILL.md`
- `.codex/skills/reviewer/reference.md`
- `.codex/skills/reviewer/prompts/`
- `.codex/skills/reviewer/schemas/`
- `.codex/skills/reviewer/bin/reviewer-run.sh`
- `.codex/plans/`
- `AGENTS.md` 中的显式触发入口

原生 Codex subagent 是首选执行方式。`reviewer-run.sh` 仅保留作兼容与回归测试用途。

Claude Code 版安装到 `.claude/skills/reviewer/`，由 Claude 完成主任务并通过同名 `reviewer-run.sh blind|followup|resume` 命令启动外部只读 Codex reviewer；制品写入 `.claude/plans/`，不修改项目 `CLAUDE.md`。

Claude Code 原生调用为 `/reviewer`；launcher 位于 `.claude/skills/reviewer/bin/reviewer-run.sh`，保留 `blind`、`followup` 和 `resume` 子命令及原有参数。

## 持久文件

- `brief.md`
- `consensus-exclusions.json`
- `review-backlog.json`
- `workflow-state.json`
- 必要的 `session-handoff.md`、`final.md`、`dispute-report.md`

每轮完成后清理该轮 artifact/review/response/revision 文件，避免长期运行累积中间产物。

## 自检

```bash
bash workflow-templates/reviewer/tests/installers.sh
```
