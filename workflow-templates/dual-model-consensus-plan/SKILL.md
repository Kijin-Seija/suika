---
name: dual-model-consensus-plan
description: 当用户显式要求使用"双模型共识工作流"时使用，支持 plan（计划制定）和 code（代码开发）两种制品类型，适用于 Claude 起草、GPT review 的迭代协作场景。
---

# 双模型共识工作流

## 概览

只在用户显式要求使用这套流程时启用。

这套工作流包含一个控制器和两个角色代理：

- Claude 负责产出主制品（计划文档或代码变更）
- GPT 负责 review 当前版本并提出修改建议
- 控制器负责判断流程是否收敛，或决定继续下一轮

工作流支持两种制品类型：

- `plan`：Claude 产出 Markdown 计划文档，GPT review 该文档
- `code`：Claude 直接修改代码文件，GPT 基于 git diff 做 code review

## 触发条件

只有当用户明确提出以下意图时才应用本 skill：

- `使用双模型共识工作流-计划制定`
- `使用 dual-model-consensus-plan skill`
- `让 Claude 起草计划，GPT review`
- `用双模型共识流程生成开发计划`
- `用双模型共识工作流开发这个功能`
- `让 Claude 写代码，GPT review`

如果用户没有显式要求，不要默认启用。

## 必要输入

开始前需要收集或推断以下输入：

- 用户任务陈述
- 制品类型：`plan` 或 `code`，默认 `plan`
- 输出 topic slug，使用 lowercase kebab-case
- 最大 review 轮次，默认 `3`

如果用户的任务是开发代码、实现功能、修复 bug 等，制品类型应为 `code`。如果任务是制定计划、分析需求等，制品类型应为 `plan`。

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

所有运行产物都必须放在项目根目录下的 `.cursor/plans/` 中，并使用 `.cursor/plans/<topic-slug>/` 这种 topic 子目录。

## 角色代理

### Claude 作者

plan 模式使用：

- prompt 模板：`../../prompts/dual-model-consensus-plan/claude-analysis-planner.md`
- 修订模板：`../../prompts/dual-model-consensus-plan/claude-revision.md`

code 模式使用：

- prompt 模板：`../../prompts/dual-model-consensus-plan/claude-code-draft.md`
- 修订模板：`../../prompts/dual-model-consensus-plan/claude-code-revision.md`

推荐 subagent：`.cursor/agents/claude-author.md`

Claude 在 plan 模式下必须：

- 产出或更新主 Markdown 计划文档
- 对每一条 GPT review 意见做显式回应
- 把接受的修改落实到主文档中
- 对拒绝的建议给出理由和替代方案

Claude 在 code 模式下必须：

- 直接修改代码文件完成任务
- 返回变更摘要文本
- 修订时对每一条 GPT review 意见做显式回应
- 对拒绝的建议给出理由和替代方案

### GPT Reviewer

plan 模式使用：

- prompt 模板：`../../prompts/dual-model-consensus-plan/gpt-review.md`

code 模式使用：

- prompt 模板：`../../prompts/dual-model-consensus-plan/gpt-code-review.md`

推荐 subagent：`.cursor/agents/gpt-reviewer.md`

GPT 必须：

- 只做 review，不直接改写主制品或代码
- 识别 `blocking`、`important`、`minor` 问题
- 给出具体修改计划
- 明确判断当前制品是否无需再修订即可接受

### 控制器

控制器就是当前会话中的父 agent。控制器必须：

- 收集并标准化输入
- 创建 topic 目录和 `brief.md`
- 根据制品类型选择对应的 prompt 模板
- 决定下一步调用哪个角色代理
- 显式把所需上下文传给 subagent
- 把每次输出保存到正确文件
- 在每一轮 GPT review 后执行收敛检查
- 在达到轮次上限时停止
- 输出 `final.md` 或 `disagreement-report.md`

不要把"是否继续下一轮"的决定权交给角色代理。循环控制只属于控制器。

## 计划模式控制器执行协议

当制品类型为 `plan` 时，按以下步骤执行：

1. 先把用户请求标准化写入 `brief.md`。
2. 在 `brief.md` 中记录执行元数据，包括：
   - topic slug
   - 制品类型：`plan`
   - 最大 review 轮次
   - 标准化后的任务描述
   - 执行模式：`automatic` 或 `manual-fallback`
   - 如果某一轮曾手动重跑，则记录 model-binding notes
3. 渲染首稿 prompt，包含：
   - `{{USER_TASK}}`
   - `{{ARTIFACT_TYPE}} = plan`
   - `{{TOPIC_SLUG}}`
   - `{{ROUND}} = 1`
   - `{{MAX_ROUNDS}}`
4. 调用 Claude 生成首稿。
5. 只把主制品正文保存为 `draft-r1.md`。
6. 渲染 GPT review prompt，包含：
   - 同一组任务元信息
   - `{{ARTIFACT_TYPE}} = plan`
   - `{{ROUND}} = 1`
   - `{{CURRENT_ARTIFACT}} = draft-r1.md`
7. 调用 GPT review 该文件。
8. 把 review 保存为 `review-r1.md`。
9. 运行 `reference.md` 中的完整收敛检查。
10. 如果检查通过，则把最新主制品正文写入 `final.md` 并停止。
11. 如果当前 GPT review 轮次已经达到上限，则渲染分歧报告 prompt，包含：
    - `{{USER_TASK}}`
    - `{{ARTIFACT_TYPE}} = plan`
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
14. 调用 Claude 根据最新制品和最新 review 进行修订。
15. 按要求的哨兵拆分 Claude 输出：
    - `<!-- BEGIN_RESPONSE -->` ... `<!-- END_RESPONSE -->`
    - `<!-- BEGIN_REVISION -->` ... `<!-- END_REVISION -->`
16. 拆分后移除哨兵注释。
17. 将响应正文保存为 `response-rN.md`。
18. 将修订后的主制品正文保存为 `revision-rN.md`。
19. 让 GPT review `revision-rN.md`，不要 review `response-rN.md`。
20. 重复以上过程，直到收敛或达到轮次上限。

## 代码模式控制器执行协议

当制品类型为 `code` 时，按以下步骤执行：

### 前提条件

- 项目必须是 git 仓库。控制器应在开始前检查，如果不是则提示用户先执行 `git init`。
- 工作区应当没有未提交的变更（clean working tree），以便准确捕获 diff。如果有未提交变更，建议用户先 commit 或 stash。

### 执行步骤

1. 先把用户请求标准化写入 `brief.md`。
2. 在 `brief.md` 中记录执行元数据，包括：
   - topic slug
   - 制品类型：`code`
   - 最大 review 轮次
   - 标准化后的任务描述
   - 执行模式：`automatic` 或 `manual-fallback`
   - git baseline（`git rev-parse HEAD` 的输出）
   - 如果某一轮曾手动重跑，则记录 model-binding notes
3. 记录 git baseline：执行 `git rev-parse HEAD` 保存当前 commit hash。
4. 渲染首稿 prompt（使用 `claude-code-draft.md`），包含：
   - `{{USER_TASK}}`
   - `{{ARTIFACT_TYPE}} = code`
   - `{{TOPIC_SLUG}}`
   - `{{ROUND}} = 1`
   - `{{MAX_ROUNDS}}`
5. 调用 Claude 执行代码修改。Claude 会直接修改代码文件，并返回变更摘要文本。
6. 捕获代码变更：执行 `git diff`（包含未暂存变更）获取完整 diff。
7. 将变更摘要 + 变更文件列表 + diff 组装并保存为 `draft-r1.md`。
8. 渲染 GPT code review prompt（使用 `gpt-code-review.md`），包含：
   - `{{USER_TASK}}`
   - `{{ARTIFACT_TYPE}} = code`
   - `{{TOPIC_SLUG}}`
   - `{{ROUND}} = 1`
   - `{{CODE_CHANGES}} = draft-r1.md 的内容（变更摘要 + diff）`
9. 调用 GPT review 代码变更。
10. 把 review 保存为 `review-r1.md`。
11. 运行 `reference.md` 中的代码模式收敛检查。
12. 如果检查通过，则将最终变更摘要 + diff 写入 `final.md` 并停止。
13. 如果当前 GPT review 轮次已经达到上限，则渲染分歧报告 prompt，传入相应上下文，保存为 `disagreement-report.md`。
14. 否则，渲染 Claude 代码修订 prompt（使用 `claude-code-revision.md`），包含：
    - `{{ROUND}} = 下一轮 review 的轮次号`
    - `{{CODE_CHANGES}} = 当前累积 diff`
    - `{{LATEST_REVIEW}} = 最新 review`
15. 调用 Claude 执行代码修订。Claude 会直接修改代码文件，并返回 review response 文本。
16. 将 Claude 返回的 review response 保存为 `response-rN.md`。
17. 重新捕获 `git diff` 获取更新后的累积变更。
18. 将更新后的变更摘要 + diff 保存为 `revision-rN.md`。
19. 渲染 GPT code review prompt，将更新后的 diff 作为 `{{CODE_CHANGES}}`。
20. 调用 GPT review 更新后的代码变更。
21. 把 review 保存为 `review-rN.md`。
22. 重复以上过程，直到收敛或达到轮次上限。

### code 模式与 plan 模式的关键差异

- 不使用哨兵拆分：Claude 修订时只返回 review response 文本，代码变更在文件系统中完成
- diff 由控制器捕获：通过 `git diff` 获取，而非从 Claude 输出中提取
- `draft-r1.md` / `revision-rN.md` / `final.md` 的内容是变更摘要 + diff，而非计划文档正文
- `response-rN.md` 直接取自 Claude 返回的文本，不需要从混合输出中拆分

## Prompt 渲染规则

控制器应把完整渲染后的 prompt 文本直接传给 subagent，而不是让 subagent 自己去加载模板。

每次调用 subagent 时都应明确提供：

- 工作流目的
- 当前轮次
- 制品类型（`plan` 或 `code`）
- 完整渲染后的 prompt
- 预期输出文件名
- 只有控制器负责写文件这一规则（code 模式下，Claude 负责写代码文件，控制器负责写跟踪文件）

由于 subagent 从干净上下文启动，绝不要假设它能看到此前对话历史。

### plan 模式变量

- `{{USER_TASK}}`、`{{ARTIFACT_TYPE}}`、`{{TOPIC_SLUG}}`、`{{ROUND}}`、`{{MAX_ROUNDS}}`
- `{{CURRENT_ARTIFACT}}`（GPT review 时传入当前计划文档正文）
- `{{PREVIOUS_ARTIFACT}}`、`{{LATEST_REVIEW}}`（Claude 修订时传入）

### code 模式变量

- `{{USER_TASK}}`、`{{ARTIFACT_TYPE}}`、`{{TOPIC_SLUG}}`、`{{ROUND}}`、`{{MAX_ROUNDS}}`
- `{{CODE_CHANGES}}`（GPT review 和 Claude 修订时传入，包含变更摘要 + git diff）
- `{{LATEST_REVIEW}}`（Claude 修订时传入）

## 收敛规则

### 通用条件

以下条件在 plan 和 code 模式下都适用：

- GPT review 明确认为当前制品 acceptable，且没有 `blocking` 问题
- Claude 已经接受所有必要修改，或对剩余分歧说明了其 non-blocking 理由
- 如果 `review-r1.md` 已经接受 `draft-r1.md`，流程可以直接收敛，无需生成任何 `response-rN.md` 或 `revision-rN.md`

### plan 模式额外条件

- 最新主制品中没有未处理占位，如 `TODO`、`TBD`、`待确认`

### code 模式额外条件

- 不检查 `TODO`/`TBD` 占位（代码中的 TODO 注释可能是合理的）

控制器在写入 `final.md` 之前，还必须执行 `reference.md` 中的全部收敛检查项。

## 轮次上限

默认最大 review 轮次为 `3`，除非用户另行指定。

如果达到轮次上限仍未收敛：

- 立即停止循环
- 使用 `../../prompts/dual-model-consensus-plan/disagreement-report.md` 生成 `disagreement-report.md`
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

在 code 模式下，`final.md` 和跟踪文件（`draft-r1.md`、`revision-rN.md`）包含的是变更摘要 + diff，而非计划文档正文。实际的代码变更已经在工作区的文件中。

## 补充说明

请阅读 `reference.md` 获取：

- 制品章节结构要求
- review 严重级别定义
- 控制器检查表
- 文件命名规则
- 示例流程序列
