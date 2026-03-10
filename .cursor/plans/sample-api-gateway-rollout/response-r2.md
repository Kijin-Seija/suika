# 第 2 轮修订响应

## 评审响应
1. Shared rate-limit service is assumed but not established
   - decision: accepted
   - action: 将首期实现改为网关直接使用 Redis 计数器，不再依赖未确认存在的统一限流服务。
2. Validation does not define rollout success criteria
   - decision: accepted
   - action: 增加灰度成功标准，覆盖正确性、延迟和误拦截率。
