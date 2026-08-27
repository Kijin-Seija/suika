# Vitest Safe

这是一个兼容 Codex 与 Claude Code 的全局 skill 模板，用原子文件锁把测试命令放进同一个共享队列，限制同时运行的完整测试进程数量。

它包含根入口、Codex/Claude Code 安装器、skill、可执行 helper 和安装器测试；区别是安装目标是宿主全局目录，不需要传入项目路径。

## 安装

在 `suika` 仓库根目录执行：

```bash
bash workflow-templates/vitest-safe/init.sh
```

默认最多允许 2 个 Vitest 命令同时运行。安装时可以修改上限：

```bash
bash workflow-templates/vitest-safe/init.sh --max-concurrent 4
```

安装器默认使用 `${CODEX_HOME:-$HOME/.codex}`，也支持通过 `CODEX_HOME` 指向隔离的 Codex 配置目录。它会：

- 将 `codex/skill` 以 symlink 安装到 `$CODEX_HOME/skills/vitest-safe/`
- 将 `vitest-safe` 包装器安装到 `$CODEX_HOME/bin/vitest-safe`
- 写入 `$CODEX_HOME/vitest-safe/config.json`
- 在 `$CODEX_HOME/AGENTS.md` 中维护强制通过 wrapper 执行 Vitest 的规则

Claude Code 版使用 `${CLAUDE_HOME:-$HOME/.claude}`：

```bash
bash workflow-templates/vitest-safe/init.sh --claude --max-concurrent 2
```

它安装到 `$CLAUDE_HOME/skills` 和 `$CLAUDE_HOME/bin`，并维护 `$CLAUDE_HOME/CLAUDE.md`。两种宿主的描述配置分别保存在各自 home 下，但实际运行配置与锁池共享 `${VITEST_SAFE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/suika-vitest-safe}`。

如果希望直接输入 `vitest-safe`，把对应宿主的 `$CODEX_HOME/bin` 或 `$CLAUDE_HOME/bin` 加入 shell 的 `PATH`；也可以按全局指令文件使用绝对路径。

## 使用

在 Claude Code 中可通过 `/vitest-safe` 显式调用；实际测试命令仍统一使用 `vitest-safe -- <原命令>`。

所有测试命令（尤其是确认会启动 Vitest 的命令）都必须写成：

```bash
vitest-safe -- pnpm exec vitest run
vitest-safe -- pnpm --filter @writer/writer-next test
vitest-safe -- npm run test -- --run
```

如果直接命令找不到，使用：

```bash
"${CODEX_HOME:-$HOME/.codex}/bin/vitest-safe" -- pnpm exec vitest run
"${CLAUDE_HOME:-$HOME/.claude}/bin/vitest-safe" -- pnpm exec vitest run
```

超过并发上限的调用会等待 slot；wrapper 使用 `fcntl.flock`，锁由内核管理，测试进程退出或崩溃时会自动释放。

需要降低单个 Vitest 进程的 worker 数量时，仍把参数传给原始命令：

```bash
vitest-safe -- pnpm exec vitest run --maxWorkers=2 --no-file-parallelism
```

## 卸载

```bash
bash workflow-templates/vitest-safe/init.sh --remove
bash workflow-templates/vitest-safe/init.sh --claude --remove
```

卸载只删除对应宿主的 skill、wrapper、描述配置和规则区块；共享运行配置与锁目录会保留，避免打断另一个宿主或正在运行的测试。

## 自检

```bash
bash workflow-templates/vitest-safe/tests/installers.sh
```
