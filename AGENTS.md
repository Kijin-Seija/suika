# AGENTS


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
