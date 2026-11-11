# tiny-NPU项目主线文档

本目录专门存放tiny-NPU项目讲解；课程作业讲义继续保留在../docs/assignment-*.md，作业代码、验证日志和波形继续保留在../assignments/。

当前进度与接手规则见[主线交接](handoff-tiny-npu-mainline.md)及[总交接](../HANDOFF.md)。

## 讲解要求

后续对话先阅读[硬件与代码讲解要求](TEACHING_GUIDELINES.md)：新模块先讲硬件/架构和数据、控制及适用的指令流；代码按原文件顺序逐段先讲逻辑、再讲代码，并解释变量和时序。

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
| 07精读 | axi_dma_rd逐段与变量 | [读DMA源码顺序精读](lesson-07-axi-dma-rd-code-walkthrough.md) |
| 07下 | DMA与AXI写通路 | [axi_dma_wr](lesson-07-dma-axi-write.md) |
| 07精读 | axi_dma_wr逐段与变量 | [写DMA源码顺序精读](lesson-07-axi-dma-wr-code-walkthrough.md) |
| 07补充 | SRAM与AXI的位宽适配 | [8 bit与128 bit适配](lesson-07-sram-axi-width-adapter.md) |
| 08上 | 取指与微码 | [ucode_fetch](lesson-08-ucode-fetch.md) |

第07讲已按用户要求重新精读axi_dma_rd和axi_dma_wr源码与变量；第08讲fetch也已讲解，尚未确认掌握。优先回答当前具体问题；后续按进度进入Decode/Dispatch与Scoreboard。

## 学习地图与历史资料

- [完整学习指南](tiny-npu-study-guide.md)
- [GEMM后快速复习](review-gemm-before-memory-2026-11-06.md)
- [第03讲后历史交接](handoff-after-lesson-03.md)
- [gemm_post后历史交接](handoff-after-gemm-post-2026-10-31.md)

历史交接仅保存当时的阶段记录，当前停点以主线交接和根目录HANDOFF.md为准。

## 文档约定

按“硬件结构→变量含义与单位→数据/控制流→代码顺序与时序”讲解；每次完整主线Markdown同步到main分支的npu_docs/，报告真实commit。已讲过不等于已掌握，不额外布置练习题。需要实验时由用户亲自编写和执行，未经明确要求不代运行。
