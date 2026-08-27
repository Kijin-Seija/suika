# Push Code 工作流

这是一个兼容 Codex 与 Claude Code 的可复用模板包，用于初始化“本地 clean working tree -> push 当前分支 -> 创建 MR -> 跟进 review 到可提交状态”的 `push-code` skill。

当前模板提供两类能力：

- `codex/`：安装到 `.codex/skills/push-code/`，并通过 `AGENTS.md` 暴露入口
- `claude/`：安装到 `.claude/skills/push-code/`，依靠 Claude Code 原生 skill 发现
- 可选的全局 Node.js MR monitor：作为系统级单实例服务，统一检查各项目已登记的 MR 状态，并用固定模板通知指定会话；它不参与业务判断，也不会替当前会话改代码

该模板始终把职责拆开：

- 当前 Codex 会话负责理解 review、判断是否接受意见、修改代码、提交 commit、决定是否回复 discussion / 普通 note、以及哪些 thread 应该在修复后显式 resolve
- 安装后的 launcher 负责机械动作：git preflight、push、创建 MR、轮询 review 状态、读取 discussions / 普通 notes、回复 discussion、追加普通 MR note、resolve discussion thread
- 可选 monitor 只负责全局定时巡检和固定模板通知，不会替代当前会话的主动轮询

## 目录结构

```text
workflow-templates/push-code/
  common/
    bin/
      push-code-run.sh
      push-code-monitor.cjs
      push_code_webhook.py
    reference.md
  codex/
    skill/
      SKILL.md
    init.sh
  tests/
    installers.sh
  init.sh
  README.md
```

## 触发方式

安装后，通过以下入口暴露能力：

- `AGENTS.md`
- `.codex/skills/push-code/`

该 skill 只在用户显式要求使用时启用，例如：

```text
请使用 push-code skill 把当前分支推上去，创建 MR，并跟进直到达到可提交状态。
```

不要默认对所有普通请求自动附加这套流程。

## 行为概览

1. 先检查当前工作区：
   - 必须是 git 仓库
   - 不能有 staged / unstaged / untracked 变更
   - 不能处于 detached HEAD
2. 通过 `git push` 推送当前分支到远端。
3. 直接调用 GitLab REST API 创建从当前分支到目标主分支的 MR，并获取 `mr_id`。
4. 轮询当前 head SHA 的全部 pipelines、review 状态、discussions、普通 MR notes、external status checks 和 mergeability blockers：
   - 如果 review 通过，则 MR 达到可提交状态
   - 如果 reviewer 提出问题，则读取 discussions / 普通 MR notes
   - 任意当前 head pipeline / external status check 失败都优先于其他 running / pending 信号，避免并行检查中的失败被仍在运行的检查遮住
   - 即使结构化状态暂时还是 pending，也要重新检查全部非 system MR note revisions，避免漏掉 reviewer 对已有评论的编辑，或把“CI 运行中但 reviewer 已给出 finding”误报成“仅等待 CI”
   - 当前会话必须自己继续轮询，直到 MR 达到可提交状态、超时或出现明确 blocker
   - 若有异议，通过 GitLab discussion 或普通 MR note 回复
   - 若无异议，则修复代码、`git add`、`git commit`、`git push`
   - 对已修复完成的 unresolved thread，显式标记为 resolved
5. 重复第 4 步，直到 MR 达到可提交状态。

补充规则：

- 如果 `git push` 触发本地 pre-push 检查脚本且检查失败，agent 需要先分析报错原因
- 确认是测试、lint、构建还是环境问题后，先修复，再重新 `git add`、`git commit`、`git push`
- 不要跳过本地 pre-push 检查去继续创建 MR

## 初始化配置

安装时会进入一个提示式配置向导，并写入 `.codex/skills/push-code/config.env`。如果目标项目之前已经初始化过，安装器会先读取旧配置；再次执行 `init.sh` 时，直接回车即可沿用之前的值。对于安装器不直接托管的自定义环境变量，也会在重装时一并保留。

交互式向导默认只询问常用项：

- `Git remote`
- `目标主分支`
- `项目 ID`
- `MR 标题前缀`
- `GitLab 基础地址`
- `GitLab API token`
- 是否启用全局 Node.js MR monitor
- monitor 轮询间隔（秒）

其余高级参数会直接按默认值或旧配置写入 `config.env`，需要时再手动编辑。

如果启用了全局 MR monitor，安装器会：

- 在项目里写入 bridge 脚本：
  - `.codex/skills/push-code/bin/push-code-monitor.cjs`
- 在 `CODEX_HOME` 下写入全局 monitor 运行文件：
  - `$CODEX_HOME/push-code-monitor/bin/push-code-monitor.cjs`
  - `$CODEX_HOME/push-code-monitor/config.json`
  - `$CODEX_HOME/push-code-monitor/monitor.db`

这个 monitor 不依赖 Codex 自带的 automation。它的设计是：

1. `create-mr` 成功后，launcher 会在当前会话存在 `CODEX_THREAD_ID` 时，把 `thread_id -> mr_id` 连同 `project_root`、`launcher_path` 一起登记到全局 `monitor.db`
2. 定时检查时直接运行全局 Node.js 脚本：
   - `$CODEX_HOME/push-code-monitor/bin/push-code-monitor.cjs scan`
   - 或 `$CODEX_HOME/push-code-monitor/bin/push-code-monitor.cjs run-loop --interval-seconds <n>`
3. 脚本会按 MR 记录里的项目信息，回到对应项目调用 `push-code-run.sh status --mr-id <id>` 获取结构化状态
4. 如果发现 MR 已达到可提交状态，或已经需要继续处理，则用固定模板通过 `codex exec resume` 通知登记过的原始会话
5. monitor 服务启动后，还会在本地起一个简单 dashboard 页面，用来查看运行状态、会话 / MR 映射和最近巡检记录

monitor 只是额外的定时提醒工具，不会改变业务 agent 的收口规则。skill 仍要求当前会话在提交 MR 后自己继续定时轮询追踪，直到 MR 达到可提交状态。
安装器只会写入 monitor 脚本、配置和数据库，不会自动启动后台巡检服务；是否启动由项目自己显式执行。

对于 `Git remote`，安装器会优先按下面顺序决定默认值：

- 命令行显式传入的 `--remote`
- 旧的 `.codex/skills/push-code/config.env`
- 目标项目 git 仓库中的 `origin`
- 如果没有 `origin`，但只有一个 remote，则使用那个唯一 remote
- 都没有时回退到 `origin`

对于 `project_id`，安装器也会尽量自动推断：

- 先用命令行显式传入的 `--project-id`
- 再用旧的 `.codex/skills/push-code/config.env`
- 如果仍为空，并且能读到目标项目的 remote URL，则从 URL 路径推断，例如：
  - `git@gitlab.example.com:group/project.git` -> `group/project`
  - `https://gitlab.example.com/group/project.git` -> `group/project`

当 `remote` 或 `project_id` 是自动推断出来时，交互式向导会直接采用推断值，不再停下来要求你再次输入。

安装器在写入配置后还会尝试做连通性检查：

- 如果目标项目本身是 git 仓库，且配置的 remote 存在，会执行 `git ls-remote <remote>` 验证 GitLab 连接
- 如果配置了 GitLab 地址和 token，会调用 `GET /api/v4/user` 验证 API 鉴权
- 如果同时配置了 `project_id`，会继续调用 `GET /api/v4/projects/:id` 验证项目是否可访问
- 如果信息不足，会明确打印 `跳过`

GitLab API helper 默认优先使用 `curl`，这样通常能直接复用系统证书链；如果没有 `curl`，才回退到 Python `urllib`。

如果检查阶段看到 `CERTIFICATE_VERIFY_FAILED`，一般不是 token 错，而是当前 Python 证书信任链和 GitLab TLS 链不匹配。初始化后可以在配置里补：

- `PUSH_CODE_GITLAB_CA_BUNDLE`
- `PUSH_CODE_GITLAB_SKIP_TLS_VERIFY`（仅建议临时排障时使用）

## 安装方式

默认安装 Codex 版本：

```bash
./workflow-templates/push-code/init.sh /path/to/target-project
```

带配置参数安装：

```bash
./workflow-templates/push-code/init.sh \
  --gitlab-base-url "https://gitlab.example.com" \
  --gitlab-api-token "glpat-xxxxx" \
  --project-id "group/project" \
  --target-branch "main" \
  --enable-mr-monitor \
  --mr-monitor-interval-seconds 300 \
  /path/to/target-project
```

如果希望脚本模式下完全跳过提示，可以显式指定：

```bash
./workflow-templates/push-code/init.sh --no-prompt /path/to/target-project
```

如果希望显式要求执行连通性检查，可以传：

```bash
./workflow-templates/push-code/init.sh --check-connectivity /path/to/target-project
```

也可以直接调用 Codex 安装器：

```bash
./workflow-templates/push-code/codex/init.sh /path/to/target-project
```

安装 Claude Code 版时，现有配置和 launcher 参数保持一致：

```bash
./workflow-templates/push-code/init.sh --claude \
  --no-prompt \
  --claude-bin "$(command -v claude)" \
  /path/to/target-project
```

Claude 版使用 `${CLAUDE_HOME:-$HOME/.claude}/push-code-monitor/` 保存全局 monitor，并从 `CLAUDE_CODE_SESSION_ID` 获取当前会话。通知命令为 `claude --resume <session-id> --print <message>`；可通过 `PUSH_CODE_MR_MONITOR_CLAUDE_BIN` 覆盖 CLI 路径。

安装结果包括：

- `.codex/skills/push-code/`
- `.codex/skills/push-code/config.env`
- `.codex/skills/push-code/reference.md`
- `.codex/skills/push-code/bin/push-code-run.sh`
- `.codex/skills/push-code/bin/push-code-monitor.cjs`
- `.codex/skills/push-code/bin/push_code_webhook.py`
- `$CODEX_HOME/push-code-monitor/bin/push-code-monitor.cjs`
- `$CODEX_HOME/push-code-monitor/config.json`
- `$CODEX_HOME/push-code-monitor/monitor.db`
- `AGENTS.md` 中的 `push-code` 工作流区块

Claude Code 对应文件位于 `.claude/skills/push-code/`，MR 标题默认前缀为 `[Claude]`。所有 `push-code-run.sh` 子命令与 Codex 版一致。

## 使用方式

Claude Code 原生调用示例为 `/push-code`。触发 skill 后，优先通过安装后的 launcher 执行机械动作：

```bash
.codex/skills/push-code/bin/push-code-run.sh preflight
.codex/skills/push-code/bin/push-code-run.sh push
.codex/skills/push-code/bin/push-code-run.sh rebase-target
.codex/skills/push-code/bin/push-code-run.sh create-mr
.codex/skills/push-code/bin/push-code-run.sh wait-review --mr-id 123
.codex/skills/push-code/bin/push-code-run.sh threads --mr-id 123
.codex/skills/push-code/bin/push-code-run.sh comment --mr-id 123 --thread-id abc --body-file reply.md
.codex/skills/push-code/bin/push-code-run.sh note --mr-id 123 --body-file reply.md
.codex/skills/push-code/bin/push-code-run.sh resolve-thread --mr-id 123 --thread-id abc
```

Claude Code 使用完全相同的子命令和参数，只把路径前缀替换为 `.claude/skills/push-code/`。

如果你想启动系统级总服务，可以额外运行：

```bash
$CODEX_HOME/push-code-monitor/bin/push-code-monitor.cjs scan
$CODEX_HOME/push-code-monitor/bin/push-code-monitor.cjs run-loop --interval-seconds 300
$CODEX_HOME/push-code-monitor/bin/push-code-monitor.cjs start --interval-seconds 300
$CODEX_HOME/push-code-monitor/bin/push-code-monitor.cjs status
$CODEX_HOME/push-code-monitor/bin/push-code-monitor.cjs stop
$CODEX_HOME/push-code-monitor/bin/push-code-monitor.cjs dashboard-data
```

`start` 成功后，`status` 输出里会带上本地 dashboard 地址；默认配置下通常是 [http://127.0.0.1:4635/](http://127.0.0.1:4635/)。页面会显示：

- 当前 monitor 的运行状态
- 当前活跃的会话 id / MR id 列表
- 最近巡检记录，包括触发时间、分析结果，以及给哪些会话发过消息
