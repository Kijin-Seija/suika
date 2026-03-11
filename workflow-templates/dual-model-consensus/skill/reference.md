# 双模型共识工作流参考规范

## 目的

这份 reference 定义双模型共识工作流的共享契约。

应与 `SKILL.md`、`prompts/` 下的 prompt 模板，以及 `agents/` 下的角色说明一起使用。

## 推荐目录结构

```text
.cursor/plans/<topic-slug>/
  brief.md
  draft-r1.md
  review-r1.md
  response-r2.md
  revision-r2.md
  review-r2.md
  response-r3.md
  revision-r3.md
  review-r3.md
  final.md
  disagreement-report.md
```

只创建本次实际运行所需的文件。

## Brief 结构

`brief.md` 至少应记录：

- `topic-slug`
- `artifact-type`: `plan | code`
- `max-review-rounds`
- `execution-mode`: `automatic` 或 `manual-fallback`
- `model-binding-notes`
- 原始任务
- 标准化后的任务

code 模式还应记录：

- `git-baseline`: `git rev-parse HEAD` 的输出

如果某一轮因模型绑定未按预期生效而重跑，应把情况记入 `model-binding-notes`。

## 控制器隔离原则

控制器是协议执行者，不是作者、编辑或 reviewer。控制器只允许执行以下机械操作：

- 渲染 prompt
- 调度角色代理
- 原样保存角色输出
- 哨兵拆分
- 解析固定结构字段用于收敛检查
- 执行 `git diff`、`git add -N` 等变更捕获动作
- 在输出不合规时重试同一角色，或停止流程

控制器绝对禁止：

- 改写 `draft-r1.md`、`revision-rN.md`、`final.md` 的业务正文
- 根据 review 自行修订计划文档或代码
- 替作者补写遗漏章节、补齐 response 或润色主制品
- 将 reviewer findings 先做语义重组、降级、合并后再转述给作者
- 在角色输出不完整时“热心兜底”补正文

除非只是做引用式摘录，否则控制器不得把原始输入改写成新的业务摘要。

## 计划模式主制品结构

当 `artifact-type` 为 `plan` 时，主制品应采用以下结构：

```markdown
# <标题>

## 任务理解

## 目标

## 范围

## 假设

## 风险

## 建议方案

## 验证方式

## 开放问题

## Execution Steps
```

## 代码模式制品结构

当 `artifact-type` 为 `code` 时，跟踪文件（`draft-r1.md`、`revision-rN.md`、`final.md`）采用以下结构：

```markdown
# 代码变更摘要

## 变更概述
<Claude 返回的变更说明>

## 变更文件
- <文件路径>: <修改说明>
- <文件路径>: <修改说明>

## Diff
\`\`\`diff
<git diff 输出>
\`\`\`
```

实际的代码变更在工作区的文件中，跟踪文件仅作记录用途。

`response-rN.md` 在 code 模式下直接包含 Claude 对 review 的逐条回应，不需要从混合输出中拆分：

```markdown
# 第 <N> 轮修订响应

## Review Response
1. <问题标题>
   - decision: accepted | rejected | partially-accepted
   - action: <做了什么修改>
   - rationale: <如果不是完全接受，这里必须解释>
```

## Review 输出格式

### plan 模式

GPT review 应采用以下结构：

```markdown
# 第 <N> 轮 Review

## 结论
- status: acceptable | revision-required
- blocking-issues: <count>
- important-issues: <count>
- minor-issues: <count>

## Findings
1. <问题标题>
   - severity: blocking | important | minor
   - rationale: <为什么重要>
   - requested change: <应该如何修改>

## 修改计划
1. <具体修改>
2. <具体修改>

## 接受性检查
- acceptable-without-further-revision: yes | no
```

### code 模式

GPT code review 采用类似结构，但增加 `location` 字段：

```markdown
# 第 <N> 轮 Code Review

## 结论
- status: acceptable | revision-required
- blocking-issues: <count>
- important-issues: <count>
- minor-issues: <count>

## Findings
1. <问题标题>
   - severity: blocking | important | minor
   - location: <文件路径:行号或函数名>
   - rationale: <为什么重要>
   - requested change: <应该如何修改>

## 修改计划
1. <具体修改>
2. <具体修改>

## 接受性检查
- acceptable-without-further-revision: yes | no
```

## Claude 修订输出格式

### plan 模式

Claude 修订阶段应产出两个逻辑结果：

- 一个供 `response-rN.md` 使用的 review 响应摘要
- 一个供 `revision-rN.md` 使用的干净计划正文

控制器必须把它们拆分成两个文件，让 GPT 下一轮只 review 更新后的计划正文。原始 Claude 输出必须通过固定哨兵拆分，拆分完成后再移除哨兵注释，不要把哨兵写入最终文件。

#### `response-rN.md`

```markdown
# 第 <N> 轮修订响应

## Review Response
1. <问题标题>
   - decision: accepted | rejected | partially-accepted
   - action: <做了什么修改>
   - rationale: <如果不是完全接受，这里必须解释>
```

#### `revision-rN.md`

```markdown
# <更新后的标题>

## 任务理解

## 目标

## 范围

## 假设

## 风险

## 建议方案

## 验证方式

## 开放问题

## Execution Steps
```

### code 模式

Claude 修订阶段只返回 review response 文本。代码变更在文件系统中直接完成，控制器通过 `git diff` 捕获。

- `response-rN.md`：Claude 返回的 review response（与 plan 模式格式相同）
- `revision-rN.md`：由控制器组装，包含更新后的变更摘要 + git diff

不使用哨兵拆分。

## 推荐上下文传递策略

控制器可以减少无关噪音，但不能通过自行总结来改变语义边界。优先传原文、原始 diff 和引用式摘录，而不是控制器撰写的紧凑摘要。

### `CURRENT_ARTIFACT` + `LATEST_REVIEW`（plan 模式）

用于 `plan` 模式的 Claude 修订轮。控制器应传入：

- 最新主制品原文
- 最新 review 原文

如果 token 受限，允许做引用式摘录，但必须满足：

- 摘录内容来自原始主制品或原始 review
- 摘录时不改写原意，不合并多条 finding 为一条新结论
- 未展示部分只能声明“其余部分保持原样”，不能补写控制器自己的解释

### `CODE_REVIEW_CONTEXT`（code 模式）

用于 `code` 模式的 GPT review 和 Claude 修订轮。推荐只包含：

- 自上一轮 review 以来的增量 diff
- 文件路径列表
- 仅在 diff 不足以判断正确性时附带的原始关键代码片段

避免默认重复传“变更摘要 + 全量 diff + 变更后文件全文”三份等价信息。
禁止直接把 `draft-r1.md`、`revision-rN.md` 或 `final.md` 的完整正文原样塞进 `CODE_REVIEW_CONTEXT`。这些文件是落盘跟踪材料，不是 reviewer 或修订轮的输入格式。
同样禁止在 `CODE_REVIEW_CONTEXT` 中加入控制器自己撰写的语义摘要、风险判断或修复建议。

### 分歧报告上下文

推荐包含以下原文或引用式摘录：

- `LATEST_ARTIFACT`
- `LATEST_REVIEW`
- `LATEST_CLAUDE_RESPONSE`
- `UNRESOLVED_ISSUES`

历史 review 与 response 文件应保留在磁盘中供人工追溯，但不应默认整包注入到分歧报告 prompt。控制器可以按问题逐条引用原文，但不应先改写出一份新的业务总结。

## 最小化控制器渲染模板

下面给出一组可直接复用的最小模板。目标是让控制器只向 subagent 发送“渲染后的 prompt + 极少量运行说明”，并通过原文与引用式摘录传递上下文，而不是自己撰写业务摘要。

### 通用调用外壳

控制器调用 subagent 时，优先只传：

```markdown
stage: <draft | review | revision | disagreement>
prompt:
<完整渲染后的 prompt>
```

只有当 prompt 本身没有覆盖运行约束时，才额外补一小段说明，例如：

```markdown
controller_notes:
- 由控制器负责写 `.cursor/plans/...` 跟踪文件
- code 模式下由 Claude 直接修改工作区文件
```

### `CURRENT_ARTIFACT` + `LATEST_REVIEW` 模板

用于 `plan` 模式的 Claude 修订轮：

```markdown
# Current Artifact
<最新主制品原文；如有 token 限制，仅做引用式摘录>

# Latest Review
<最新 review 原文；如有 token 限制，仅做引用式摘录>
```

不要把原文改写成控制器自己的小结、章节骨架重述或 findings 合并版。

### `CODE_REVIEW_CONTEXT` 模板

用于 `code` 模式的 GPT review 和 Claude 修订轮：

````markdown
# Code Review Context

## Incremental Diff
```diff
<只放自上一轮 review 以来的增量 diff>
```

## File Notes
- `path/to/file1`
- `path/to/file2`

## Extra Snippets
### `path/to/file1`
```ts
<只有当 diff 无法独立说明语义时，才补关键片段>
```
````

如无必要，省略 `Extra Snippets` 整段，不要默认附带变更后全文。
不要把 `draft-r1.md`、`revision-rN.md` 或 `final.md` 的完整 Markdown 原样粘贴到这里；如果需要引用其中信息，必须先抽取为增量 diff、文件路径列表或必要片段。
除文件路径列表外，不要添加控制器撰写的说明文字。

### 分歧报告摘要模板

用于达到最大轮次后的 `disagreement-report.md` 渲染：

```markdown
LATEST_ARTIFACT
<最新主制品原文或必要摘录>

LATEST_REVIEW
<最新 review 原文或必要摘录>

LATEST_CLAUDE_RESPONSE
<最新 response 原文或 none>

UNRESOLVED_ISSUES
1. <问题标题>
   - severity: blocking | important
   - gpt_position: <引用 GPT 原文>
   - claude_position: <引用 Claude 原文或 none>
   - gap: <仍未收敛的核心分歧>
   - suggested_human_decision: <建议的人类决策>
```

### 渲染示例

#### `plan` 修订轮

```markdown
task: 为新工作流设计 token 优化方案
meta: artifact=plan topic=token-optimization round=2
current_artifact:
<当前主制品原文或引用式摘录>
latest_review:
<最新 review 原文或引用式摘录>
```

#### `code` review 轮

```markdown
task: 为工作流模板引入增量上下文打包
meta: artifact=code topic=incremental-context round=2
code_review_context:
<按 `CODE_REVIEW_CONTEXT` 模板渲染后的内容>
```

#### 分歧报告轮

```markdown
task: 为工作流模板引入增量上下文打包
meta: artifact=code topic=incremental-context max_rounds=3
latest_artifact:
<按摘要模板渲染后的内容>
latest_review:
<按摘要模板渲染后的内容>
latest_claude_response:
<按摘要模板渲染后的内容>
unresolved_issues:
<按摘要模板渲染后的内容>
```

## 严重级别规则

- `blocking`: 阻止执行、导致功能错误、或留下未解决的核心问题
- `important`: 会实质提升正确性或质量，但不会直接使整个变更失效
- `minor`: 文案、润色或可选优化

只有 `blocking` 项必须全部解决，流程才能收敛。

## 控制器检查表

控制器每次推进状态前都应执行以下检查：

### 在生成 `brief.md` 之后

- 输入完整：任务、topic slug、制品类型、最大轮次
- topic slug 使用 lowercase kebab-case
- `brief.md` 已记录标准化任务和所选参数
- `brief.md` 已记录执行模式和模型绑定备注
- 制品类型为 `plan` 或 `code`

### 在生成 `draft-r1.md` 之前（plan 模式）

- 首轮 Claude prompt 使用了正确轮次号
- `ARTIFACT_TYPE` 为 `plan`
- 使用 `claude-analysis-planner.md` 模板

### 在生成 `draft-r1.md` 之前（code 模式）

- 项目是 git 仓库
- 工作区没有未提交变更（建议 clean working tree）
- git baseline 已记录到 `brief.md`
- 首轮 Claude prompt 使用了正确轮次号
- `ARTIFACT_TYPE` 为 `code`
- 使用 `claude-code-draft.md` 模板
- 如果本轮新增了未跟踪文件，控制器会先执行 `git add -N <path>`，确保后续 `git diff` 能捕获新文件内容

### 在生成每个 `review-rN.md` 之前（plan 模式）

- 发送给 GPT 的文件只能是 `draft-r1.md` 或 `revision-rN.md`
- 绝不能把 `response-rN.md` 发送给 GPT
- 渲染后的 GPT prompt 只包含当前主制品正文和标准化任务元信息
- prompt 中轮次号与 review 文件名一致
- 使用 `gpt-review.md` 模板

### 在生成每个 `review-rN.md` 之前（code 模式）

- 已执行 `git diff` 捕获最新变更
- 若变更包含未跟踪文件，已先执行 `git add -N <path>`
- 发送给 GPT 的内容优先是增量 diff + 文件路径列表，只有在必要时才补充原始关键片段
- 没有把 `draft-r1.md`、`revision-rN.md` 或 `final.md` 的完整正文直接转发给 GPT
- prompt 中轮次号与 review 文件名一致
- 使用 `gpt-code-review.md` 模板

### 在生成每个 `response-rN.md` 和 `revision-rN.md` 之前（plan 模式）

- 渲染后的 Claude 修订 prompt 包含最新主制品原文和最新 review 原文
- 如果因 token 限制只能摘录，则摘录必须是引用式的，不得改写原意
- Claude 被明确要求逐条回应每个 finding
- 控制器已准备好通过固定哨兵拆分响应日志和修订后正文，并在保存前去掉哨兵

### 在生成每个 `response-rN.md` 和 `revision-rN.md` 之前（code 模式）

- 渲染后的 Claude 修订 prompt 包含 `CODE_REVIEW_CONTEXT`
- `CODE_REVIEW_CONTEXT` 优先包含自上一轮 review 以来的原始增量 diff、文件路径列表和必要的原始代码片段，而不是当前累积全量 diff
- `CODE_REVIEW_CONTEXT` 不是 `draft-r1.md`、`revision-rN.md` 或 `final.md` 的完整正文转发
- `CODE_REVIEW_CONTEXT` 不包含控制器自行撰写的语义摘要、修复建议或风险判断
- 渲染后的 Claude 修订 prompt 包含最新 GPT review 正文
- Claude 被明确要求逐条回应每个 finding
- Claude 返回的文本直接保存为 `response-rN.md`（不需要哨兵拆分）
- 控制器在 Claude 完成修订后执行 `git diff` 捕获更新后变更；若修订中新增了未跟踪文件，已先执行 `git add -N <path>`；随后组装为 `revision-rN.md`

### 在生成 `final.md` 之前（通用）

- 最新 GPT verdict 为 `acceptable`
- 最新 GPT review 的 `blocking-issues: 0`
- 如果被接受的是 `draft-r1.md`，则不要求 Claude response 文件
- 否则，最新 Claude response 文件必须回应上一轮 GPT review 的每一条问题

### 在生成 `final.md` 之前（plan 模式额外检查）

- 最新主制品中没有未解决占位，如 `TODO`、`TBD`、`待确认`

### 在生成 `final.md` 之前（code 模式额外检查）

- `git diff` 输出不为空（确实有代码变更）

### 在生成 `disagreement-report.md` 之前

- 已达到配置的轮次上限
- 最新主制品和最新 review 都可用
- 渲染后的 disagreement prompt 包含最新主制品原文或摘录、最新 review 原文或摘录、最新 Claude response 原文或 none，以及未解决问题列表
- 如果没有发生 Claude 修订轮次，则 `LATEST_CLAUDE_RESPONSE` 明确传 `none`，不得由控制器补写一份新的 Claude 立场总结
- 未解决问题可以从保存下来的轮次历史中追溯

## 收敛检查表

### 通用条件

只有同时满足以下条件，控制器才可以写入 `final.md`：

- 最新 GPT verdict 为 `acceptable`
- 最新 GPT review 的 `blocking-issues: 0`
- 如果被接受的是 `draft-r1.md`，则不要求 Claude response 文件
- 否则，最新 Claude response 文件必须回应上一轮 GPT review 的所有问题

### plan 模式额外条件

- 最新主制品中没有未解决占位，如 `TODO`、`TBD`、`待确认`

### code 模式额外条件

- 不检查 `TODO`/`TBD` 占位（代码中的 TODO 注释可能是合理的）
- `git diff` 输出不为空

## 失败处理

如果角色输出不满足契约，控制器只能重试同一角色或停止流程：

- 缺少哨兵、章节、严重级别或必需字段时，不得由控制器补写
- 缺少逐条回应时，不得由控制器代写 `response-rN.md`
- `code` 模式下 reviewer 指出了应修改的代码，但 writer 未落实时，不得由控制器直接改代码
- 多次重试后仍失败时，应停止在当前轮，并保留已有文件供人工接管

## 分歧报告格式

如果流程在未收敛的情况下停止，应使用以下结构（plan 和 code 模式共用）：

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

## 文件命名规则

- `<topic-slug>` 使用 lowercase kebab-case
- 首个 Claude 输出固定命名为 `draft-r1.md`
- Claude 对上一轮 review 的显式回应命名为 `response-rN.md`
- 后续 Claude 主制品命名为 `revision-rN.md`
- 每一轮 GPT review 命名为 `review-rN.md`
- 只有在确认收敛后才能使用 `final.md`
- 轮次按 GPT review 文件计数，而不是按 Claude 修订次数计数

plan 和 code 模式使用相同的文件命名规则，区别仅在文件内容。

## 示例序列

### plan 模式 - 首轮直接收敛

```text
brief.md
draft-r1.md
review-r1.md
final.md
```

### plan 模式 - 多轮修订后收敛

```text
brief.md
draft-r1.md
review-r1.md
response-r2.md
revision-r2.md
review-r2.md
final.md
```

### plan 模式 - 多轮后到上限停止

```text
brief.md
draft-r1.md
review-r1.md
response-r2.md
revision-r2.md
review-r2.md
response-r3.md
revision-r3.md
review-r3.md
disagreement-report.md
```

### code 模式 - 首轮直接收敛

```text
brief.md              (含 git-baseline)
draft-r1.md            (变更摘要 + diff)
review-r1.md           (code review)
final.md               (最终变更摘要 + diff)
```

### code 模式 - 多轮修订后收敛

```text
brief.md              (含 git-baseline)
draft-r1.md            (变更摘要 + diff)
review-r1.md           (code review)
response-r2.md         (Claude 对 review 的响应)
revision-r2.md         (更新后变更摘要 + diff)
review-r2.md           (code review)
final.md               (最终变更摘要 + diff)
```

## 实践说明

- 主制品与 review 文档要分开保存
- Claude 的修订响应与修订后正文要分开保存
- 不要让 GPT 直接重写主制品或代码
- 不要让 Claude 跳过对 review 项的显式回应
- 如果 `review-r1.md` 已经接受 `draft-r1.md`，允许直接收敛
- 到达配置轮次上限后必须停止，不要无限循环
- subagent 的 `model` 设置属于优先运行时绑定，不是绝对保证
- code 模式下，确保 git 工作区初始状态干净，以便准确捕获 diff
- code 模式下，如果新增文件，必须先用 `git add -N` 将其纳入 diff，再交给 reviewer
