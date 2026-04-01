# 实现闭环工作流

这是一个可复用模板包，用于初始化“Codex 作为控制器和 reviewer，writer 可选 Claude Code CLI 或独立 Codex CLI 子进程负责实现与修订”的代码实现工作流。

该工作流只面向代码任务，不处理计划文档或纯分析任务。

## 工作流效果

触发后，控制器会执行以下闭环：

1. Codex 将实现任务交给所选 writer。
2. 所选 writer 直接修改工作区代码，并返回结构化变更摘要。
3. Codex 基于最新 `git diff`、变更摘要和上一轮回应做结构化审查。
4. 如果未通过，writer 逐条判断问题：
   - 属实则修复
   - 存疑则提出疑问
   - 不成立则说明理由
   - 当 writer 是 Claude Code 且出现 400/上下文过大类错误时，launcher 会自动切到紧凑模式重试
5. Codex 再次审查最新结果。
6. 循环直到通过，或达到最大轮次；默认 `5` 轮。
7. 如果达到轮次上限仍未通过，Codex 输出 `dispute-report.md` 交由人类裁决。

为降低 Claude Code 在大仓库或多轮修订中的不稳定性，launcher 现在还会：

- 为每轮修订生成精简的 `writer-handoff-rN.md`，避免反复把完整 diff 当成主要输入
- 用 `--no-session-persistence` 发起无状态调用，减少历史会话噪音
- 捕获 Claude stderr，并对上下文过大/瞬时失败做自动重试
- 在重试时切换到更严格的上下文约束 prompt，要求 Claude 只读必要文件

## 目录结构

```text
workflow-templates/writer/
  common/
    bin/
    prompts/
    schemas/
    reference.md
  codex/
    skill/
    init.sh
  tests/
    installers.sh
  init.sh
  README.md
```

## 安装方式

默认安装 Codex 版本：

```bash
./workflow-templates/writer/init.sh /path/to/target-project
```

也可以显式调用：

```bash
./workflow-templates/writer/codex/init.sh /path/to/target-project
```

安装结果包括：

- `.codex/skills/writer/`
- `.codex/skills/writer/prompts/`
- `.codex/skills/writer/schemas/`
- `.codex/skills/writer/bin/writer-run.sh`
- `.codex/plans/`
- `AGENTS.md` 中的工作流入口区块

## 触发方式

安装后，通过 `AGENTS.md` 暴露显式触发入口。典型说法：

```text
请使用 writer skill 实现这个功能。
请走实现闭环工作流，让 Claude Code 开发，Codex 审查。
请使用 writer skill，让 Codex 作为 writer 来实现这个 bug。
使用 writer skill 修复这个 bug，最多审查 3 轮。
```

如果用户没有显式要求，不要默认启用该流程。

## 前提条件

- 当前项目必须是 git 仓库
- 启动时工作区必须是 clean working tree
- `claude`、`codex`、`git`、`python3` 必须可用
- 当前目录应当是你信任的仓库，因为 Claude Code 会被允许直接修改代码

## 手动执行 launcher

安装后，Codex skill 应优先调用 launcher，而不是在对话中手工模拟循环：

```bash
.codex/skills/writer/bin/writer-run.sh run \
  --task "修复支付回调重试逻辑" \
  --writer claude \
  --topic payment-retry-fix \
  --max-rounds 5
```

`--writer` 支持：

- `claude`：默认值，由 Claude Code CLI 负责实现与修订
- `codex`：由独立的 `codex exec` 子进程负责实现与修订，当前控制器会话仍只负责调度和审查

运行产物会写入：

```text
.codex/plans/<topic-slug>/
```

其中当 `writer=claude` 时，可能额外看到：

- `writer-handoff-rN.md`：给 Claude 修订轮使用的精简上下文
- `*.claude-prompt-aN.md`：每次 Claude 调用时落盘的 prompt
- `*.claude-stderr-aN.log`：Claude 调用失败时的 stderr，便于排查 400/限流/服务错误

这些文件都属于运行日志，不需要手工维护。

## Claude 稳定性参数

可以通过环境变量调节 Claude writer 的重试行为：

- `WRITER_CLAUDE_MAX_ATTEMPTS`
  - 默认 `3`
  - Claude 单次调用最多尝试次数
- `WRITER_CLAUDE_RETRY_BACKOFF_SECONDS`
  - 默认 `2`
  - 每次自动重试前的等待秒数
- `WRITER_CLAUDE_COMPACT_RETRY`
  - 默认 `1`
  - 命中上下文过大类错误时，是否切换到紧凑模式 prompt 再试一次

示例：

```bash
WRITER_CLAUDE_MAX_ATTEMPTS=4 \
WRITER_CLAUDE_RETRY_BACKOFF_SECONDS=3 \
.codex/skills/writer/bin/writer-run.sh run \
  --task "修复支付回调重试逻辑" \
  --writer claude
```

## 自检

运行以下测试验证安装器：

```bash
bash workflow-templates/writer/tests/installers.sh
```
