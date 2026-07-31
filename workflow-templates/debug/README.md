# Debug 工作流

这是一个面向 Codex 的可复用前端排障 skill 模板包。

## 三种模式

- `debug auto`：Codex 使用 Playwright 或等价浏览器自动化能力自行启动、操作、取证和回归验证。
- `debug steps`：用户手动操作，Codex 通过本地日志服务器收集最新浏览器日志并建立证据链。
- `debug manual`：不启动日志服务器；Codex 添加临时 `console` 日志，用户复现并上传日志后再分析。

## 目录结构

```text
workflow-templates/debug/
  common/
    bin/
      debug-session.sh
      debug_log_server.py
  codex/
    skills/
      debug-auto/SKILL.md
      debug-steps/SKILL.md
      debug-manual/SKILL.md
    reference-steps.md
    init.sh
  tests/installers.sh
  init.sh
  README.md
```

## 安装

```bash
./workflow-templates/debug/init.sh /path/to/target-project
```

也可以显式指定 Codex：

```bash
./workflow-templates/debug/init.sh --codex /path/to/target-project
```

安装结果包括：

- `.codex/skills/debug-auto/SKILL.md`
- `.codex/skills/debug-steps/SKILL.md`
- `.codex/skills/debug-manual/SKILL.md`
- `.codex/skills/debug-steps/bin/debug-session.sh`
- `.codex/skills/debug-steps/bin/debug_log_server.py`
- `.codex/skills/debug-steps/reference.md`
- `AGENTS.md` 中的显式触发入口区块

## 触发

该工作流只在用户显式要求时启用，例如：

```text
请使用 debug auto 排查这个前端 bug。
请走 debug steps，我来手动复现，你收集日志分析。
请使用 debug manual，你先加 console 日志，我操作后把日志发你。
```

## Launcher

只有 `debug steps` 需要 launcher：

```bash
.codex/skills/debug-steps/bin/debug-session.sh start
.codex/skills/debug-steps/bin/debug-session.sh status
.codex/skills/debug-steps/bin/debug-session.sh reset
.codex/skills/debug-steps/bin/debug-session.sh show
.codex/skills/debug-steps/bin/debug-session.sh cleanup
```

`start` 返回浏览器上报地址、日志文件和服务状态。每轮复现前先 `reset`，拿到新日志并确认其足以支撑判断后再修改代码；用户确认修复后移除临时调试代码并执行 `cleanup`。

## 自检

```bash
bash workflow-templates/debug/tests/installers.sh
```
