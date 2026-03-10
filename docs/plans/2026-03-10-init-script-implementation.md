# Init Script Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为 `workflow-templates/dual-model-consensus-plan` 添加一个一键初始化脚本，自动把模板复制到目标项目并幂等更新目标项目的 `AGENTS.md`。

**Architecture:** 使用一个轻量的 `bash` 脚本作为初始化入口，接收目标项目路径，负责建目录、复制模板文件、写入带哨兵标记的 `AGENTS.md` 工作流区块。通过一个 shell 集成测试脚本在临时目录中验证初始化结果与重复执行行为。

**Tech Stack:** `bash`, `mktemp`, `cmp`, `grep`-free shell assertions, Markdown 文档

---

### Task 1: 写初始化脚本的失败测试

**Files:**
- Create: `workflow-templates/dual-model-consensus-plan/tests/test-init.sh`
- Test: `workflow-templates/dual-model-consensus-plan/tests/test-init.sh`

**Step 1: Write the failing test**

编写一个 shell 集成测试，覆盖以下行为：
- 对临时目标项目执行 `init.sh`
- 断言目标目录被创建
- 断言 `SKILL.md`、`reference.md`、四个 prompt、两个 agent、文档文件被复制到预期位置
- 断言 `AGENTS.md` 被创建并包含带哨兵标记的工作流区块
- 再执行一次 `init.sh`
- 断言 `AGENTS.md` 中该区块未重复追加

**Step 2: Run test to verify it fails**

Run: `bash workflow-templates/dual-model-consensus-plan/tests/test-init.sh`
Expected: FAIL，因为 `init.sh` 尚不存在

**Step 3: Write minimal implementation**

暂不实现，进入下一任务。

**Step 4: Run test to verify it still reflects missing feature**

Run: `bash workflow-templates/dual-model-consensus-plan/tests/test-init.sh`
Expected: FAIL，且失败原因与缺失初始化脚本一致

**Step 5: Commit**

不提交，除非用户明确要求。

### Task 2: 实现初始化脚本

**Files:**
- Create: `workflow-templates/dual-model-consensus-plan/init.sh`
- Modify: `workflow-templates/dual-model-consensus-plan/tests/test-init.sh`

**Step 1: Write the minimal script**

实现一个 `bash` 脚本，要求：
- 参数：`<target-project>`
- 校验目标路径存在且为目录
- 创建目标目录：
  - `.cursor/skills/dual-model-consensus-plan/`
  - `.cursor/prompts/dual-model-consensus-plan/`
  - `.cursor/agents/`
  - `.cursor/plans/`
  - `docs/ai/`
- 复制模板文件到目标项目
- 生成或更新 `AGENTS.md`
- 使用固定哨兵实现幂等替换：
  - `<!-- BEGIN dual-model-consensus-plan -->`
  - `<!-- END dual-model-consensus-plan -->`

**Step 2: Run targeted test**

Run: `bash workflow-templates/dual-model-consensus-plan/tests/test-init.sh`
Expected: PASS

**Step 3: Refactor**

若需要，提取小型 shell 函数：
- `copy_file`
- `upsert_agents_block`
- `require_dir`

**Step 4: Run test to verify it still passes**

Run: `bash workflow-templates/dual-model-consensus-plan/tests/test-init.sh`
Expected: PASS

**Step 5: Commit**

不提交，除非用户明确要求。

### Task 3: 更新 README

**Files:**
- Modify: `workflow-templates/dual-model-consensus-plan/README.md`
- Test: `workflow-templates/dual-model-consensus-plan/tests/test-init.sh`

**Step 1: Add one-command usage**

在 `README.md` 中新增：
- 一键初始化命令
- 脚本做了什么
- 重复执行的幂等行为
- 失败时的常见提示

**Step 2: Run test to ensure docs align with script behavior**

Run: `bash workflow-templates/dual-model-consensus-plan/tests/test-init.sh`
Expected: PASS

**Step 3: Manual verification**

Run: `bash workflow-templates/dual-model-consensus-plan/init.sh "$(mktemp -d)/demo-project"`
Expected: 创建完成并输出初始化摘要

**Step 4: Commit**

不提交，除非用户明确要求。
