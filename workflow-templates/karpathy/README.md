# Karpathy 编码守则

这是一个可复用模板包，用于把 Andrej Karpathy 风格的编码守则安装为项目级 Codex 或 Claude Code skill。

它不是代码生成器或 launcher，而是一层默认启用的行为约束，适用于大多数非琐碎的编码、review、重构、排障等工程任务，帮助 agent：

- 避免擅自脑补需求
- 优先最小实现，避免过度设计
- 控制改动面，只做与请求直接相关的修改
- 把任务写成可验证的成功标准

## 目录结构

```text
workflow-templates/karpathy/
  common/
    reference.md
  codex/
    skill/
      SKILL.md
    init.sh
  claude/
    skill/
      SKILL.md
    init.sh
  tests/
    installers.sh
  init.sh
  README.md
```

## 安装方式

默认安装 Codex 版：

```bash
./workflow-templates/karpathy/init.sh /path/to/target-project
```

也可以显式调用：

```bash
./workflow-templates/karpathy/init.sh --codex /path/to/target-project
./workflow-templates/karpathy/codex/init.sh /path/to/target-project
```

安装 Claude Code 版：

```bash
./workflow-templates/karpathy/init.sh --claude /path/to/target-project
```

安装结果包括：

- `.codex/skills/karpathy/SKILL.md`
- `.codex/skills/karpathy/reference.md`
- `AGENTS.md` 中的默认启用规则区块

Claude Code 版安装到 `.claude/skills/karpathy/`，依靠原生 skill 发现，不修改 `CLAUDE.md`。

## 启用方式

安装后，默认会在大多数非琐碎工程任务中启用。

如果用户显式说出下面这些话，也会更强地提示 agent 按该守则执行：

```text
请使用 karpathy skill 来做这次实现。
按 karpathy 风格修这个 bug。
这次 review 请遵守 karpathy guidelines。
请按 Karpathy 的编码守则执行。
/karpathy
```

以下场景通常可以轻量处理，不必完整走这套节奏：

- 纯闲聊、纯翻译、纯信息查询
- 显而易见的一行式机械改动

## Skill 内容

该 skill 收敛为四条原则：

1. 先想清楚再编码
2. 简单优先
3. 外科式改动
4. 目标驱动执行

`SKILL.md` 负责描述默认启用条件、执行要求和核心原则；`reference.md` 负责放置判断示例，避免主 skill 过长。

## 自检

运行以下测试验证安装器：

```bash
bash workflow-templates/karpathy/tests/installers.sh
```
