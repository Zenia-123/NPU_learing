# tiny-NPU项目主线文档

本目录专门存放tiny-NPU项目讲解；课程作业讲义继续保留在../docs/assignment-*.md，作业代码、验证日志和波形继续保留在../assignments/。

当前进度与接手规则见[主线交接](handoff-tiny-npu-mainline.md)及[总交接](../HANDOFF.md)。

## 课程

| 讲次 | 主题 | 讲义 |
|---|---|---|
| 01 | 整体架构与学习路线 | [总览](lesson-01-overview.md) |
| 02 | RTL与INT8 MAC | [MAC](lesson-02-rtl-mac.md) |
| 03 | PE微结构 | [PE](lesson-03-pe-microarchitecture.md) |
| 04 | 脉动阵列与逐周期数据流 | [脉动阵列](lesson-04-systolic-array.md) |
| 05 | GEMM源码与控制 | [源码精读](lesson-05-gemm-code-walkthrough.md)、[控制器设计经验](lesson-05-gemm-controller-design-patterns.md)、[gemm_post](lesson-05-gemm-post.md) |
| 06 | SRAM、Bank与Buffer | [存储结构](lesson-06-sram-bank-buffer.md)、[Ping-Pong与流水](lesson-06-supplement-ping-pong-pipeline.md) |
| 07补充 | AXI零基础快速介绍 | [AXI基础](lesson-07-supplement-axi-basics.md) |
| 07上 | DMA与AXI读通路 | [axi_dma_rd](lesson-07-dma-axi-read.md) |

第07讲上已讲解；2026-11-10因用户明确未学过AXI，先补充AXI基础。尚未由用户确认掌握，优先解答AXI问题，再回到DMA源码；原计划后续为axi_dma_wr、宽度适配与本地落存完成，再进入第08讲ISA/Fetch/Decode/Dispatch。

## 学习地图与历史资料

- [完整学习指南](tiny-npu-study-guide.md)
- [GEMM后快速复习](review-gemm-before-memory-2026-11-06.md)
- [第03讲后历史交接](handoff-after-lesson-03.md)
- [gemm_post后历史交接](handoff-after-gemm-post-2026-10-31.md)

历史交接仅保存当时的阶段记录，当前停点以主线交接和根目录HANDOFF.md为准。

## 文档约定

按“硬件结构→变量含义与单位→数据/控制流→代码顺序与时序”讲解；每次完整主线Markdown同步到main分支的npu_docs/，报告真实commit。已讲过不等于已掌握，不额外布置练习题。需要实验时由用户亲自编写和执行，未经明确要求不代运行。
