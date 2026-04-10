# Debug 工作流

这是一个可复用模板包，用于初始化“显式触发后由 agent 启动本地微型日志服务器，浏览器通过 HTTP 接口把调试信息写入同一个临时 log 文件，agent 基于该 log 文件排查 bug，问题修复后再清理会话”的调试工作流。

该工作流同时支持：

- Codex CLI 宿主
- Claude Code 宿主

## 工作流效果

触发后，agent 会遵循同一套会话约定：

1. 启动本地微型服务器，默认监听 `127.0.0.1:47821`；若端口被占用，会自动回退到随机可用端口。
2. 服务器暴露浏览器可直接调用的接口：
   - `POST /log`：把调试内容追加到当前会话的同一个 log 文件
   - `POST /clear`：清空当前会话 log 文件
   - `GET /session` / `GET /health`：查看会话与健康状态
3. 每个调试会话只使用一个临时 log 文件。
4. 当用户在同一个 debug 会话里追加新问题时，agent 先清空上一次日志，再让用户重新记录。
5. agent 读取该 log 文件定位问题。
6. 用户确认问题修复后，agent 删除 log 文件并结束会话。

运行时文件默认写到系统临时目录，不污染项目工作区；同一项目在同一个宿主下会复用一份会话状态。

## 目录结构

```text
workflow-templates/debug/
  common/
    bin/
      debug-session.sh
      debug_log_server.py
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

默认同时安装 Codex 和 Claude Code 两版：

```bash
./workflow-templates/debug/init.sh /path/to/target-project
```

也可以显式指定：

```bash
./workflow-templates/debug/init.sh --codex /path/to/target-project
./workflow-templates/debug/init.sh --claude /path/to/target-project
./workflow-templates/debug/init.sh --all /path/to/target-project
```

安装结果包括：

- `.codex/skills/debug/` 或 `.claude/skills/debug/`
- `bin/debug-session.sh`
- `bin/debug_log_server.py`
- `reference.md`
- `AGENTS.md` / `CLAUDE.md` 中的显式触发入口区块

## 触发方式

该工作流只在用户显式要求时启用，例如：

```text
请使用 debug skill 排查这个前端 bug。
请走 debug workflow，启动本地日志服务器帮我看问题。
使用 debug 工作流，把浏览器里的调试信息写到临时日志里再分析。
```

如果用户没有明确要求，不要默认启用。

## 手动执行 launcher

安装后，agent 应优先使用 launcher 管理会话，而不是手工拼装临时服务器命令：

```bash
.codex/skills/debug/bin/debug-session.sh start
.codex/skills/debug/bin/debug-session.sh status
.codex/skills/debug/bin/debug-session.sh reset
.codex/skills/debug/bin/debug-session.sh show
.codex/skills/debug/bin/debug-session.sh cleanup
```

Claude Code 版路径等价，只是把 `.codex` 替换为 `.claude`。

`start` 会返回 JSON，包括：

- `endpoint`：浏览器写日志用的地址
- `clear_url`：浏览器或 agent 主动清空日志时可调用的地址
- `log_file`：agent 需要读取的临时日志路径
- `server_log`：服务自身 stdout/stderr 的落盘日志

如果 `start` 失败，返回 JSON 还会保留 `state_dir` 和 `server_log_tail`，并且不会立刻删除 runtime，便于继续诊断绑定失败或环境限制问题。

## 浏览器接入示例

最小可用示例：

```js
await fetch("http://127.0.0.1:47821/log", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    mode: "append",
    content: JSON.stringify(
      {
        href: window.location.href,
        message: "button click failed",
        payload: debugPayload,
      },
      null,
      2,
    ),
  }),
});
```

服务已启用基础 CORS 头，便于本地开发页面直接上报。

## 自检

运行以下测试验证安装器与日志服务器生命周期：

```bash
bash workflow-templates/debug/tests/installers.sh
```
