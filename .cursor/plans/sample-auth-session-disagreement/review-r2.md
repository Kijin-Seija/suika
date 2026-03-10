# 第 2 轮评审

## 结论
- status: revision-required
- blocking-issues: 1
- important-issues: 1
- minor-issues: 0

## 问题项
1. Mobile renewal path is still underspecified
   - severity: blocking
   - rationale: 计划引入“短期 session token”，但没有说明 token 过期后的续期机制，移动端可能被迫频繁重新登录。
   - requested change: 明确移动端续期链路，是通过 refresh token、重新换取 session token，还是继续依赖服务端 Session 续期。
2. Scope does not limit offline behavior
   - severity: important
   - rationale: 文档把“离线续期能力”留为开放问题，但没有说明首期是否明确不做，范围边界仍然模糊。
   - requested change: 说明首期是否不支持离线续期，并把非目标写进 Scope。

## 修改计划
1. 补足移动端 token 续期链路。
2. 把离线续期是否纳入首期范围写清楚。

## 接受性检查
- acceptable-without-further-revision: no
