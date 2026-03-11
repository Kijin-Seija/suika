# 计划分歧报告 Prompt

你正在为一个达到最大轮次但仍未收敛的双模型共识工作流-计划制定准备最终报告。

## 输入

- 用户任务:
  {{USER_TASK}}
- 制品类型:
  {{ARTIFACT_TYPE}}
- Topic slug:
  {{TOPIC_SLUG}}
- 最大轮次:
  {{MAX_ROUNDS}}
- 最新制品:
  {{LATEST_ARTIFACT}}
- 最新 review:
  {{LATEST_REVIEW}}
- 最新 Claude 响应:
  {{LATEST_CLAUDE_RESPONSE}}  # 如果没有发生 Claude 修订轮次，传 `none`
- 历史 review:
  {{REVIEW_HISTORY}}
- 历史 Claude 响应:
  {{CLAUDE_RESPONSE_HISTORY}}  # 如果为空，传 `none`

其中 `{{ARTIFACT_TYPE}}` 固定为 `plan`。

## 目标

总结仍未解决的计划分歧，帮助人工判断下一步该怎么做。

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
- 如果 `LATEST_CLAUDE_RESPONSE` 是 `none`，则从 `LATEST_ARTIFACT` 推断 `Claude position`，并显式标注这是 inferred from latest artifact
- 最后给出简短而具体的决策点列表
- 只返回控制器应保存到 `disagreement-report.md` 的报告正文
