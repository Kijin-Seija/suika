# 双模型共识工作流-计划制定

这是一个可复用的外置模板包，用于在其他项目中初始化“Claude 起草计划、GPT 做 review、控制器负责收敛判断”的双模型共识工作流。

该模板聚焦 `plan` 制品，不包含通用 `analysis` 分支。

## 包含内容

- `SKILL.md`：工作流入口与控制器协议
- `reference.md`：文件契约、收敛规则、输出格式
- `prompts/`：首稿、review、修订、分歧报告模板
- `agents/`：`claude-author` 与 `gpt-reviewer` 角色说明
- `docs/dual-model-consensus-plan-workflow.md`：给人阅读的完整工作流说明

## 适用场景

适用于以下类型的请求：

- 需求已经比较明确，需要产出开发计划
- 希望由一个模型负责写计划，另一个模型专门做审查
- 希望过程文件可审计，而不是反复覆盖单个文档

## 在其他项目中初始化引入

假设目标项目根目录为 `<target-project>`。

### 1. 一键初始化

优先使用初始化脚本：

```bash
./workflow-templates/dual-model-consensus-plan/init.sh /path/to/target-project
```

脚本会自动：

- 创建目标目录结构
- 复制 `SKILL.md`、`reference.md`、`prompts/`、`agents/` 和工作流文档
- 若目标项目没有 `AGENTS.md` 则自动创建
- 若目标项目已有 `AGENTS.md`，则自动追加或更新带哨兵标记的工作流区块

重复执行是安全的：

- 模板文件会被当前版本覆盖
- `AGENTS.md` 中的工作流区块会按标记替换，不会重复追加同一段

### 2. 手动初始化

在目标项目中创建以下目录：

```text
<target-project>/.cursor/skills/dual-model-consensus-plan/
<target-project>/.cursor/prompts/dual-model-consensus-plan/
<target-project>/.cursor/agents/
<target-project>/.cursor/plans/
<target-project>/docs/ai/
```

### 3. 复制模板文件

把本模板中的文件复制到目标项目：

```text
workflow-templates/dual-model-consensus-plan/SKILL.md
  -> <target-project>/.cursor/skills/dual-model-consensus-plan/SKILL.md

workflow-templates/dual-model-consensus-plan/reference.md
  -> <target-project>/.cursor/skills/dual-model-consensus-plan/reference.md

workflow-templates/dual-model-consensus-plan/prompts/claude-analysis-planner.md
  -> <target-project>/.cursor/prompts/dual-model-consensus-plan/claude-analysis-planner.md

workflow-templates/dual-model-consensus-plan/prompts/gpt-review.md
  -> <target-project>/.cursor/prompts/dual-model-consensus-plan/gpt-review.md

workflow-templates/dual-model-consensus-plan/prompts/claude-revision.md
  -> <target-project>/.cursor/prompts/dual-model-consensus-plan/claude-revision.md

workflow-templates/dual-model-consensus-plan/prompts/disagreement-report.md
  -> <target-project>/.cursor/prompts/dual-model-consensus-plan/disagreement-report.md

workflow-templates/dual-model-consensus-plan/agents/claude-author.md
  -> <target-project>/.cursor/agents/claude-author.md

workflow-templates/dual-model-consensus-plan/agents/gpt-reviewer.md
  -> <target-project>/.cursor/agents/gpt-reviewer.md

workflow-templates/dual-model-consensus-plan/docs/dual-model-consensus-plan-workflow.md
  -> <target-project>/docs/ai/dual-model-consensus-plan-workflow.md
```

### 4. 在目标项目的 `AGENTS.md` 中声明工作流

把下面这段加入目标项目根目录的 `AGENTS.md`：

```md
## 双模型共识工作流-计划制定

当用户显式要求使用“双模型共识工作流-计划制定”生成开发计划时，优先使用项目级 skill：

- `.cursor/skills/dual-model-consensus-plan/SKILL.md`

不要默认对所有普通请求启用该流程；只有用户明确要求时才触发。

相关模板位于：

- `.cursor/prompts/dual-model-consensus-plan/claude-analysis-planner.md`
- `.cursor/prompts/dual-model-consensus-plan/gpt-review.md`
- `.cursor/prompts/dual-model-consensus-plan/claude-revision.md`
- `.cursor/prompts/dual-model-consensus-plan/disagreement-report.md`

运行产物保存在：

- `.cursor/plans/<topic-slug>/`
```

### 5. 触发方式

在目标项目中，可以这样触发：

```text
请使用双模型共识工作流-计划制定，为下面这个任务生成开发计划：

任务：为新的 API 网关灰度发布能力制定实施计划
主题：api-gateway-rollout
最大轮次：3
```

或：

```text
使用 dual-model-consensus-plan skill 处理这个任务，输出开发计划。
```

### 6. 初始化后自检

建议在目标项目中确认以下几点：

- `SKILL.md` 中引用的 `reference.md` 路径存在
- `prompts/` 下四个模板文件都已复制
- `.cursor/agents/` 下两个角色文件都可读取
- `.cursor/plans/` 目录可写
- `AGENTS.md` 已声明触发条件与路径

如果使用初始化脚本，额外建议确认：

- `AGENTS.md` 中只出现一次 `<!-- BEGIN dual-model-consensus-plan -->`
- 重新执行脚本后，`AGENTS.md` 中对应区块被更新而不是重复追加

## 建议的目录命名

如果你准备在多个项目复用，建议统一使用以下命名：

- skill 目录：`dual-model-consensus-plan`
- prompt 目录：`dual-model-consensus-plan`
- 参考文档：`docs/ai/dual-model-consensus-plan-workflow.md`

## 维护建议

- 若你更新了模板，请同步更新 `SKILL.md`、`reference.md` 与 `README.md`
- 若你修改了 prompt 文件名，也要同步更新 `SKILL.md` 与 `AGENTS.md` 中的路径
- 如果后续想扩展到“分析 + 计划”双制品，再从当前模板派生出通用版会更稳妥
