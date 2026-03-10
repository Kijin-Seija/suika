# 第 1 轮评审

## 结论
- status: revision-required
- blocking-issues: 1
- important-issues: 1
- minor-issues: 0

## 问题项
1. Shared rate-limit service is assumed but not established
   - severity: blocking
   - rationale: 计划把核心能力建立在“平台已提供统一限流服务”的前提上，但文档没有说明若该能力不存在或不足时的首期实现方案，导致计划不可执行。
   - requested change: 明确首期限流状态存储与计数实现，说明是复用现有组件还是在网关内新增 Redis 方案。
2. Validation does not define rollout success criteria
   - severity: important
   - rationale: 目前验证只有“压测”和“灰度环境验证”，但缺少具体指标，无法判断发布是否成功。
   - requested change: 为功能正确性、性能开销和误拦截率增加明确验收指标。

## 修改计划
1. 将首期限流实现说明补全，消除对未证实平台能力的依赖。
2. 增加灰度验收指标，包括 `429` 命中率、P95 延迟增量和误拦截阈值。

## 接受性检查
- acceptable-without-further-revision: no
