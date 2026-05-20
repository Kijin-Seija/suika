---
name: reviewer
description: 当用户显式要求使用 reviewer skill 时使用。当前 Codex 会话先完成主任务，再通过只读 reviewer subagent 做结构化 review，并按 review 结果自动迭代修订，直到通过或达到轮次上限。
---

# Reviewer 工作流

## 概览

只在用户显式要求使用这套流程时启用。

这套工作流包含两个角色和一个控制器：

- 当前 Codex 会话负责完成主任务，并根据 review 结果修订代码或文档
- 当前 Codex 会话必须 `spawn_agent` 一个只读 reviewer subagent 负责 review 当前制品，并返回结构化 JSON
- 控制器负责流程调度、文件落盘、协议校验、收敛判断和停止条件

不要默认对所有普通请求启用该流程。

对于 Codex 宿主，不要再通过 shell 去跑 `codex exec` 来充当 reviewer；主路径必须是 Codex 原生 subagent 协作。安装目录中的 `.codex/skills/reviewer/bin/reviewer-run.sh` 仅保留给 Claude 兼容场景、回归测试或人工排障参考，不是本 skill 的首选执行方式。

## 触发条件

只有当用户明确提出以下意图时才应用本 skill：

- `使用 reviewer skill`
- `使用 reviewer 工作流`
- `让 Codex 审查这次任务结果`
- `做完后交给 Codex review`
- `请走 reviewer 审查循环`

如果用户没有显式要求，不要默认启用。

## 必要输入

开始前需要收集或推断以下输入：

- 用户任务陈述
- 制品类型：`code` 或 `doc`
- 输出 topic slug，使用 lowercase kebab-case
- 最大 review 轮次，默认 `5`

推断规则：

- 如果任务涉及实现功能、修复 bug、修改代码，则制品类型应为 `code`
- 如果任务涉及计划、分析、方案、说明文档，则制品类型应为 `doc`
- 如果用户没有提供 topic slug，应根据任务语义推导一个简短的 kebab-case 名称

## 前提检查

开始前必须检查：

- 当前目录是 git 仓库
- `git`、`python3` 可用
- 当前环境必须支持 Codex subagent / agent delegation 工具

如果这些前提不成立，不要自己改回 `codex exec` shell reviewer；应明确告诉用户当前 blocker。

## 运行目录布局

工作流产物保存在：

- `.codex/plans/<topic-slug>/brief.md`
- `.codex/plans/<topic-slug>/draft-r1.md`
- `.codex/plans/<topic-slug>/review-r1.md`
- `.codex/plans/<topic-slug>/response-r2.md`
- `.codex/plans/<topic-slug>/revision-r2.md`
- `.codex/plans/<topic-slug>/review-r2.md`
- `.codex/plans/<topic-slug>/response-r3.md`
- `.codex/plans/<topic-slug>/revision-r3.md`
- `.codex/plans/<topic-slug>/review-r3.md`
- `.codex/plans/<topic-slug>/final.md`
- `.codex/plans/<topic-slug>/dispute-report.md`

只创建本次实际运行所需的文件。

## 控制器职责

控制器就是当前会话中的父 agent。控制器必须：

- 收集并标准化输入
- 创建 topic 目录和 `brief.md`
- 先完成用户主任务
- 将当前结果标准化写入 `draft-r1.md` 或 `revision-rN.md`
- 根据当前轮次渲染 reviewer prompt
- 优先 `spawn_agent` 一个新的 reviewer subagent 获取 review
- 将 reviewer 原样返回保存为 `review-rN.md`
- 对 reviewer JSON 结果做协议校验
- 在 review 未通过时，根据 findings 执行修订
- 在每一轮 review 后执行收敛检查
- 在达到轮次上限时停止并生成 `dispute-report.md`

不要把是否继续下一轮的决定权交给 reviewer。循环控制只属于控制器。

控制器只允许执行协议层和机械层操作，不得参与 reviewer 结论本身：

- 可以做：prompt 渲染、流程调度、文件保存、JSON 校验、`git diff` 捕获、停止或重试流程
- 不可以做：伪造 reviewer finding、合并或降级问题后再转述、在 reviewer JSON 缺字段时脑补默认值
- 如果角色输出不合规，控制器只能要求同一角色重试，或停止流程；不能自己补正文

## reviewer subagent 规则

Codex 宿主下的 reviewer 必须满足：

- 优先 `spawn_agent` 一个新的 reviewer subagent；不要让当前控制器会话自己兼任 reviewer
- 优先使用 `default` 子代理类型；不要使用会修改文件的 `worker`
- `fork_context` 不是必需；不要假设 subagent 能看到当前对话历史，必要上下文必须通过完整渲染后的 prompt 显式传入
- subagent 只负责读取当前工作区并返回严格 JSON，不得修改工作区文件，不得代替控制器修正文档或代码
- 每轮 review 优先新建一个新的 reviewer subagent，避免上一轮上下文污染当前结论

## 执行协议

### 1. 初始化

1. 把用户请求标准化写入 `brief.md`。
2. 在 `brief.md` 中记录：
   - topic slug
   - 制品类型：`code` 或 `doc`
   - 最大 review 轮次
   - 标准化后的任务描述
   - execution mode：`explicit-reviewer-skill`
3. 如果制品类型为 `code`，还应记录 `git rev-parse HEAD` 的输出作为 baseline。

### 2. 完成主任务

4. 当前 Codex 会话先完成用户主任务。
5. 主任务完成后，控制器将当前结果标准化写入 `draft-r1.md`：
   - `code` 模式：保存变更概述、变更文件列表和 `git diff`
   - `doc` 模式：保存文档正文，必要时附带任务目标与约束

### 3. 首轮 reviewer 审查

6. 渲染 `./prompts/codex-review-request.md`，传入：
   - `{{USER_TASK}}`
   - `{{ARTIFACT_TYPE}}`
   - `{{TOPIC_SLUG}}`
   - `{{ROUND}} = 1`
   - `{{MAX_ROUNDS}}`
   - `{{CURRENT_ARTIFACT}} = draft-r1.md` 的正文
   - `{{LATEST_REVIEW}} = none`
   - `{{LATEST_CLAUDE_RESPONSE}} = none`
7. 控制器必须 `spawn_agent` 一个新的 reviewer subagent，把完整渲染后的 prompt 发送给它，而不是调用 `.codex/skills/reviewer/bin/reviewer-run.sh review ...`。
8. reviewer subagent 必须在当前工作区里完成只读审查，直接读取最新文件和未提交改动，并返回严格 JSON。
9. 将 reviewer 原样返回保存为 `review-r1.md`。
10. 校验返回是否为符合契约的 JSON：
   - 必须包含 `status`、`summary`、`issues`、`next_action`
   - `severity` 只能是 `blocking | important | minor`
   - `status = fail` 时，问题列表必须存在且结构完整
11. 若协议不合法，只能要求 reviewer subagent 重试该轮，不能由控制器补齐。

### 4. 收敛或修订

12. 如果 `review-r1.md` 已返回通过结果，则写入 `final.md` 并停止。
13. 否则，读取并遵循 `./prompts/codex-review-response.md`，逐条处理 `review-r1.md` 中的问题：
   - 属实则修改，并标记 `accepted`
   - 存疑则提出问题，并标记 `questioned`
   - 不成立则说明理由，并标记 `rejected`
14. 将逐条回应保存为 `response-r2.md`。
15. 重新采集最新结果并保存为 `revision-r2.md`。

### 5. 后续轮次

16. 每一轮都重新 `spawn_agent` 一个新的 reviewer subagent review `revision-rN.md`，并同时附带：
   - 上一轮 `review-r(N-1).md`
   - 当前轮 `response-rN.md`
17. 将 reviewer 返回保存为 `review-rN.md`。
18. 如果通过，则写入 `final.md` 并停止。
19. 如果未通过且仍未达到最大轮次，则重复修订 -> review。
20. 如果达到最大轮次仍未通过，则停止循环，并生成 `dispute-report.md`。

## Code 模式要求

当制品类型为 `code` 时：

- 项目必须是 git 仓库
- `brief.md` 应记录 git baseline
- 如果某一轮新增了未跟踪文件，应确保它们能被后续 diff 捕获
- 提交给 reviewer 的上下文应以原始 `git diff`、文件路径列表和必要原始片段为主
- reviewer subagent 必须在当前项目工作区中运行，直接查看主 agent 已产生但尚未提交的改动
- 不得为 reviewer subagent 创建或切换到独立 worktree、临时 checkout、镜像目录或其他看不到当前改动的隔离环境
- 不要只把控制器自己的语义摘要交给 reviewer

## Doc 模式要求

当制品类型为 `doc` 时：

- `draft-r1.md` / `revision-rN.md` / `final.md` 保存文档正文
- 可以附带任务目标、约束、验收标准
- 如果因长度限制只能摘录，必须保留足够的原文线索，避免控制器改写语义

## 收敛规则

以下条件在 code 和 doc 模式下都适用：

- 最新 reviewer `status` 为 `pass`
- 最新 reviewer `next_action` 为 `approve`
- 没有未解决的 `blocking` 和 `important` 问题
- 如果不是首轮直接通过，则当前会话必须对上一轮问题做出逐条回应

`minor` 问题不单独阻止通过，但如果 reviewer 仍明确返回 `fail`，则流程不得自判收敛。

## 轮次上限

默认最大 review 轮次为 `5`，除非用户另行指定。

轮次按 reviewer 文件计数：`review-r1.md`、`review-r2.md`、`review-r3.md` ...

如果达到轮次上限仍未收敛：

- 立即停止循环
- 使用 `./prompts/dispute-report.md` 生成 `dispute-report.md`
- 总结仍未解决的问题、双方理由和需要用户做出的决策

## 失败处理

- 如果 reviewer 返回无法解析或不符合契约的 JSON，控制器只能要求 reviewer 重试该轮
- 如果当前会话没有逐条回应 findings，控制器只能要求重试该轮
- 如果声称已修复，但最新制品没有体现，控制器不得伪造完成状态
- 多次重试仍不满足契约时，应停止流程并保留已有文件供人工接管

## 补充说明

请阅读 `reference.md` 获取：

- JSON 契约
- 文件命名规则
- 制品结构
- 严重级别定义
- 收敛与争议升级规则
