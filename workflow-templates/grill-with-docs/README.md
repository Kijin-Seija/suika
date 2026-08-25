# Grill with docs

这是一个可复用的项目级 skill 模板，用于在实现前对方案进行连续追问，并把已经明确的领域术语和重要架构决策同步到项目文档。

模板兼容：

- Codex：安装到 `.codex/skills/grill-with-docs/`
- Claude Code：安装到 `.claude/skills/grill-with-docs/`

模板内容收录在仓库中，安装时不依赖 npm，也不需要联网。

## 安装方式

默认同时安装 Codex 和 Claude Code 版：

```bash
bash workflow-templates/grill-with-docs/init.sh /path/to/target-project
```

也可以选择目标平台：

```bash
bash workflow-templates/grill-with-docs/init.sh --all /path/to/target-project
bash workflow-templates/grill-with-docs/init.sh --codex /path/to/target-project
bash workflow-templates/grill-with-docs/init.sh --claude /path/to/target-project
```

重复运行安装器是安全的：目标 skill 目录会更新，Codex 的 `AGENTS.md` 说明区块会原位替换，不会重复追加。

## 安装结果

每个平台的 skill 目录包含：

- `SKILL.md`
- `CONTEXT-FORMAT.md`
- `ADR-FORMAT.md`
- `LICENSE`

Codex 安装器还会在目标项目的 `AGENTS.md` 中维护一个带标记的入口区块。Claude Code 按其原生项目 skill 目录自动发现，不修改 `CLAUDE.md`。

## 使用方式

可以对 agent 说：

```text
使用 grill-with-docs 质询这个方案。
Grill this design with docs.
先不要实现，逐项追问并验证这个计划。
```

skill 会：

- 一次只提出一个聚焦问题，并给出推荐答案
- 能从代码或现有文档确认的问题先自行检查
- 对照 `CONTEXT.md` 统一领域术语
- 仅在有内容时创建或更新领域词汇表
- 仅为难以逆转、缺少背景会显得意外、且存在真实权衡的决策提出 ADR

## 上游来源

内容来自 `xwang-mattpocock` npm 包的 `grill-with-docs` skill，当前收录版本为 `0.1.2`：

- https://github.com/xwang-mattpocock/xwang-mattpocock
- https://www.npmjs.com/package/xwang-mattpocock

上游采用 MIT License；许可文本会随 skill 一并安装。

## 自检

```bash
bash workflow-templates/grill-with-docs/tests/installers.sh
```
