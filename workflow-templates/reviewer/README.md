# Reviewer 工作流

这是一个可复用模板包，用于初始化“Claude 完成主任务，随后通过安装后的 launcher 启动外部 Codex reviewer 子进程做结构化 review，并按 review 结果自动迭代修订”的 Claude Code 工作流。

当前版本只提供 Claude Code 宿主入口，采用与 `workflow-templates/dual-model-consensus` 相近的目录分层：

- `common/`：共享协议、launcher、schemas 与 prompts
- `claude/`：Claude Code 宿主专属入口与安装脚本
- `tests/`：安装器回归测试

支持两类审查制品：

- `code`：Claude 修改代码后，Codex 在与主 agent 相同的工作区中基于 `git diff`、文件列表和必要片段进行 review
- `doc`：Claude 产出计划、分析、说明等文档后，Codex 基于文档正文进行 review

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
  claude/
    skill/
    init.sh
  tests/
    installers.sh
  init.sh
  README.md
```

## 触发方式

安装后通过 `CLAUDE.md` 和 `.claude/skills/reviewer/` 暴露入口；实际执行通道由安装后的 launcher `.claude/skills/reviewer/bin/reviewer-run.sh` 提供。

该 skill 只在用户显式要求使用 reviewer 工作流时启用，例如：

```text
请使用 reviewer skill 完成这个任务并进行 Codex 审查循环。
```

不要默认对所有普通请求自动附加该流程。

如果后续需要“所有任务完成后自动审查”，应通过 Claude Code 的 settings hook 进行接入，而不是修改当前 skill 的显式触发语义。

## `CLAUDE.md` 示例文案

可以在项目根目录的 `CLAUDE.md` 中加入下面这段，作为对 Claude 的显式触发说明：

```md
## Reviewer 工作流

当用户明确要求“使用 reviewer skill”或“完成后交给 Codex review”时，优先使用：

- `.claude/skills/reviewer/SKILL.md`

不要默认对所有任务启用该流程，只有用户显式要求时才触发。

该工作流支持两类制品：

- `code`：代码任务，基于 `git diff` 做审查
- `doc`：计划、分析、说明文档，基于文档正文做审查

默认最多执行 `5` 轮 Codex 审查循环；如果用户指定轮次，则按用户要求执行。

若达到轮次上限仍未通过，输出争议点并交由人类裁决。
```

当前模板安装器会自动把等价说明 upsert 到目标项目的 `CLAUDE.md` 中，并明确写入 launcher 路径、schema 路径以及默认模型约定。

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
2. 将当前结果写入 `.claude/plans/<topic-slug>/`
3. 通过 `.claude/skills/reviewer/bin/reviewer-run.sh` 启动外部 Codex reviewer 子进程返回结构化 `pass/fail + issues`
4. Claude 根据 findings 修订或提出疑问
5. 反复循环，直到通过或达到轮次上限
6. 若仍未通过，输出 `dispute-report.md`

如果你希望用户在项目里更容易发现这个入口，也可以把上面的触发示例直接复制到团队使用的 `CLAUDE.md` 模板中。

## 安装方式

安装 Claude Code 版本：

```bash
./workflow-templates/reviewer/init.sh /path/to/target-project
```

或显式调用 Claude 安装器：

```bash
./workflow-templates/reviewer/claude/init.sh /path/to/target-project
```

安装结果包括：

- `.claude/skills/reviewer/`
- `.claude/skills/reviewer/prompts/`
- `.claude/skills/reviewer/schemas/`
- `.claude/skills/reviewer/bin/reviewer-run.sh`
- `.claude/plans/`
- `CLAUDE.md` 中的 reviewer 工作流区块

## 工作流概览

1. Claude 先完成用户主任务。
2. 控制器将当前结果写入 `.claude/plans/<topic-slug>/draft-r1.md`。
3. 控制器调用 `.claude/skills/reviewer/bin/reviewer-run.sh`，由它在当前工作区中以 `codex exec -C <project> -s read-only` 做 review，并要求返回严格 JSON。
4. 若 review 通过，则生成 `final.md`。
5. 若 review 未通过，Claude 逐条判断 issue：
   - 属实则修改
   - 存疑则提出问题
   - 不成立则说明理由
6. 控制器将最新制品、上一轮 review、以及 Claude 回应再次发给 Codex。
7. 循环直至通过，或达到最大轮次；默认 `5` 轮。
8. 若达到上限仍未通过，则生成 `dispute-report.md`，交由人类裁决。

## 环境变量

launcher 默认使用：

- `REVIEWER_CODEX_BIN`：外部 Codex CLI，可覆盖可执行文件路径；未设置时回退到 `IMPLEMENTATION_LOOP_CODEX_BIN`，再回退到 `codex`
- `REVIEWER_CODEX_REVIEW_MODEL`：外部 reviewer 模型；未设置时回退到兼容变量，最终默认 `gpt-5.4`

reviewer launcher 固定在当前项目目录执行 `codex exec -C <project> -s read-only`，不会创建 worktree、临时副本或其他看不到未提交改动的隔离环境。

## 手动执行 launcher

安装后，Claude 宿主应优先调用 launcher，而不是在对话里手工模拟外部 reviewer：

```bash
.claude/skills/reviewer/bin/reviewer-run.sh review \
  --task "修复登录页表单校验问题" \
  --artifact-type code \
  --topic login-validation-fix \
  --round 1 \
  --max-rounds 5 \
  --artifact .claude/plans/login-validation-fix/draft-r1.md
```

达到轮次上限后，可用同一通道生成分歧报告：

```bash
.claude/skills/reviewer/bin/reviewer-run.sh dispute \
  --task "修复登录页表单校验问题" \
  --artifact-type code \
  --topic login-validation-fix \
  --max-rounds 5 \
  --latest-artifact .claude/plans/login-validation-fix/revision-r5.md \
  --latest-review .claude/plans/login-validation-fix/review-r5.md \
  --latest-response .claude/plans/login-validation-fix/response-r5.md
```

## 自检

运行以下测试验证安装器：

```bash
bash workflow-templates/reviewer/tests/installers.sh
```
