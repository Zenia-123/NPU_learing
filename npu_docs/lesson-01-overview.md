# tiny-NPU 系统学习指南

仓库：https://github.com/harishsg993010/tiny-NPU

## 学习定位

从算法→微架构→数据流/控制流→SystemVerilog RTL→仿真验证→性能分析逐步掌握 NPU，并衔接 CIMFlow 和 MRAM-CIM。

## 14 讲课程

1. 项目总览与架构分层
2. 数字电路时序与 INT8 MAC 流水线
3. PE 架构：数据转发与 INT8/FP16
4. 二维脉动阵列和逐周期映射
5. GEMM Controller、Tiling、写回
6. 存储层次、SRAM Bank、Buffer
7. AXI、DMA、传输握手
8. 微码指令集和 Fetch/Decode/Dispatch
9. Scoreboard、Barrier、调度和依赖
10. Softmax、LayerNorm、GELU、LUT
11. Transformer 和 KV Cache 数据流
12. ONNX Compiler、Graph ISA、Tensor Descriptor
13. Verilator 仿真、Testbench、Golden Model、性能测量
14. 架构优化与 CIMFlow/MRAM-CIM 研究衔接

## 核心代码阅读顺序

- `rtl/pkg/npu_pkg.sv`：全局参数
- `rtl/gemm/mac_int8.sv`：两级流水 MAC
- `rtl/gemm/pe.sv`：单 PE 包装、传递寄存器和计算选择
- `rtl/gemm/systolic_array.sv`：二维阵列连线和有效性控制
- `rtl/gemm/gemm_ctrl.sv`：GEMM 调度
- `rtl/mem/sram_dp.sv`, `banked_sram.sv`：片上存储
- `rtl/bus/axi_dma_rd.sv`, `axi_dma_wr.sv`：DMA
- `rtl/ctrl/ucode_fetch.sv`, `ucode_decode.sv`, `scoreboard.sv`：控制路径
- `rtl/ops/`：专用计算引擎
- `rtl/graph/`, `python/onnx_compiler/`：图执行与编译
- `sim/verilator/`：验证环境

## 第一讲：项目结构及前置知识

tiny-NPU 使用 SystemVerilog 实现 RTL，README 描述 LLM 与 Graph 两种执行模式。默认 GEMM 脉动阵列为 16×16，含 256 个 MAC 位置；片上主 SRAM0 为 64 KB，SRAM1 为 8 KB。LLM 使用 128-bit 微码；Graph 支持 ONNX 编译和图指令执行。

必须掌握六个知识块：

1. 数字电路：组合逻辑、时序逻辑、D 触发器、FSM、握手和流水线。
2. SystemVerilog：module、parameter、port、logic、wire、always_ff/always_comb、非阻塞赋值、generate。
3. AI 数学：MAC、GEMM/GEMV、卷积、矩阵维度及 Transformer 的注意力。
4. NPU 架构：PE、Systolic Array、Tiling、数据复用、利用率。
5. 存储互连：SRAM Bank、缓冲、DDR、DMA、AXI、带宽。
6. 仿真验证：Verilator、C++ testbench、Python golden、VCD 波形和 Makefile。

### MAC 与 PE 的关键区别

MAC 计算 `acc <- acc + a*b`；PE 除乘加外还含数据向邻居转发和控制。在 `rtl/gemm/pe.sv` 中，A 向右传，B 向下传；INT8 与 FP16 有独立路径。 `rtl/gemm/mac_int8.sv` 中乘法和累加为两级流水，读取寄存器和时钟沿必须逐周期理解。

对于 GEMM `C[M,N] = A[M,K] × B[K,N]`，脉动阵列通过偏斜输入、逐拍传递及在各 PE 内累加形成结果。后续逐周期分析填充、有效计算、排空与 Tile 切换。

## 学习方法与验证闭环

每讲按以下顺序：硬件需求→模块划分→数据/控制通路→时序表→实际源码→必要语言语法→测试脚本→波形证据→与 CIMFlow 的映射。

建议在 Linux 环境安装 Git、Python、Make、G++、Verilator、GTKWave；先检查 `make help`、`make lint` 和 `make test`，再根据构建报错选择修正步骤。README 和不同构建路径的源码集合可能不同，不应把“仓库有功能”自动等同于“根目录 Makefile 都会编译”。

## 第一讲后续入口

第二讲从 `rtl/gemm/mac_int8.sv` 开始，详解时序逻辑、两级流水、寄存器更新、饱和累加，并建立可追踪的时钟周期表。
