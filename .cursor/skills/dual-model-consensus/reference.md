# 双模型共识参考规范

## 目的

这份 reference 定义双模型共识工作流的共享契约。

应与 `SKILL.md`、`.cursor/prompts/dual-model-consensus/` 下的 prompt 模板，以及 `.cursor/agents/` 下的项目级 subagent 一起使用。

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
- `artifact-type`
- `max-review-rounds`
- `execution-mode`: `automatic` 或 `manual-fallback`
- `model-binding-notes`
- 原始任务
- 标准化后的任务

如果某一轮因模型绑定未按预期生效而重跑，应把情况记入 `model-binding-notes`。

## 主制品结构

无论是 analysis 还是 plan，主制品都应采用以下结构：

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
```

如果制品类型是 implementation plan，还应补充：

```markdown
## Execution Steps
```

## Review 输出格式

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

## Claude 修订输出格式

Claude 修订阶段应产出两个逻辑结果：
- 一个供 `response-rN.md` 使用的 review 响应摘要
- 一个供 `revision-rN.md` 使用的干净主制品正文

控制器必须把它们拆分成两个文件，让 GPT 下一轮只 review 更新后的主制品。原始 Claude 输出必须通过固定哨兵拆分，拆分完成后再移除哨兵注释，不要把哨兵写入最终文件。

### `response-rN.md`

```markdown
# 第 <N> 轮修订响应

## Review Response
1. <问题标题>
   - decision: accepted | rejected | partially-accepted
   - action: <做了什么修改>
   - rationale: <如果不是完全接受，这里必须解释>
```

### `revision-rN.md`

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
```

## 严重级别规则

- `blocking`: 阻止执行、导致范围错误、或留下未解决的核心矛盾
- `important`: 会实质提升正确性或清晰度，但不会直接使整份文档失效
- `minor`: 文案、润色或可选优化

只有 `blocking` 项必须全部解决，流程才能收敛。

## 控制器检查表

控制器每次推进状态前都应执行以下检查：

### 在生成 `draft-r1.md` 之前

- 输入完整：任务、制品类型、topic slug、最大轮次
- topic slug 使用 lowercase kebab-case
- `brief.md` 已记录标准化任务和所选参数
- `brief.md` 已记录执行模式和模型绑定备注
- 首轮 Claude prompt 使用了正确轮次号

### 在生成每个 `review-rN.md` 之前

- 发送给 GPT 的文件只能是 `draft-r1.md` 或 `revision-rN.md`
- 绝不能把 `response-rN.md` 发送给 GPT
- 渲染后的 GPT prompt 只包含当前主制品正文和标准化任务元信息
- prompt 中轮次号与 review 文件名一致

### 在生成每个 `response-rN.md` 和 `revision-rN.md` 之前

- 渲染后的 Claude 修订 prompt 包含完整上一版主制品正文
- 渲染后的 Claude 修订 prompt 包含最新 GPT review 正文
- Claude 被明确要求逐条回应每个 finding
- 控制器已准备好通过固定哨兵拆分响应日志和修订后正文，并在保存前去掉哨兵

### 在生成 `final.md` 之前

- 最新 GPT verdict 为 `acceptable`
- 最新 GPT review 的 `blocking-issues: 0`
- 最新主制品中没有未解决占位，如 `TODO`、`TBD`、`待确认`
- 如果被接受的是 `draft-r1.md`，则不要求 Claude response 文件
- 否则，最新 Claude response 文件必须回应上一轮 GPT review 的每一条问题

### 在生成 `disagreement-report.md` 之前

- 已达到配置的轮次上限
- 最新主制品和最新 review 都可用
- 渲染后的 disagreement prompt 包含 latest artifact、latest review、latest Claude response、review history 和 Claude response history
- 如果没有发生 Claude 修订轮次，则 `LATEST_CLAUDE_RESPONSE` 与 `CLAUDE_RESPONSE_HISTORY` 统一渲染为 `none`
- 如果 `LATEST_CLAUDE_RESPONSE` 是 `none`，则 `Claude position` 从最新主制品推断，并显式标注为 inferred
- 未解决问题可以从保存下来的轮次历史中追溯

## 收敛检查表

只有同时满足以下条件，控制器才可以写入 `final.md`：
- 最新 GPT verdict 为 `acceptable`
- 最新 GPT review 的 `blocking-issues: 0`
- 最新主制品中没有未解决占位，如 `TODO`、`TBD`、`待确认`
- 如果被接受的是 `draft-r1.md`，则不要求 Claude response 文件
- 否则，最新 Claude response 文件必须回应上一轮 GPT review 的所有问题

## 分歧报告格式

如果流程在未收敛的情况下停止，应使用以下结构：

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

## 示例序列

首轮直接收敛：

```text
brief.md
draft-r1.md
review-r1.md
final.md
```

多轮修订后收敛：

```text
brief.md
draft-r1.md
review-r1.md
response-r2.md
revision-r2.md
review-r2.md
final.md
```

多轮后到上限停止：

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

首轮 review 即到上限停止：

```text
brief.md
draft-r1.md
review-r1.md
disagreement-report.md
```

## 实践说明

- 主制品与 review 文档要分开保存
- Claude 的修订响应与修订后正文要分开保存
- 不要让 GPT 直接重写主制品
- 不要让 Claude 跳过对 review 项的显式回应
- 如果 `review-r1.md` 已经接受 `draft-r1.md`，允许直接收敛
- 到达配置轮次上限后必须停止，不要无限循环
- subagent 的 `model` 设置属于优先运行时绑定，不是绝对保证

