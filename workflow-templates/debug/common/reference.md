# Debug 工作流参考

## 生命周期约定

该工作流围绕“一个调试会话对应一个临时 log 文件”展开。

控制器必须遵循以下规则：

1. 首次进入 debug 会话时，执行 `./bin/debug-session.sh start`。
2. 在同一个会话中，每次新的用户追加提问前，如果用户补充了新的复现条件、追加了新的问题，或要求“重新看一下”，先执行 `./bin/debug-session.sh reset`，再让用户重新上报日志。
3. 需要查看日志内容时，优先执行 `./bin/debug-session.sh show`，必要时直接读取 `status` 返回中的 `log_file`。
4. 只要问题还未确认修复，就持续复用同一个会话和同一个 log 文件路径。
5. 用户确认问题已解决后，执行 `./bin/debug-session.sh cleanup`，删除 log 文件、状态文件和后台服务。

不要在普通任务中默认启动该服务器；只有用户显式要求使用 debug skill / debug workflow 时才触发。

## Launcher 命令

### `start`

```bash
./bin/debug-session.sh start
./bin/debug-session.sh start --session login-bug
./bin/debug-session.sh start --host 127.0.0.1 --port 47821
```

返回 JSON，包含：

- `status`: `ready`
- `endpoint`: 浏览器写日志地址，形如 `http://127.0.0.1:47821/log`
- `clear_url`: 清空日志地址
- `log_file`: 当前会话临时日志文件
- `server_log`: 服务自身日志
- `state_dir`: 会话状态目录
- `healthy`: 当前服务是否可达

如果同一会话已经存在且服务仍健康，`start` 不会重复启动新进程，而是直接返回当前状态。

### `status`

```bash
./bin/debug-session.sh status
```

返回与 `start` 类似的 JSON；如果会话不存在，则返回：

```json
{"status": "missing"}
```

### `reset`

```bash
./bin/debug-session.sh reset
```

清空当前会话的 log 文件，但保留服务进程和 log 文件路径，便于同一次调试线程继续复用。

### `show`

```bash
./bin/debug-session.sh show
```

直接输出当前 log 文件内容，便于 agent 读取与分析。

### `cleanup`

```bash
./bin/debug-session.sh cleanup
```

停止后台服务并删除当前会话目录下的：

- `debug.log`
- `session.json`
- `server.pid`
- `server.log`

## HTTP 接口

### `GET /health`

返回健康状态与当前会话元信息。

### `GET /session`

返回当前会话元信息，便于浏览器侧确认端口和目标文件。

### `POST /log`

支持两种 body 形式：

1. `application/json`
2. `text/plain`

JSON body 支持字段：

- `content`: 要写入日志的正文
- `mode`: `append` 或 `replace`，默认 `append`

示例：

```json
{
  "mode": "append",
  "content": "[click] checkout failed"
}
```

如果 JSON body 没有 `content`，服务会把整个 JSON 对象序列化后写入日志，方便直接上报结构化调试信息。

### `POST /clear`

清空日志文件内容。

### CORS

服务默认返回：

- `Access-Control-Allow-Origin: *`
- `Access-Control-Allow-Methods: GET, POST, DELETE, OPTIONS`
- `Access-Control-Allow-Headers: Content-Type`

## 浏览器接入建议

推荐在页面中封装一个轻量 helper，把关键事件、接口响应、报错堆栈、上下文参数写到同一 log 文件。例如：

```js
async function pushDebugLog(payload) {
  await fetch(window.__DEBUG_ENDPOINT__, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      mode: "append",
      content: JSON.stringify(payload, null, 2),
    }),
  });
}
```

在用户重新描述问题或切换排查方向后，控制器应先调用 `reset`，再让用户重新复现，以免旧日志干扰判断。
