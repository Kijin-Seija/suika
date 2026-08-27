# Explain Code

这是一个兼容 Codex 与 Claude Code 的项目级 skill 模板，用于把复杂程序整理成类似 API 文档或使用说明书的解释。

它采用双重显式控制：

- 只有运行安装脚本的项目才会获得该 skill。
- 安装后只有用户显式调用 Codex 的 `$explain-code` 或 Claude Code 的 `/explain-code` 才会启用。

## 安装

默认安装 Codex 版：

```bash
./workflow-templates/explain-code/init.sh /path/to/target-project
```

也可以显式指定 Codex：

```bash
./workflow-templates/explain-code/init.sh --codex /path/to/target-project
```

Claude Code 版：

```bash
./workflow-templates/explain-code/init.sh --claude /path/to/target-project
```

安装结果：

```text
.codex/skills/explain-code/
  SKILL.md
  agents/
    openai.yaml
```

安装器还会在目标项目的 `AGENTS.md` 中写入一个带边界标记的说明区块。重复安装会替换该 skill 和对应区块，不会不断追加。

Claude Code 版只安装 `.claude/skills/explain-code/SKILL.md`，不写 `CLAUDE.md`，并使用原生调用 `/explain-code [quick|deep]`。

## 使用

```text
$explain-code 解释用户提交订单后的完整主流程。
$explain-code quick 这个模块的入口和输出是什么？
$explain-code deep 解释任务调度、状态变化和失败重试。
/explain-code 解释用户提交订单后的完整主流程。
/explain-code quick 这个模块的入口和输出是什么？
/explain-code deep 解释任务调度、状态变化和失败重试。
```

三种深度：

- `quick`：结论、主流程、关键源码落点
- 默认：增加角色分工、关键机制和必要术语
- `deep`：概览之后展开调用路径、状态变化、异步边界、错误路径和设计取舍

该 skill 只规定解释方式，不授权修改项目代码。

## 卸载与还原

```bash
./workflow-templates/explain-code/init.sh --remove /path/to/target-project
./workflow-templates/explain-code/init.sh --claude --remove /path/to/target-project
```

Codex 卸载会删除 `.codex/skills/explain-code` 并移除安装器写入的 `AGENTS.md` 区块；Claude Code 卸载只删除 `.claude/skills/explain-code`。目标项目原有内容都会保留。

## 自检

```bash
bash workflow-templates/explain-code/tests/installers.sh
```
