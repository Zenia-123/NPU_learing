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

## 学习文档约定

- `docs/` 存放分章节教学 Markdown。
- 章节文件命名为 `lesson-01-overview.md`、`lesson-02-rtl-mac.md` 等。
- `notes/` 可放个人实验日志、波形分析与问题记录。
- 每讲说明对应的 tiny-NPU 源码路径、硬件设计意图、数据流/控制流、关键 RTL 语法、仿真与验证方法。

每次生成教学文档时在当前对话中同步提交 GitHub，并提供提交后的文件链接；需要确保相关仓库的 GitHub 连接仍可用。