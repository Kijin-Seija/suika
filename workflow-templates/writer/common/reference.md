# 实现闭环工作流参考规范

## 目的

这份 reference 定义 `writer` 的共享契约。

角色边界如下：

- Codex：控制器 + reviewer
- Writer CLI：实现者 + 修订者，可选 `claude` 或 `codex`
- Launcher：协议执行器，负责命令调用、文件落盘、JSON 校验与收敛判断

## 适用范围

该工作流只适用于 `code` 任务：

- 实现功能
- 修复 bug
- 做受约束的重构

不适用于：

- 计划文档
- 需求分析
- 纯说明文档

## 推荐目录结构

```text
.codex/plans/<topic-slug>/
  brief.md
  draft-r1.md
  review-r1.json
  writer-handoff-r2.md
  response-r2.json
  revision-r2.md
  review-r2.json
  writer-handoff-r3.md
  response-r3.json
  revision-r3.md
  review-r3.json
  final.md
  dispute-report.md
```

只创建本次实际运行所需的文件。

## Brief 结构

`brief.md` 至少应记录：

- `topic-slug`
- `artifact-type: code`
- `max-review-rounds`
- `current-round`
- `execution-mode: writer`
- 原始任务
- 标准化后的任务
- `git-baseline`
- `writer`
- `claude-bin`
- `codex-bin`

## 控制器职责

Launcher 作为控制器时，只允许执行以下机械工作：

- 标准化输入
- 生成和调用 prompt
- 原样保存 Claude/Codex 输出
- 校验 JSON schema
- 采集 `git diff`
- 判断是否收敛
- 达到上限时生成争议报告

控制器禁止：

- 代替 writer 改代码
- 擅自改写 Codex findings 后再转给 writer
- 在 JSON 不合法时脑补字段
- 在 writer 未响应所有问题时强行推进下一轮

## 制品结构

`draft-r1.md`、`revision-rN.md` 和 `final.md` 采用以下结构：

````markdown
# 代码变更摘要

## 变更概述
<Claude summary>

## 验证
<Claude verification>

## 变更文件
- <文件路径>: <修改说明>

## Diff
```diff
<git diff 输出>
```
````

实际代码变更发生在工作区文件中，Markdown 只是审查上下文快照。

`writer-handoff-rN.md` 是给修订轮 writer 用的精简上下文，应该优先包含：

- 用户任务
- 最新 review 的 issue 摘要
- 上一轮 writer 的 summary、verification、changed_files
- 如果存在，则包含上一轮对 issue 的 decisions
- 明确提醒 writer 非必要不要再读取带完整 diff 的 artifact

## JSON 契约

### Writer 首轮输出

writer 首轮实现返回 JSON，schema 位于：

- `schemas/claude-draft.schema.json`

关键字段：

- `summary`
- `verification`
- `changed_files`
- `questions`

### Writer 修订输出

writer 修订返回 JSON，schema 位于：

- `schemas/claude-response.schema.json`

关键字段：

- `summary`
- `verification`
- `changed_files`
- `responses`
- `remaining_questions`

其中 `responses[*].decision` 只能是：

- `accepted`
- `questioned`
- `rejected`

### Codex 审查输出

Codex review 返回 JSON，schema 位于：

- `schemas/codex-review.schema.json`

关键字段：

- `status`
- `summary`
- `issues`
- `next_action`

其中：

- `status`: `pass | fail`
- `severity`: `blocking | important | minor`
- `next_action`: `approve | revise | human_judgment`

## 收敛规则

只有同时满足以下条件，流程才可以写入 `final.md`：

- 最新 Codex `status = pass`
- 最新 Codex `next_action = approve`
- 不存在未解决的 `blocking` 或 `important` 问题
- 如果不是首轮直接通过，writer 必须对上一轮每个 issue 都有回应

`minor` 问题不单独阻止通过；但如果 Codex 仍显式返回 `fail`，则流程不得自判通过。

## 轮次规则

默认最大 review 轮次为 `5`，除非用户另行指定。

轮次按 Codex review 文件计数：

- `review-r1.json`
- `review-r2.json`
- `review-r3.json`

如果达到轮次上限仍未收敛：

- 立即停止循环
- 生成 `dispute-report.md`
- 报告中只保留仍未解决的 `blocking` 与 `important` 分歧
- 最终裁决交给人类，而不是由控制器擅自决定

## 失败处理

- 如果 `git` 或 `python3` 缺失，应立即停止
- 如果选中的 writer 命令缺失，应立即停止
- 如果工作区一开始不是 clean working tree，应立即停止
- 如果 writer JSON 不合法，应停止并保留现场
- 如果 writer 修订未覆盖上一轮全部 issue，应停止并保留现场
- 如果 Codex JSON 不合法，应停止并保留现场
- 如果 launcher 中途失败，不要自动回滚已生成代码

## Prompt 使用规则

运行时应把完整 prompt 文本直接传给外部 CLI，而不是让外部 CLI 自己去拼接模板。

动态上下文至少应包含：

- 用户任务
- topic slug
- 当前轮次
- 最大轮次
- `brief.md` 路径
- 最新 review 路径
- 最新 response 路径
- 修订轮使用的最新 handoff 路径

对于 Claude writer，推荐额外满足：

- 调用使用无状态模式，避免继承历史会话
- 当命中上下文过大或瞬时服务错误时，launcher 自动重试
- 重试时优先切换到更紧凑的 prompt，而不是继续把完整 diff 作为主要输入

## 严重级别定义

- `blocking`: 阻止正确交付、存在明确功能错误或核心缺陷
- `important`: 实质影响质量、正确性或完整性
- `minor`: 非关键优化、轻微一致性问题或可选改进

只有 `blocking` 和 `important` 都已解决，流程才算真正稳定收敛。
