---
name: debug
description: 当用户显式要求使用 "debug skill"、"debug workflow"、"debug 工作流"、"启动本地日志服务器排查 bug" 时使用。适用于前端或联调排障场景：agent 启动本地微型服务器，让浏览器把调试信息写入同一个临时 log 文件；每次用户追加新问题时先清空旧日志，再基于最新日志继续排查；修复确认后清理日志文件和会话。
---

# Debug 工作流

## 触发条件

只在用户明确要求时启用，例如：

- `使用 debug skill`
- `使用 debug workflow`
- `请走 debug 工作流`
- `启动本地日志服务器帮我排查 bug`

如果用户没有显式要求，不要默认启用。

## 目标

该 skill 用于把浏览器侧调试信息稳定写入一个临时 log 文件，再由当前 agent 基于该文件排查问题。

在同一个 debug 会话中：

- 始终复用同一个 log 文件路径
- 每次新的用户追加提问前，先清空旧日志
- 用户确认修复后，删除日志文件与后台服务

## 标准流程

### 1. 启动会话

首次进入该 workflow 时，优先执行：

```bash
.codex/skills/debug/bin/debug-session.sh start
```

如需显式命名会话，可加：

```bash
.codex/skills/debug/bin/debug-session.sh start --session <topic-slug>
```

读取返回 JSON 中的：

- `endpoint`
- `clear_url`
- `log_file`
- `server_log`

随后把 `endpoint` 提供给用户，指导浏览器或页面脚本把调试信息写进去。

### 2. 新一轮提问前清空旧日志

如果用户在同一个排障线程里追加问题、补充复现条件、或要求“重新看一下”，先执行：

```bash
.codex/skills/debug/bin/debug-session.sh reset
```

然后再让用户重新操作页面、重新写日志。

不要把上一轮遗留日志和本轮新问题混在一起分析。

### 3. 读取日志并排查

优先使用以下命令读取当前日志：

```bash
.codex/skills/debug/bin/debug-session.sh show
```

如果需要更多元信息，再执行：

```bash
.codex/skills/debug/bin/debug-session.sh status
```

必要时直接读取 `status` 返回中的 `log_file`。

### 4. 用户确认修复后清理

当用户明确表示问题已修复、无需继续保留日志时，执行：

```bash
.codex/skills/debug/bin/debug-session.sh cleanup
```

这一步必须删除 log 文件、状态文件和后台微型服务器，避免残留临时调试数据。

## 资源

- launcher: `.codex/skills/debug/bin/debug-session.sh`
- server: `.codex/skills/debug/bin/debug_log_server.py`
- 参考说明: `.codex/skills/debug/reference.md`

除非 launcher 无法使用，否则不要手工改写成另一套临时服务器方案。
