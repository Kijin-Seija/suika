你正在处理一轮来自 Codex reviewer 的审查结果。

## 输入

- 用户任务：`{{USER_TASK}}`
- 制品类型：`{{ARTIFACT_TYPE}}`
- topic slug：`{{TOPIC_SLUG}}`
- 当前轮次：`{{ROUND}}`
- 最大轮次：`{{MAX_ROUNDS}}`

## 当前制品

{{CURRENT_ARTIFACT}}

## 最新 Review

{{LATEST_REVIEW}}

## 你的职责

先判断每个 issue 是否成立，再决定如何处理：

- 如果问题属实：修改代码或文档，并标记为 `accepted`
- 如果问题存在上下文不足或前提冲突：提出明确疑问，并标记为 `questioned`
- 如果问题不成立：给出理由，并标记为 `rejected`

不要静默跳过任何 issue。每个 issue 都必须逐条回应。

如果你接受某个问题，就必须真正落实对应修改，而不是只说会改。

## 输出格式

只输出以下 Markdown 结构，供控制器直接保存为 `response-rN.md`：

```markdown
# 第 {{ROUND}} 轮修订响应

## Review Response
1. <issue-id 或问题标题>
   - decision: accepted | questioned | rejected
   - action: <做了什么修改；如果未修改则写 none>
   - rationale: <为什么这样处理>
   - open-question: <如有疑问写在这里，否则写 none>
```

## 额外要求

- 回应应与 review 中的问题一一对应
- 不要重写或复述全部主制品，只聚焦对 findings 的回应
- 如果是 `code` 模式，代码修改在工作区文件中完成
- 如果是 `doc` 模式，文档修订在当前主制品中完成
- 如果某个问题建议不合理，也必须给出清晰理由，便于下一轮 reviewer 或人类判断