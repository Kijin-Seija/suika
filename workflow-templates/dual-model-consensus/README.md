# 双模型共识工作流

这是一个可复用模板包，用于初始化“Claude 产出主制品、GPT 做 review、控制器只负责调度/收敛/落盘”的双模型共识工作流。

当前版本已拆分为三层目录：

- `common/`：公共协议、共享 reference、共享 prompts
- `cursor/`：Cursor 宿主专属入口、agents、安装脚本；保持原有 Cursor 逻辑不变
- `claude/`：Claude Code 宿主专属入口、agents、安装脚本与说明

支持两种制品类型：

- `plan`：Claude 产出 Markdown 计划文档，GPT review 文档
- `code`：Claude 直接修改代码文件，GPT 基于 git diff 做 code review

## 目录结构

```text
workflow-templates/dual-model-consensus/
  common/
    reference.md
    prompts/
  cursor/
    skill/
    agents/
    init.sh
  claude/
    skill/
    agents/
    init.sh
  tests/
    installers.sh
  init.sh
  README.md
```

## 安装方式

### Cursor

兼容旧入口，默认安装 Cursor 版本：

```bash
./workflow-templates/dual-model-consensus/init.sh /path/to/target-project
```

也可以显式调用：

```bash
./workflow-templates/dual-model-consensus/cursor/init.sh /path/to/target-project
```

安装结果保持不变：

- `.cursor/skills/dual-model-consensus/`
- `.cursor/prompts/dual-model-consensus/`
- `.cursor/agents/`
- `.cursor/plans/`
- `AGENTS.md` 工作流区块

根入口还支持显式模式：

```bash
./workflow-templates/dual-model-consensus/init.sh --cursor /path/to/target-project
./workflow-templates/dual-model-consensus/init.sh --claude /path/to/target-project
./workflow-templates/dual-model-consensus/init.sh --all /path/to/target-project
```

- `--cursor`：只安装 Cursor 版
- `--claude`：只安装 Claude Code 版
- `--all`：同时安装 Cursor 和 Claude Code 两版

可以用下面的命令查看帮助：

```bash
./workflow-templates/dual-model-consensus/init.sh --help
```

示例输出：

```text
用法:
  init.sh <target-project>          默认安装 Cursor 版
  init.sh --cursor <target-project> 只安装 Cursor 版
  init.sh --claude <target-project> 只安装 Claude Code 版
  init.sh --all <target-project>    同时安装 Cursor 和 Claude Code 两版
```

### Claude Code

安装 Claude Code 原生版本：

```bash
./workflow-templates/dual-model-consensus/claude/init.sh /path/to/target-project
```

或使用根入口：

```bash
./workflow-templates/dual-model-consensus/init.sh --claude /path/to/target-project
```

安装结果包括：

- `.claude/skills/dual-model-consensus/`
- `.claude/skills/dual-model-consensus/prompts/`
- `.claude/agents/`
- `.claude/plans/`
- `CLAUDE.md` 工作流区块

当前原型阶段的一个重要限制：

- Claude Code 的 subagent `model` 只能使用 Claude 系列模型
- 因此 `claude/agents/gpt-reviewer.md` 当前是“保留 GPT reviewer 角色名，但由 Claude 模型临时承担 review 职责”的兼容实现
- Cursor 版本仍保留真正的 `GPT reviewer` 配置，不受此限制影响

## 公共层与宿主层边界

放入 `common/` 的内容必须满足“跨宿主共享”这一条件，例如：

- 协议约束
- reference 文档
- 不依赖宿主目录结构的 prompts

保留在 `cursor/` 或 `claude/` 的内容通常包括：

- 宿主入口文档
- agents frontmatter
- 安装脚本
- 宿主特定的路径与发现机制说明

## 触发方式

### Cursor

安装后通过 `AGENTS.md` 暴露工作流入口，继续沿用原有触发方式，例如：

```text
请使用双模型共识工作流处理下面这个任务：
```

### Claude Code

安装后通过 `CLAUDE.md` 和 `.claude/skills/dual-model-consensus/` 暴露工作流入口，支持显式触发 `dual-model-consensus` skill 或自然语言触发。

如果后续需要恢复真正的双模型语义，推荐在 Claude 版本中补一层外部 reviewer 通道，例如 MCP、API 或独立 review 脚本，而不是继续依赖 Claude Code 原生 subagent 的 `model` 字段。

## 自检

运行以下测试，验证 Cursor 与 Claude 两套安装器都可用：

```bash
bash workflow-templates/dual-model-consensus/tests/installers.sh
```
