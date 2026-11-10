# NPU Learning / tiny-NPU 系统学习

这是学习 [tiny-NPU](https://github.com/harishsg993010/tiny-NPU) 的个人笔记仓库，目标是从 RTL 硬件设计逐步深入到 NPU 体系结构、数据流、仿真验证，以及 CIMFlow / MRAM-CIM 架构研究。

## 学习路线（14 讲）

1. NPU 全局架构与项目概览
2. 数字电路时序与 RTL：MAC 代码
3. PE 微架构与 INT8/FP16 计算
4. 二维脉动阵列与逐周期数据流
5. GEMM Engine：Tiling 与控制
6. SRAM、Bank 与 Buffer
7. DMA 与 AXI 总线
8. ISA、Fetch、Decode、Dispatch
9. Scoreboard、Barrier 与依赖控制
10. Softmax、LayerNorm、GELU 等引擎
11. Transformer 与 KV Cache
12. ONNX 编译、图执行与张量映射
13. Verilator 仿真、Testbench 与性能评估
14. 架构优化与 CIMFlow / MRAM-CIM 衔接

## 教学与交接

学习要求见 [硬件与代码讲解要求](npu_docs/TEACHING_GUIDELINES.md)，继续学习先读取 [HANDOFF.md](HANDOFF.md) 与 [项目主线交接](npu_docs/handoff-tiny-npu-mainline.md)。

## 学习文档约定

- `npu_docs/` 专门存放 tiny-NPU 项目主线讲义、补充、复习与交接，入口：[主线文档目录](npu_docs/README.md)。
- `docs/assignment-*.md` 保留课程作业讲义；`assignments/` 保留作业代码、Testbench、日志与波形。
- [HANDOFF.md](HANDOFF.md) 分别记录项目主线与开放作业支线；继续时依据用户指定方向选择。
- 章节文件命名为 `lesson-01-overview.md`、`lesson-02-rtl-mac.md` 等。
- `notes/` 可放个人实验日志、波形分析与问题记录。
- 每讲说明对应的 tiny-NPU 源码路径、硬件设计意图、数据流/控制流、关键 RTL 语法、仿真与验证方法。

每次生成教学文档时在当前对话中同步提交 GitHub，并提供提交后的文件链接；需要确保相关仓库的 GitHub 连接仍可用。

## 当前主线进度

第01～07讲相关内容和第08讲Fetch已讲解；最近按用户要求回读[axi_dma_rd源码与变量](npu_docs/lesson-07-axi-dma-rd-code-walkthrough.md)。后续优先回答用户当前问题，进度以[主线交接](npu_docs/handoff-tiny-npu-mainline.md)为准；已讲解不等于用户已完全掌握。
