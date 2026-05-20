# Reviewer 工作流

这是一个可复用模板包，用于初始化“主 agent 完成主任务，随后由 reviewer 角色做结构化 review，并按 review 结果自动迭代修订”的 reviewer 工作流。

当前模板同时提供两种宿主入口：

- `codex/`：面向 Codex，安装到 `.codex/skills/reviewer/` 并通过 `AGENTS.md` 暴露入口
- `claude/`：面向 Claude Code，安装到 `.claude/skills/reviewer/` 并通过 `CLAUDE.md` 暴露入口

两种宿主的 reviewer 执行路径不同：

- Codex 宿主：当前主会话优先 `spawn_agent` 一个新的只读 reviewer subagent；不应再通过 shell 去跑 `codex exec`
- Claude 宿主：继续通过当前项目目录中的 `codex exec -C <project> -s read-only` 启动外部 reviewer

目录分层如下：

- `common/`：共享协议、launcher、schemas 与 prompts
- `codex/`：Codex 宿主专属入口与安装脚本
- `claude/`：Claude Code 宿主专属入口与安装脚本
- `tests/`：安装器回归测试

支持两类审查制品：

- `code`：主 agent 修改代码后，Codex 在与主 agent 相同的工作区中基于 `git diff`、文件列表和必要片段进行 review
- `doc`：主 agent 产出计划、分析、说明等文档后，Codex 基于文档正文进行 review

## 目录结构

```text
workflow-templates/reviewer/
  common/
    bin/
      reviewer-run.sh
    schemas/
      codex-review.schema.json
    reference.md
    prompts/
  codex/
    skill/
    init.sh
  claude/
    skill/
    init.sh
  tests/
    installers.sh
  init.sh
  README.md
```

## 触发方式

安装后通过宿主对应的入口文件暴露能力：

- Codex：`AGENTS.md` + `.codex/skills/reviewer/`
- Claude Code：`CLAUDE.md` + `.claude/skills/reviewer/`

Codex 宿主的首选执行通道是 reviewer subagent；Claude 宿主和兼容回归场景仍可使用安装后的 launcher `.../skills/reviewer/bin/reviewer-run.sh`。

该 skill 只在用户显式要求使用 reviewer 工作流时启用，例如：

```text
请使用 reviewer skill 完成这个任务并进行 Codex 审查循环。
```

不要默认对所有普通请求自动附加该流程。

如果后续需要“所有任务完成后自动审查”，应通过宿主自己的 hook 或设置机制接入，而不是修改当前 skill 的显式触发语义。

## 入口文案示例

Codex 项目的 `AGENTS.md` 可加入：

```md
## Reviewer 工作流

当用户明确要求“使用 reviewer skill”或“完成后交给 Codex review”时，优先使用：

- `.codex/skills/reviewer/SKILL.md`

不要默认对所有任务启用该流程，只有用户显式要求时才触发。

该工作流支持两类制品：

- `code`：代码任务，基于 `git diff` 做审查
- `doc`：计划、分析、说明文档，基于文档正文做审查

默认最多执行 `5` 轮 Codex 审查循环；如果用户指定轮次，则按用户要求执行。

若达到轮次上限仍未通过，输出争议点并交由人类裁决。
```

Claude 项目的 `CLAUDE.md` 也可加入等价说明，只需把 skill 路径替换为 `.claude/skills/reviewer/SKILL.md`。

当前模板安装器会自动把等价说明 upsert 到目标项目对应的入口文件中。对于 Codex 宿主，会优先把主路径描述成 reviewer subagent；launcher 仅作为兼容信息保留。

## 使用说明

### 代码任务

```text
请使用 reviewer skill 完成这个 bug 修复，修完后让 Codex CLI 做审查循环。
```

推荐补充的信息：

- 任务目标
- 约束条件
- 是否限制最大轮次

例如：

```text
请使用 reviewer skill 修复登录页表单校验问题，最多审查 3 轮，修完后交给 Codex review。
```

### 文档任务

```text
请使用 reviewer skill 产出这份迁移方案文档，并在完成后交给 Codex 做文档审查。
```

例如：

```text
请使用 reviewer skill 写一份 Redis 缓存迁移方案，默认轮次即可，完成后交给 Codex review。
```

### 结果预期

触发后，工作流会：

1. 先完成主任务
2. 将当前结果写入宿主对应的 `.codex/plans/<topic-slug>/` 或 `.claude/plans/<topic-slug>/`
3. 由 reviewer 返回结构化 `pass/fail + issues`
4. 主 agent 根据 findings 修订或提出疑问
5. 反复循环，直到通过或达到轮次上限
6. 若仍未通过，输出 `dispute-report.md`

## 安装方式

默认安装 Codex 版本：

```bash
./workflow-templates/reviewer/init.sh /path/to/target-project
```

显式安装 Codex 版本：

```bash
./workflow-templates/reviewer/init.sh --codex /path/to/target-project
./workflow-templates/reviewer/codex/init.sh /path/to/target-project
```

显式安装 Claude Code 版本：

```bash
./workflow-templates/reviewer/init.sh --claude /path/to/target-project
./workflow-templates/reviewer/claude/init.sh /path/to/target-project
```

Codex 版安装结果包括：

- `.codex/skills/reviewer/`
- `.codex/skills/reviewer/prompts/`
- `.codex/skills/reviewer/schemas/`
- `.codex/skills/reviewer/bin/reviewer-run.sh`（兼容/回归用途，不是首选执行路径）
- `.codex/plans/`
- `AGENTS.md` 中的 reviewer 工作流区块

Claude 版安装结果包括：

- `.claude/skills/reviewer/`
- `.claude/skills/reviewer/prompts/`
- `.claude/skills/reviewer/schemas/`
- `.claude/skills/reviewer/bin/reviewer-run.sh`
- `.claude/plans/`
- `CLAUDE.md` 中的 reviewer 工作流区块

## 工作流概览

1. 当前宿主会话先完成用户主任务。
2. 控制器将当前结果写入宿主对应的 plans 目录中的 `draft-r1.md`。
3. Codex 宿主优先 `spawn_agent` 一个新的 reviewer subagent；Claude 宿主调用安装后的 `reviewer-run.sh`，由它在当前工作区中以 `codex exec -C <project> -s read-only` 做 review，并要求返回严格 JSON。
4. 若 review 通过，则生成 `final.md`。
5. 若 review 未通过，当前宿主逐条判断 issue：
   - 属实则修改
   - 存疑则提出问题
   - 不成立则说明理由
6. 控制器将最新制品、上一轮 review、以及本轮回应再次发给 Codex。
7. 循环直至通过，或达到最大轮次；默认 `5` 轮。
8. 若达到上限仍未通过，则生成 `dispute-report.md`，交由人类裁决。

## 环境变量

launcher 默认使用：

- `REVIEWER_CODEX_BIN`：外部 Codex CLI，可覆盖可执行文件路径；未设置时回退到 `IMPLEMENTATION_LOOP_CODEX_BIN`，再回退到 `codex`
- `REVIEWER_CODEX_REVIEW_MODEL`：外部 reviewer 模型；未设置时回退到兼容变量，最终默认 `gpt-5.4`

这些环境变量主要用于 Claude 宿主和兼容 launcher 路径。Codex 宿主的首选路径仍然是 reviewer subagent，而不是 shell launcher。

## 手动执行 launcher

安装后：

- Codex 宿主应优先 `spawn_agent` 一个新的 reviewer subagent，并把完整渲染后的 `codex-review-request.md` prompt 发送给它
- Claude 宿主应优先调用 launcher，而不是在对话里手工模拟外部 reviewer

Codex 版示例（首选路径）：

1. 由当前主会话渲染 `.codex/skills/reviewer/prompts/codex-review-request.md`
2. `spawn_agent` 一个新的只读 reviewer subagent
3. 把完整渲染后的 prompt 发给它
4. 将返回 JSON 原样保存为 `.codex/plans/<topic-slug>/review-rN.md`

Claude 版示例：

```bash
.claude/skills/reviewer/bin/reviewer-run.sh review \
  --task "修复登录页表单校验问题" \
  --artifact-type code \
  --topic login-validation-fix \
  --round 1 \
  --max-rounds 5 \
  --artifact .claude/plans/login-validation-fix/draft-r1.md
```

达到轮次上限后，Claude/兼容 launcher 路径可用同一通道生成分歧报告，例如：

```bash
.codex/skills/reviewer/bin/reviewer-run.sh dispute \
  --task "修复登录页表单校验问题" \
  --artifact-type code \
  --topic login-validation-fix \
  --max-rounds 5 \
  --latest-artifact .codex/plans/login-validation-fix/revision-r5.md \
  --latest-review .codex/plans/login-validation-fix/review-r5.md \
  --latest-response .codex/plans/login-validation-fix/response-r5.md
```

## 自检

运行以下测试验证安装器：

```bash
bash workflow-templates/reviewer/tests/installers.sh
```
