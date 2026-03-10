# 第 1 轮评审

## 结论
- status: revision-required
- blocking-issues: 1
- important-issues: 1
- minor-issues: 0

## 问题项
1. Mobile session model is not executable as written
   - severity: blocking
   - rationale: 移动端并不总是运行在可稳定共享 Cookie 的 WebView 环境中，计划把移动端统一成 Cookie Session 会导致原生客户端场景无法落地。
   - requested change: 明确移动端的会话载体与续期机制，不要把“复用 Cookie”当成统一方案。
2. Validation lacks measurable migration criteria
   - severity: important
   - rationale: “投诉量没有明显上升”无法作为工程验收标准。
   - requested change: 增加登录成功率、续期成功率和强制重新登录率等指标。

## 修改计划
1. 重新定义移动端登录态载体与续期路径。
2. 把验收标准改成可量化指标。

## 接受性检查
- acceptable-without-further-revision: no
