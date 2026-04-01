# Reviewer 工作流参考规范

## 目的

这份 reference 定义 reviewer 工作流的共享契约。

该工作流的角色边界如下：

- Claude：完成用户主任务，并根据 review 结果修订代码或文档
- 安装后的 launcher `.claude/skills/reviewer/bin/reviewer-run.sh`：负责在当前工作区启动外部 Codex reviewer 子进程
- 外部 Codex reviewer 子进程：只负责 review，返回结构化结论与问题列表
- 控制器：负责调度、落盘、解析、收敛判断和停止条件，不参与业务正文创作或改写

## 推荐目录结构

```text
<plans-root>/<topic-slug>/
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
  dispute-report.md
```

只创建本次实际运行所需的文件。

## Brief 结构

`brief.md` 至少应记录：

- `topic-slug`
- `artifact-type`: `code | doc`
- `max-review-rounds`
- `current-round`
- `execution-mode`: `explicit-reviewer-skill`
- 原始任务
- 标准化后的任务

当 `artifact-type` 为 `code` 时，还应记录：

- `git-baseline`: `git rev-parse HEAD` 的输出

## 控制器隔离原则

控制器是协议执行者，不是作者，也不是 reviewer。控制器只允许执行以下机械操作：

- 标准化输入
- 渲染 prompt
- 调用 `.claude/skills/reviewer/bin/reviewer-run.sh`
- 确保 launcher 使用 `.claude/skills/reviewer/schemas/codex-review.schema.json`
- 确保外部 reviewer 以 `codex exec -C <project> -s read-only` 运行在与主 agent 相同的工作目录和工作区状态中
- 原样保存角色输出
- 解析固定 JSON 字段用于收敛检查
- 捕获 `git diff`、文件路径列表和必要片段
- 在输出不合规时要求同一角色重试，或停止流程

控制器绝对禁止：

- 改写 `draft-r1.md`、`revision-rN.md`、`final.md` 的业务正文
- 代替 Claude 修改代码、补写文档或润色主制品
- 将 Codex findings 先合并、降级或重写后再转述给 Claude
- 在 Codex JSON 缺字段时脑补默认值
- 在 Claude 未落实修改时假装问题已解决

## 制品结构

### code 模式

当 `artifact-type` 为 `code` 时，`draft-r1.md`、`revision-rN.md` 和 `final.md` 采用以下结构：

````markdown
# 代码变更摘要

## 变更概述
<Claude 返回的变更说明>

## 变更文件
- <文件路径>: <修改说明>
- <文件路径>: <修改说明>

## Diff
```diff
<git diff 输出>
```
````

实际代码变更发生在工作区文件中，跟踪文件只用于记录和传递 review 上下文。

Codex reviewer 必须直接读取当前工作区中的这些文件与未提交改动；如果切到独立 worktree、临时副本或隔离目录，会看不到主 agent 的最新改动，从而导致错误的未通过结论。因此 reviewer 运行环境必须与主 agent 保持一致。

这意味着 reviewer 不能由 Claude 内部 subagent 冒充，必须通过 launcher 在当前项目目录里启动真实的外部 `codex exec` 子进程。

### doc 模式

当 `artifact-type` 为 `doc` 时，`draft-r1.md`、`revision-rN.md` 和 `final.md` 保存当前文档正文，必要时可以附带：

- 任务目标
- 约束条件
- 验收标准

如果文档过长，只允许做引用式摘录，并保留足以恢复原文的文件路径或上下文线索。

## Codex Review JSON 契约

每个 `review-rN.md` 都必须保存 Codex 原样返回的 JSON。launcher 使用的 schema 文件路径固定为 `.claude/skills/reviewer/schemas/codex-review.schema.json`。推荐结构如下：

```json
{
  "status": "pass | fail",
  "summary": "string",
  "issues": [
    {
      "id": "string",
      "severity": "blocking | important | minor",
      "description": "string",
      "fix_suggestion": "string",
      "location": "string"
    }
  ],
  "next_action": "approve | revise | human_judgment"
}
```

### JSON 约束

- `status = pass` 时：
  - `issues` 必须为空，或只允许 non-blocking 备注
  - `next_action` 应为 `approve`
- `status = fail` 时：
  - `issues` 必须存在且至少包含一个问题
  - 每个问题都必须包含 `description`、`severity`、`fix_suggestion`
  - `next_action` 应为 `revise` 或 `human_judgment`
- `severity` 只能是 `blocking`、`important`、`minor`

如果 JSON 缺字段、字段非法，或结论与问题列表矛盾，控制器只能要求 Codex 重试该轮，不能自行修复协议错误。

## Claude 响应格式

每个 `response-rN.md` 都应包含 Claude 对上一轮 findings 的逐条回应：

```markdown
# 第 <N> 轮修订响应

## Review Response
1. <issue-id 或问题标题>
   - decision: accepted | questioned | rejected
   - action: <做了什么修改；若未修改则写 none>
   - rationale: <为什么接受、质疑或拒绝>
   - open-question: <如有疑问则填写，否则写 none>
```

规则：

- `accepted`：问题属实，Claude 必须落实修改
- `questioned`：Claude 对前提、上下文或建议存在疑问，必须显式写出疑问点
- `rejected`：Claude 认为问题不成立，必须给出理由

## 上下文传递策略

### code 模式

传给 Codex 的 review 上下文优先包含：

- 原始增量 `git diff`
- 变更文件路径列表
- 仅在 diff 不足以解释语义时附带的原始关键代码片段
- 若存在上一轮 review，则附上：
  - 上一轮 `review-rN.md`
  - 当前轮 `response-r(N+1).md`

不要只把 Claude 的口头总结发给 Codex。Codex 必须能同时看到最新实际变更和 Claude 对上一轮问题的回应。

### doc 模式

传给 Codex 的 review 上下文优先包含：

- 当前文档正文
- 任务目标、约束、验收标准
- 若存在上一轮 review，则附上：
  - 上一轮 `review-rN.md`
  - 当前轮 `response-r(N+1).md`

控制器可以做引用式摘录，但不得改写成新的业务摘要。

## 收敛规则

只有同时满足以下条件，控制器才可以写入 `final.md`：

- 最新 Codex `status` 为 `pass`
- 最新 Codex `next_action` 为 `approve`
- 不存在未解决的 `blocking` 或 `important` 问题
- 如果存在上一轮失败记录，则 Claude 已对上一轮问题做出逐条回应

`minor` 问题不阻止流程收敛，但如果 Codex 仍给出 `status = fail`，则仍按未通过处理。

## 轮次上限

默认最大 review 轮次为 `5`，除非用户另行指定。

轮次按 Codex review 文件计数：

- `review-r1.md`
- `review-r2.md`
- `review-r3.md`
- ...

如果达到最大轮次仍未收敛：

- 立即停止循环
- 生成 `dispute-report.md`
- 只列出仍未解决的 `blocking` 或 `important` 分歧
- 将最终裁决交给人类，而不是由控制器擅自决定

## 失败处理

- 如果 Codex 返回无法解析的 JSON，控制器只能要求 Codex 重试该轮
- 如果 Codex 输出 JSON 合法但字段不符合契约，控制器只能要求 Codex 重试该轮
- 如果 Claude 没有逐条回应上一轮问题，控制器只能要求 Claude 重试该轮
- 如果 Claude 声称已修复，但实际 artifact 未体现，控制器不得代为修复
- 多次重试后仍不满足契约时，流程应停止，并保留已有文件供人工接管

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
   - severity:
   - codex-position:
   - claude-position:
   - why-still-unresolved:
   - suggested-human-decision:

## 建议下一步
- <一个具体的人类动作>
```

## 严重级别规则

- `blocking`: 阻止正确交付、导致功能错误、或保留核心缺陷
- `important`: 实质影响质量或正确性，但不一定完全阻止交付
- `minor`: 可选改进、措辞问题或非关键优化

只有 `blocking` 和 `important` 问题都已解决，流程才应被视为稳定通过。

## 文件命名规则

- `<topic-slug>` 使用 lowercase kebab-case
- 首次落盘制品固定为 `draft-r1.md`
- Claude 对上一轮 findings 的回应命名为 `response-rN.md`
- Claude 更新后的制品命名为 `revision-rN.md`
- 每一轮 Codex review 命名为 `review-rN.md`
- 只有在确认收敛后才能写入 `final.md`
- 轮次按 Codex review 文件计数，而不是按 Claude 修订次数计数
