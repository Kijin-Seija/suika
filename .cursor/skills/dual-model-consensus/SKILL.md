---
name: dual-model-consensus
description: 当用户显式要求使用双模型共识工作流处理任务分析、需求整理或开发计划时使用，特别适用于 Claude 起草、GPT review 的迭代协作场景。
---

# 双模型共识

## 概览

只在用户显式要求使用双模型共识流程时启用该工作流。

这套工作流包含一个控制器和两个角色代理：
- Claude Opus 4.6 负责起草或修订主 Markdown 制品
- GPT-5.4 负责 review 当前版本并提出修改计划
- 控制器负责判断流程是否收敛，或决定继续下一轮

## 触发条件

只有当用户明确提出以下意图时才应用本 skill：
- `使用双模型共识工作流`
- dual-model consensus
- Claude draft + GPT review loop
- iterative analysis / planning review between Claude and GPT

如果用户没有显式要求，不要默认启用。

## 必要输入

开始前需要收集或推断以下输入：
- 用户任务陈述
- 制品类型：`analysis` 或 `plan`
- 输出 topic slug，使用 lowercase kebab-case
- 最大 review 轮次，默认 `3`

如果用户没有提供 topic slug，应根据任务语义推导一个简短的 kebab-case 名称。

## 运行目录布局

工作流产物保存在：
- `.cursor/plans/<topic-slug>/brief.md`
- `.cursor/plans/<topic-slug>/draft-r1.md`
- `.cursor/plans/<topic-slug>/review-r1.md`
- `.cursor/plans/<topic-slug>/response-r2.md`
- `.cursor/plans/<topic-slug>/revision-r2.md`
- `.cursor/plans/<topic-slug>/review-r2.md`
- `.cursor/plans/<topic-slug>/response-r3.md`
- `.cursor/plans/<topic-slug>/revision-r3.md`
- `.cursor/plans/<topic-slug>/review-r3.md`
- `.cursor/plans/<topic-slug>/final.md`
- `.cursor/plans/<topic-slug>/disagreement-report.md`

只创建本次实际运行所需的文件。

所有运行产物都必须放在项目根目录下的 `.cursor/plans/` 中。必须使用 `.cursor/plans/<topic-slug>/` 这种 topic 子目录，确保迭代历史可审计。

## 角色代理

### Claude Opus 4.6

使用：
- prompt 模板：`../../prompts/dual-model-consensus/claude-analysis-planner.md`
- 修订模板：`../../prompts/dual-model-consensus/claude-revision.md`
- 推荐 subagent：`.cursor/agents/claude-author.md`

Claude 必须：
- 产出或更新主 Markdown 制品
- 对每一条 GPT review 意见做显式回应
- 把接受的修改落实到主文档中
- 对拒绝的建议给出理由和替代方案

### GPT-5.4

使用：
- prompt 模板：`../../prompts/dual-model-consensus/gpt-review.md`
- 推荐 subagent：`.cursor/agents/gpt-reviewer.md`

GPT 必须：
- 只做 review，不直接改写主制品
- 识别 `blocking`、`important`、`minor` 问题
- 给出具体修改计划
- 明确判断当前文档是否无需再修订即可接受

### 控制器

控制器就是当前会话中的父 agent。控制器必须：
- 收集并标准化输入
- 创建 topic 目录和 `brief.md`
- 决定下一步调用哪个角色代理
- 显式把所需上下文传给 subagent
- 把每次输出保存到正确文件
- 在每一轮 GPT review 后执行收敛检查
- 在达到轮次上限时停止
- 输出 `final.md` 或 `disagreement-report.md`

不要把“是否继续下一轮”的决定权交给角色代理。循环控制只属于控制器。

## 控制器执行协议

1. 先把用户请求标准化写入 `brief.md`。
2. 在 `brief.md` 中记录执行元数据，包括：
   - topic slug
   - 制品类型
   - 最大 review 轮次
   - 标准化后的任务描述
   - 执行模式：`automatic` 或 `manual-fallback`
   - 如果某一轮曾手动重跑，则记录 model-binding notes
3. 渲染首稿 prompt，包含：
   - `{{USER_TASK}}`
   - `{{ARTIFACT_TYPE}}`
   - `{{TOPIC_SLUG}}`
   - `{{ROUND}} = 1`
   - `{{MAX_ROUNDS}}`
4. 调用 Claude Opus 4.6 生成首稿。
5. 只把主制品正文保存为 `draft-r1.md`。
6. 渲染 GPT review prompt，包含：
   - 同一组任务元信息
   - `{{ROUND}} = 1`
   - `{{CURRENT_ARTIFACT}} = draft-r1.md`
7. 调用 GPT-5.4 review 该文件。
8. 把 review 保存为 `review-r1.md`。
9. 运行 `reference.md` 中的完整收敛检查。
10. 如果检查通过，则把最新主制品正文写入 `final.md` 并停止。
11. 如果当前 GPT review 轮次已经达到上限，则渲染分歧报告 prompt，包含：
    - `{{USER_TASK}}`
    - `{{ARTIFACT_TYPE}}`
    - `{{TOPIC_SLUG}}`
    - `{{MAX_ROUNDS}}`
    - `{{LATEST_ARTIFACT}} = 最新 draft 或 revision`
    - `{{LATEST_REVIEW}} = 最新 review`
    - `{{LATEST_CLAUDE_RESPONSE}} = 最新 response 文件；如果尚未发生 Claude 修订轮次则传 \`none\``
    - `{{REVIEW_HISTORY}} = 按顺序排列的历史 review 文件`
    - `{{CLAUDE_RESPONSE_HISTORY}} = 按顺序排列的历史 response 文件；如果为空则传 \`none\``
12. 调用分歧报告 prompt 生成未收敛总结，并保存为 `disagreement-report.md`。
13. 否则，渲染 Claude 修订 prompt，包含：
    - `{{ROUND}} = 下一轮 review 的轮次号`
    - `{{PREVIOUS_ARTIFACT}} = 最新 draft 或 revision`
    - `{{LATEST_REVIEW}} = 最新 review`
14. 调用 Claude Opus 4.6 根据最新制品和最新 review 进行修订。
15. 按要求的哨兵拆分 Claude 输出：
    - `<!-- BEGIN_RESPONSE -->` ... `<!-- END_RESPONSE -->`
    - `<!-- BEGIN_REVISION -->` ... `<!-- END_REVISION -->`
16. 拆分后移除哨兵注释。
17. 将响应正文保存为 `response-rN.md`。
18. 将修订后的主制品正文保存为 `revision-rN.md`。
19. 让 GPT-5.4 review `revision-rN.md`，不要 review `response-rN.md`。
20. 重复以上过程，直到收敛或达到轮次上限。

## Prompt 渲染规则

控制器应把完整渲染后的 prompt 文本直接传给 subagent，而不是让 subagent 自己去加载模板。

每次调用 subagent 时都应明确提供：
- 工作流目的
- 当前轮次
- 完整渲染后的 prompt
- 预期输出文件名
- 只有控制器负责写文件这一规则

由于 subagent 从干净上下文启动，绝不要假设它能看到此前对话历史。

## 收敛规则

只有同时满足以下条件，流程才算收敛：
- GPT review 明确认为当前文档 acceptable，且没有 `blocking` 问题
- Claude 已经接受所有必要修改，或对剩余分歧说明了其 non-blocking 理由

控制器在写入 `final.md` 之前，还必须执行 `reference.md` 中的全部收敛检查项。

如果 `review-r1.md` 已经接受 `draft-r1.md`，流程可以直接收敛，无需生成任何 `response-rN.md` 或 `revision-rN.md`。

## 轮次上限

默认最大 review 轮次为 `3`，除非用户另行指定。

如果达到轮次上限仍未收敛：
- 立即停止循环
- 使用 `../../prompts/dual-model-consensus/disagreement-report.md` 生成 `disagreement-report.md`
- 总结仍未解决的问题、双方理由，以及需要用户做出的决策

轮次按 GPT review 文件计数：`review-r1.md`、`review-r2.md`、`review-r3.md`。

## 模型绑定与回退

优先使用 `.cursor/agents/` 下的项目级 subagent，让每个角色都能请求其目标模型。

但控制器必须把模型绑定视为 best-effort 的运行时设置。如果 Cursor 没有按预期使用 subagent 配置的模型：
- 保持相同的文件契约和轮次协议
- 显式点名调用目标角色 subagent
- 必要时先让人手动切换当前模型，再重跑该轮
- 把重跑情况记录到 `brief.md` 的 `model-binding-notes`
- 不要因为模型选择回退就改动整个工作流结构

回退路径必须保持同样的产物、命名和停机条件。

## 输出契约

流程最终只能以下两种结果之一结束：
- 收敛结果：`final.md`
- 未收敛结果：`disagreement-report.md` + 最新主制品，该主制品可能是 `draft-r1.md`，也可能是最新的 `revision-rN.md`

## 补充说明

请阅读 `reference.md` 获取：
- 制品章节结构要求
- review 严重级别定义
- 控制器检查表
- 文件命名规则
- 示例流程序列

