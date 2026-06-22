# Debug 工作流

这是一个可复用模板包，用于初始化前端排障工作流。

其中：

- Codex 宿主会安装三个独立命令：`debug auto`、`debug steps`、`debug manual`
- Claude Code 宿主仍保留单一的 `debug` 工作流

该工作流同时支持：

- Codex CLI 宿主
- Claude Code 宿主

## Codex 三种模式

### `debug auto`

agent 使用 Playwright 或等价浏览器自动化能力：

1. 启动或连接本地项目
2. 自动操作页面复现问题
3. 自动监听 `console` / `pageerror` / 网络失败
4. 基于自动化运行证据分析并修复
5. 自动回归验证

### `debug steps`

用户手动操作页面，agent 自动收集日志：

1. 启动本地微型日志服务器
2. agent 直接把临时调试上报代码加到项目里
3. 浏览器通过 HTTP 接口把调试信息写入同一个临时 log 文件
4. 每次新一轮复现前清空旧日志
5. agent 先读取最新日志建立证据链
6. 修复确认后移除临时调试代码并清理会话

### `debug manual`

不启动日志服务器，由 agent 在代码中加临时 `console` 打点：

1. agent 先选择关键代码路径加日志
2. 用户自己操作并收集输出
3. 用户上传日志
4. agent 基于日志分析问题，必要时继续补打点
5. 修复后移除临时日志

## `debug steps` / Claude `debug` 工作流效果

触发后，agent 会遵循同一套会话约定：

1. 启动本地微型服务器，默认监听 `127.0.0.1:47821`；若端口被占用，会自动回退到随机可用端口。
2. 服务器暴露浏览器可直接调用的接口：
   - `POST /log`：把调试内容追加到当前会话的同一个 log 文件
   - `POST /clear`：清空当前会话 log 文件
   - `GET /session` / `GET /health`：查看会话与健康状态
3. 每个调试会话只使用一个临时 log 文件。
4. 当用户在同一个 debug 会话里追加新问题时，agent 先清空上一次日志，再让用户重新记录。
5. agent 先读取该 log 文件中的最新证据，并确认这些打印数据足以证明判断成立，再进入代码定位与修复。
6. 用户确认问题修复后，agent 删除 log 文件并结束会话。

如果当前还没有本轮问题的新日志，或者日志还不足以证明当前判断，agent 应先要求用户复现、补日志或补打点，而不是直接凭代码逻辑猜测或提前修复。

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
    skills/
      debug-auto/
        SKILL.md
      debug-steps/
        SKILL.md
      debug-manual/
        SKILL.md
    reference-steps.md
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

- Codex:
  - `.codex/skills/debug-auto/SKILL.md`
  - `.codex/skills/debug-steps/SKILL.md`
  - `.codex/skills/debug-manual/SKILL.md`
  - `.codex/skills/debug-steps/bin/debug-session.sh`
  - `.codex/skills/debug-steps/bin/debug_log_server.py`
  - `.codex/skills/debug-steps/reference.md`
- Claude Code:
  - `.claude/skills/debug/SKILL.md`
  - `.claude/skills/debug/bin/debug-session.sh`
  - `.claude/skills/debug/bin/debug_log_server.py`
  - `.claude/skills/debug/reference.md`
- `AGENTS.md` / `CLAUDE.md` 中的显式触发入口区块

## 触发方式

该工作流只在用户显式要求时启用，例如：

```text
请使用 debug auto 排查这个前端 bug。
请走 debug steps，我来手动复现，你收集日志分析。
请使用 debug manual，你先加 console 日志，我操作后把日志发你。
```

如果用户没有明确要求，不要默认启用。

## 手动执行 launcher

只有 `debug steps` 和 Claude 的单一 `debug` workflow 需要 launcher。Codex 的 `debug auto` 与 `debug manual` 不依赖这个本地日志服务器。

安装后，agent 应优先使用 launcher 管理会话，而不是手工拼装临时服务器命令：

```bash
.codex/skills/debug-steps/bin/debug-session.sh start
.codex/skills/debug-steps/bin/debug-session.sh status
.codex/skills/debug-steps/bin/debug-session.sh reset
.codex/skills/debug-steps/bin/debug-session.sh show
.codex/skills/debug-steps/bin/debug-session.sh cleanup
```

Claude Code 版路径等价，只是把 `.codex/skills/debug-steps` 替换为 `.claude/skills/debug`。

`start` 会返回 JSON，包括：

- `endpoint`：浏览器写日志用的地址
- `clear_url`：浏览器或 agent 主动清空日志时可调用的地址
- `log_file`：agent 需要读取的临时日志路径
- `server_log`：服务自身 stdout/stderr 的落盘日志

如果 `start` 失败，返回 JSON 还会保留 `state_dir` 和 `server_log_tail`，并且不会立刻删除 runtime，便于继续诊断绑定失败或环境限制问题。

## `debug steps` / Claude `debug` 推荐排障约束

为了避免“服务启动了，但 agent 还是主要靠看代码猜”，建议把该 workflow 理解为一个强约束流程：

1. 先启动会话
2. 先把最小必要的临时调试上报代码直接加到项目里
3. 先拿到一份新的问题日志
4. 先读取并总结日志证据
5. 先确认这些打印数据已经足以证明当前判断
6. 再根据证据去看代码与修复
7. 用户确认修复后移除临时调试代码并清理会话
8. 如果证据不足，先补日志，不直接下结论，也不提前修复

也就是说，代码阅读可以很重要，但它应该发生在“已经有日志线索之后”。

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
