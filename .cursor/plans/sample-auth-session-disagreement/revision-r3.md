# 统一登录态策略计划

## 任务理解

需要为 Web 与移动端设计一套统一登录态管理方案，并输出开发计划。

## 目标

- 统一身份校验入口
- 减少现有登录态实现分叉
- 降低迁移期间的用户登录中断风险

## 范围

- 覆盖 Web 与移动端
- 覆盖登录、续期和登出
- 首期不支持离线续期
- 不处理第三方单点登录

## 假设

- Web 继续使用 Cookie Session
- 移动端使用短期 session token，并通过 refresh token 重新换取
- 服务端仍维护统一 Session 存储

## 风险

- Web 与移动端虽然共享服务端状态，但客户端载体已经分化
- refresh token 与服务端 Session 的生命周期映射复杂

## 建议方案

服务端保留统一 Session 存储。Web 使用 Cookie 承载 session ID。移动端在登录后换取短期 session token，请求时由网关解析为同一份服务端 Session。session token 过期后，移动端通过 refresh token 重新换取新的 session token。这样仍可保留统一服务端状态模型，同时避免移动端依赖 Cookie。

## 验证方式

- 登录成功率不低于现网基线
- Session 续期成功率达到 99.9%
- 强制重新登录率不高于现网基线的 0.2%

## 开放问题

- refresh token 是否需要设备级吊销能力

## 执行步骤
1. 抽象统一 Session 存储接口。
2. 保持 Web 的 Cookie Session 路径不变。
3. 为移动端新增 session token 与 refresh token 换取逻辑。
4. 在迁移期观测登录、续期和重新登录指标。
