# Explain Code

这是一个项目级 Codex skill 模板，用于把复杂程序整理成类似 API 文档或使用说明书的解释：先给结论和主流程，再说明组件职责、源码落点、关键机制与边缘情况。

它采用双重显式控制：

- 只有运行安装脚本的项目才会获得该 skill。
- 安装后只有用户显式调用 `$explain-code` 才会启用。

## 安装

默认安装 Codex 版：

```bash
./workflow-templates/explain-code/init.sh /path/to/target-project
```

也可以显式指定 Codex：

```bash
./workflow-templates/explain-code/init.sh --codex /path/to/target-project
```

安装结果：

```text
.codex/skills/explain-code/
  SKILL.md
  agents/
    openai.yaml
```

安装器还会在目标项目的 `AGENTS.md` 中写入一个带边界标记的说明区块。重复安装会替换该 skill 和对应区块，不会不断追加。

## 使用

```text
$explain-code 解释用户提交订单后的完整主流程。
$explain-code quick 这个模块的入口和输出是什么？
$explain-code deep 解释任务调度、状态变化和失败重试。
```

三种深度：

- `quick`：结论、主流程、关键源码落点
- 默认：增加角色分工、关键机制和必要术语
- `deep`：概览之后展开调用路径、状态变化、异步边界、错误路径和设计取舍

该 skill 只规定解释方式，不授权修改项目代码。

## 卸载与还原

```bash
./workflow-templates/explain-code/init.sh --remove /path/to/target-project
```

卸载只删除 `.codex/skills/explain-code`，并移除安装器自己写入的 `AGENTS.md` 区块；目标项目原有的其他内容会保留。

## 自检

```bash
bash workflow-templates/explain-code/tests/installers.sh
```
