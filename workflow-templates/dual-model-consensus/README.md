# 双模型共识工作流

这是一个可复用的模板包，用于在其他项目中初始化“Claude 产出主制品、GPT 做 review、控制器负责收敛判断”的双模型共识工作流。

当前版本统一使用 `dual-model-consensus` 命名，并支持两种制品类型：

- `plan`：Claude 产出 Markdown 计划文档，GPT review 文档
- `code`：Claude 直接修改代码文件，GPT 基于 git diff 做 code review

## 模板结构

- `skill/SKILL.md`：工作流入口与控制器协议
- `skill/reference.md`：文件契约、收敛规则、输出格式
- `prompts/`：plan/code 两种模式用到的全部 prompt
- `agents/`：`claude-author` 与 `gpt-reviewer` 角色说明
- `init.sh`：覆盖式安装脚本

## 一键初始化

优先使用初始化脚本：

```bash
./workflow-templates/dual-model-consensus/init.sh /path/to/target-project
```

脚本会自动：

- 删除目标项目中旧的 `dual-model-consensus` 与 `dual-model-consensus-plan` skill/prompt 安装残留
- 覆盖写入统一后的 `SKILL.md`、`reference.md`、7 个 prompt 和 2 个 agent
- 创建 `.cursor/plans/`
- 创建或更新目标项目根目录的 `AGENTS.md` 工作流区块

重复执行是安全的；脚本每次都会先清理旧版目录，再覆盖写入当前模板内容。

## 手动初始化目录

如果不使用脚本，目标项目至少需要以下目录：

```text
<target-project>/.cursor/skills/dual-model-consensus/
<target-project>/.cursor/prompts/dual-model-consensus/
<target-project>/.cursor/agents/
<target-project>/.cursor/plans/
```

## 手动复制文件

```text
workflow-templates/dual-model-consensus/skill/SKILL.md
  -> <target-project>/.cursor/skills/dual-model-consensus/SKILL.md

workflow-templates/dual-model-consensus/skill/reference.md
  -> <target-project>/.cursor/skills/dual-model-consensus/reference.md

workflow-templates/dual-model-consensus/prompts/claude-analysis-planner.md
  -> <target-project>/.cursor/prompts/dual-model-consensus/claude-analysis-planner.md

workflow-templates/dual-model-consensus/prompts/gpt-review.md
  -> <target-project>/.cursor/prompts/dual-model-consensus/gpt-review.md

workflow-templates/dual-model-consensus/prompts/claude-revision.md
  -> <target-project>/.cursor/prompts/dual-model-consensus/claude-revision.md

workflow-templates/dual-model-consensus/prompts/disagreement-report.md
  -> <target-project>/.cursor/prompts/dual-model-consensus/disagreement-report.md

workflow-templates/dual-model-consensus/prompts/claude-code-draft.md
  -> <target-project>/.cursor/prompts/dual-model-consensus/claude-code-draft.md

workflow-templates/dual-model-consensus/prompts/gpt-code-review.md
  -> <target-project>/.cursor/prompts/dual-model-consensus/gpt-code-review.md

workflow-templates/dual-model-consensus/prompts/claude-code-revision.md
  -> <target-project>/.cursor/prompts/dual-model-consensus/claude-code-revision.md

workflow-templates/dual-model-consensus/agents/claude-author.md
  -> <target-project>/.cursor/agents/claude-author.md

workflow-templates/dual-model-consensus/agents/gpt-reviewer.md
  -> <target-project>/.cursor/agents/gpt-reviewer.md
```

## AGENTS.md 声明

脚本会写入如下工作流区块：

```md
<!-- BEGIN dual-model-consensus -->
## 双模型共识工作流

当用户显式要求使用"双模型共识工作流"时，优先使用项目级 skill：

- `.cursor/skills/dual-model-consensus/SKILL.md`

不要默认对所有普通请求启用该流程；只有用户明确要求时才触发。

支持两种制品类型：`plan`（计划制定）和 `code`（代码开发）。

相关模板位于：

- plan 模式: `claude-analysis-planner.md`, `gpt-review.md`, `claude-revision.md`
- code 模式: `claude-code-draft.md`, `gpt-code-review.md`, `claude-code-revision.md`
- 共用: `disagreement-report.md`
- 目录: `.cursor/prompts/dual-model-consensus/`

运行产物保存在：

- `.cursor/plans/<topic-slug>/`
<!-- END dual-model-consensus -->
```

## 触发示例

```text
请使用双模型共识工作流处理下面这个任务：

任务：为新的 API 网关灰度发布能力制定实施计划
主题：api-gateway-rollout
最大轮次：3
```

或：

```text
使用 dual-model-consensus skill 处理这个任务。
```

## 初始化后自检

- `.cursor/skills/dual-model-consensus/` 下存在 `SKILL.md` 与 `reference.md`
- `.cursor/prompts/dual-model-consensus/` 下存在 7 个 prompt
- `.cursor/agents/` 下两个角色文件可读取
- `.cursor/plans/` 目录可写
- `AGENTS.md` 中只存在一次 `<!-- BEGIN dual-model-consensus -->`

## 控制器渲染模板

最小化的控制器渲染规范示例见 `skill/reference.md` 中的“最小化控制器渲染模板”一节，包含：

- 通用 subagent 调用外壳
- `REVISION_CONTEXT` 模板
- `CODE_REVIEW_CONTEXT` 模板
- 分歧报告摘要模板

其中 `draft-r1.md` / `revision-rN.md` / `final.md` 用于落盘追踪，可以包含完整 diff；但 `code` 模式真正传给 reviewer 或 Claude 修订轮的，应该是单独渲染的紧凑 `CODE_REVIEW_CONTEXT`，不要把这些跟踪文件原样整包转发。

## 维护建议

- 更新模板时，同步维护 `skill/SKILL.md`、`skill/reference.md`、`README.md` 与 `init.sh`
- 修改 prompt 文件名或目录时，同步更新 `SKILL.md`、`README.md` 与 `init.sh`
