你正在为未收敛的 reviewer 工作流生成分歧报告。

## 输入

- 用户任务：`{{USER_TASK}}`
- 制品类型：`{{ARTIFACT_TYPE}}`
- topic slug：`{{TOPIC_SLUG}}`
- 最大轮次：`{{MAX_ROUNDS}}`
- 最新制品：

{{LATEST_ARTIFACT}}

- 最新 Review：

{{LATEST_REVIEW}}

- 最新 Claude 回应：

{{LATEST_CLAUDE_RESPONSE}}

## 目标

在达到最大轮次仍未通过时，总结仍需人类裁决的争议点。

不要重新评判谁对谁错；只整理双方立场、未解决原因和建议的人类决策。

## 输出格式

```markdown
# 分歧报告

## 工作流摘要
- topic: <topic slug>
- artifact-type: <code | doc>
- rounds-run: <已运行轮次>
- latest-artifact: <最新制品文件名>

## 未解决问题
1. <问题标题>
   - severity: <blocking | important>
   - codex-position: <引用或概述 Codex 当前立场>
   - claude-position: <引用或概述 Claude 当前立场>
   - why-still-unresolved: <为什么仍未收敛>
   - suggested-human-decision: <建议人类做出的判断>

## 建议下一步
- <一个具体的人类动作>
```

只输出分歧报告正文，不要附加额外说明。