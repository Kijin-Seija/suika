---
name: vitest-safe
description: 当任务需要执行项目测试，尤其是 Vitest、由 Vitest 驱动的 package test 脚本或完整测试套件，或用户显式调用 /vitest-safe 时使用；通过全局 vitest-safe 队列运行命令，避免多个测试进程同时耗尽内存。
---

# Vitest 安全执行

## 适用范围

只要命令会执行项目测试，就必须使用这个 skill。包括直接调用 `vitest`、`pnpm exec vitest`、`npm exec vitest`，以及经过 `package.json` 脚本间接启动 Vitest 的命令（例如 `pnpm test`、`pnpm --filter <package> test`）；其他测试框架的测试命令也走同一个队列。

先查看项目脚本，确认一个看起来普通的 `test` 命令是否实际调用了 Vitest；确认后也必须走队列。

## 强制执行方式

不要直接运行原始 Vitest 命令。把原命令放在 `--` 后交给全局包装器：

```bash
vitest-safe -- pnpm exec vitest run
vitest-safe -- pnpm --filter <package> test
vitest-safe -- npm run test -- --run
```

安装器会把包装器放在 Claude Code 全局目录的 `bin/vitest-safe`，并在全局 `CLAUDE.md` 写入同样的硬性规则。如果当前 shell 找不到 `vitest-safe`，使用该绝对路径，或先按模板 README 完成全局安装；不要退回直接执行测试。

## 队列行为

- 安装默认最多允许 2 个 Vitest 命令同时运行。
- 安装时可用 `--max-concurrent <正整数>` 修改上限。
- 超过上限的调用会阻塞等待可用 slot；等待期间不要重复启动同一测试。
- 包装器使用内核原子文件锁，并在获得 slot 后替换为真实测试进程。测试正常结束、被终止或崩溃时，锁都会由内核释放，不需要手工清理锁文件。

## 组合测试与并行参数

先控制外层 Vitest 进程数量，再考虑 Vitest 自身的 worker 数量。需要降低单个套件的内存占用时，可以把参数传给原始命令，例如：

```bash
vitest-safe -- pnpm exec vitest run --maxWorkers=2 --no-file-parallelism
```

不要为了绕过队列而并行启动多个完整测试套件；如果已有调用在等待或运行，继续使用现有队列。
