# 第 3 轮修订响应

## 评审响应
1. Mobile renewal path is still underspecified
   - decision: partially-accepted
   - action: 补充移动端可通过 refresh token 重新换取短期 session token。
   - rationale: 仍然坚持由服务端 Session 作为统一状态源，不改成完全独立的移动端认证模型。
2. Scope does not limit offline behavior
   - decision: accepted
   - action: 明确首期不支持离线续期，并把它放入非目标范围。
