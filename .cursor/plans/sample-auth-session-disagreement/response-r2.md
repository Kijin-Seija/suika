# 第 2 轮修订响应

## 评审响应
1. Mobile session model is not executable as written
   - decision: partially-accepted
   - action: 改为由移动端在登录后换取短期 session token，但仍尽量复用服务端 Session 存储。
   - rationale: 希望保留“统一服务端会话状态”的核心方向，不直接拆成两套完全独立方案。
2. Validation lacks measurable migration criteria
   - decision: accepted
   - action: 增加登录成功率、续期成功率和重新登录率指标。
