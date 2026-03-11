# 分歧报告 Prompt

你正在为一个达到最大轮次但仍未收敛的双模型共识工作流准备最终报告。

## 上下文

task: {{USER_TASK}}
meta: artifact={{ARTIFACT_TYPE}} topic={{TOPIC_SLUG}} max_rounds={{MAX_ROUNDS}}
latest_artifact_summary:
{{LATEST_ARTIFACT_SUMMARY}}
latest_review_summary:
{{LATEST_REVIEW_SUMMARY}}
latest_claude_position:
{{LATEST_CLAUDE_POSITION}}
unresolved_issues:
{{UNRESOLVED_ISSUES}}

## 目标

总结仍未解决的分歧，帮助人工判断下一步该怎么做。

## 输出格式

```markdown
# 分歧报告

## 工作流摘要
- topic:
- artifact-type:
- rounds-run:
- latest-artifact:

## 未解决问题
1. <问题标题>
   - GPT position:
   - Claude position:
   - why still unresolved:
   - suggested human decision:

## 决策点
1. <需要用户决定的事项>

## 建议下一步
- <一个具体的人类动作>
```

## 规则

- 只关注仍未解决的问题
- 公平转述双方立场，不要夹带额外倾向
- 区分事实分歧与判断分歧
- 如果 `{{LATEST_CLAUDE_POSITION}}` 来自主制品推断，而不是显式响应日志，需要明确标注为 inferred from latest artifact
- 最后给出简短而具体的决策点列表
- 只返回控制器应保存到 `disagreement-report.md` 的报告正文
