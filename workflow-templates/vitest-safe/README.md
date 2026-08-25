# Vitest Safe

这是一个可复用的全局 Codex skill 模板，用原子文件锁把测试命令放进共享队列，限制同时运行的完整测试进程数量，重点保护 Vitest，降低 Codex 和多个 Electron/Node 工作流并发时的内存峰值。

它和项目级 skill 模板一样，包含根入口、Codex 安装器、skill、可执行 helper 和安装器测试；区别是安装目标是 Codex 全局目录，不需要传入项目路径。

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

如果希望直接输入 `vitest-safe`，把 `$CODEX_HOME/bin` 加入 shell 的 `PATH`；Codex 也可以按全局 `AGENTS.md` 使用绝对路径。

## 使用

所有测试命令（尤其是确认会启动 Vitest 的命令）都必须写成：

```bash
vitest-safe -- pnpm exec vitest run
vitest-safe -- pnpm --filter @writer/writer-next test
vitest-safe -- npm run test -- --run
```

如果直接命令找不到，使用：

```bash
"${CODEX_HOME:-$HOME/.codex}/bin/vitest-safe" -- pnpm exec vitest run
```

超过并发上限的调用会等待 slot；wrapper 使用 `fcntl.flock`，锁由内核管理，测试进程退出或崩溃时会自动释放。

需要降低单个 Vitest 进程的 worker 数量时，仍把参数传给原始命令：

```bash
vitest-safe -- pnpm exec vitest run --maxWorkers=2 --no-file-parallelism
```

## 卸载

```bash
bash workflow-templates/vitest-safe/init.sh --remove
```

卸载只删除本安装器创建的 skill/wrapper symlink、配置文件和规则区块；如果已有其他程序正在使用锁文件，锁目录会保留，避免打断运行中的测试。

## 自检

```bash
bash workflow-templates/vitest-safe/tests/installers.sh
```
