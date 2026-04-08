---
name: writer
description: 当用户显式要求使用 "writer skill"、"writer workflow"、"实现闭环工作流"、"让 Claude Code 开发并由 Codex 审查" 时使用。适用于会落盘到仓库的制品任务：代码实现，以及 OpenSpec proposal/design/spec/tasks 等制品编写。Codex 作为控制器和 reviewer，writer 可选 Claude Code CLI 或独立 Codex CLI 子进程，默认最多 5 轮，未通过则输出争议点交由人类裁决。
---

# 实现闭环工作流

## 何时使用

只在用户显式要求时启用，例如：

- `使用 writer skill`
- `使用 writer workflow`
- `请走实现闭环工作流`
- `让 Claude Code 开发，Codex 审查`
- `让 Codex 作为 writer，Codex 再做审查`
- `请把实现交给 Claude Code，再由 Codex 循环审查`

如果用户没有明确要求，不要默认启用。

该 skill 适用于两类会直接落盘到仓库文件的任务：

- 代码实现、bug 修复、受约束重构等 `code` 任务
- OpenSpec proposal/design/spec/tasks 及其配套说明的编写、修订等 `openspec-artifacts` 任务

不适用于不产出仓库制品的纯讨论型任务，例如口头 plan、纯分析、纯建议或仅聊天式说明文档。

## 必要输入

开始前需要收集或推断：

- 用户任务陈述
- 制品类型：`code` 或 `openspec-artifacts`；如果用户未提供，应根据任务是否要求产出 OpenSpec 制品来推断
- writer 类型：`claude` 或 `codex`；如果用户未指定，默认 `claude`
- topic slug，使用 lowercase kebab-case；如果用户未提供，则根据任务语义推导
- 最大审查轮次；如果用户未提供，默认 `5`

## 前提检查

开始前必须检查：

- 当前目录是 git 仓库
- 工作区是 clean working tree
- `claude`、`codex`、`git`、`python3` 可用

如果这些前提不成立，不要自己改用普通实现流程来“替代”这个 skill；应明确告诉用户当前 blocker。

## 执行方式

优先使用 launcher，而不是在对话里手工模拟循环：

```bash
.codex/skills/writer/bin/writer-run.sh run \
  --task "<标准化后的用户任务>" \
  --artifact-type "<code|openspec-artifacts>" \
  --writer "<claude|codex>" \
  --topic "<topic-slug>" \
  --max-rounds "<N>"
```

launcher 会负责：

- 调用所选 writer 完成首轮实现或制品编写
- 采集 `git diff` 并写入 `.codex/plans/<topic-slug>/draft-r1.md`
- 调用 Codex CLI 进行结构化审查
- 在未通过时为修订轮生成精简 handoff，并驱动所选 writer 修订
- 生成 `review-rN.json`、`response-rN.json`、`revision-rN.md`
- 当 writer=claude 且命中上下文过大或瞬时调用错误时自动重试
- 在通过时写入 `final.md`
- 在轮次耗尽时写入 `dispute-report.md`

## 角色边界

- Codex 只负责控制、审查、收敛判断和最终汇报
- 所选 writer 只负责实现或编写制品，并根据 review 修订工作区文件
- 如果选择 `writer=codex`，实现必须通过独立的外部 `codex exec` 子进程完成；不要让当前控制器会话自己兼任 writer，否则会破坏角色边界
- 如果任务明确要求使用仓库内既有命令或工具链来产出制品（例如 `openspec-propose`），应由外部 writer 在自己的执行阶段遵守该流程，而不是由当前控制器会话代劳

如果 launcher 失败但工作区已经被 Claude 修改，不要擅自回滚用户工作区文件；先检查 `.codex/plans/<topic-slug>/` 下的已有产物，再向用户说明当前状态。

## 资源

- 流程规范：`./reference.md`
- Claude 首轮实现 prompt：`./prompts/claude-code-draft.md`
- Claude 修订 prompt：`./prompts/claude-code-revision.md`
- Codex 审查 prompt：`./prompts/codex-review.md`
- 争议报告 prompt：`./prompts/dispute-report.md`
- JSON 契约：`./schemas/*.json`

除非 launcher 无法使用，否则不要手动重写这些协议。
