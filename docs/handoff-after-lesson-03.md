# tiny-NPU 学习交接摘要：第 03 讲结束

## 当前进度
已完成第 01 讲项目总览与路线（`docs/lesson-01-overview.md`）、第 02 讲 MAC 流水与 SystemVerilog（`docs/lesson-02-rtl-mac.md`）、第 03 讲 PE 微架构和双精度 MAC（`docs/lesson-03-pe-microarchitecture.md`）。

教学风格：中文、先硬件和数据流再语法和源码、一次深入讲较多内容、不要重复/过多练习。每讲产出完整 Markdown 同步本仓库 `docs/`，当次用 GitHub connector 提交并报告 SHA。目标是从 NPU RTL 学到体系结构，再衔接 CIMFlow/MRAM-CIM。

## 已确认的真实代码结构
上游仓库 <https://github.com/harishsg993010/tiny-NPU>，主要路径：
- `rtl/gemm/mac_int8.sv`：INT8 乘法寄存器 + 累加寄存器，两级流水。
- `rtl/gemm/mac_fp16.sv`：FP16×FP16→FP32 乘积，FP32 累加。
- `rtl/gemm/pe.sv`：A 向东、B 向南转发各一拍；并行例化 INT8、FP16 MAC，依 dtype 选择使能和输出。
- `rtl/gemm/systolic_array.sv`：二维 generate 例化，默认 16×16 PE，256 个 MAC 位置。
- `rtl/gemm/gemm_ctrl.sv`：后续结合阵列研究控制/映射。
- `rtl/mem/`, `rtl/ctrl/`, `rtl/bus/`, `rtl/ops/`, `rtl/graph/`, `python/`, `sim/verilator/`：后续学习。

关键细节：
1. `mac_int8` 在时钟 ↑1 保存 product，↑2 使用此前保存的乘积更新 ACC；enable/clear 同步延迟为 `en_d1`/`clear_d1`。有扩展位的有符号累加与溢出饱和。
2. `pe.sv` 的 MAC 直接使用当前 `a_in,b_in`，转发寄存器同拍保存输入供邻居下拍使用；不要误以为本 PE 计算先经过本 PE 的转发寄存器。
3. INT8/FP16 是两条独立 MAC 路径；32-bit 输出在 INT8 时为整数，在 FP16 时为 FP32 位编码。模式切换与累加清零必须匹配数据批次。
4. `systolic_array.sv` 默认 `PIPE_STAGE=32`，对 16×16 阵列不会插入额外边界流水。A、B 均移动、ACC 本地保留；注释虽称 Weight-stationary，不能据此直接判定实现了权重驻留。
5. 源码 `acc_valid` 基于 `DRAIN_LATENCY=M+N+NUM_A_PIPES+NUM_B_PIPES` 的计数器，并非逐元素 valid；与 K 长度及控制阶段的匹配应核对上层控制/testbench。
6. 根目录 Makefile 的 SV_SRC 未必涵盖仓库全部新模块，“仓库具有该功能”与“当前仿真目标编译该功能”须区分。

## 已讲 2×2 偏斜输入例子
A=[[1,2],[3,4]], B=[[5,6],[7,8]]，C=[[19,22],[43,50]]。理想相对运算周期中：
- t0：PE00 1×5
- t1：PE00 2×7；PE01 1×6；PE10 3×5
- t2：PE01 2×8；PE10 4×7；PE11 3×6
- t3：PE11 4×8
各 PE 本地求和形成输出。但此表为乘积的逻辑相遇时刻，不是 ACC 寄存器更新时刻；还需额外考虑乘法→累加级的延时、清零、en、零填充和 drain。

## 下一步：直接开始第 04 讲
主题：**二维脉动阵列的数据流与逐周期执行**。
按这个顺序：
1. GEMM C[M,N]=A[M,K]×B[K,N]、PE(i,j) 与 K 方向时间复用；
2. 详细 2×2 时钟表（所有 PE 的输入、product、ACC）；随后 3×3 传播；
3. Fill/Steady/Drain、输入偏斜、16×16 阵列周期数、利用率；
4. 分清理想模型 K+M+N−2 及实际 MAC / PIPE_STAGE / acc_valid 影响；
5. 解释 `systolic_array.sv` 的 generate、a_wire/b_wire、a_pipe/b_pipe 和顶层调度；
6. 映射不同形状 GEMM/GEMV、Tiling 与数据复用、后续 PE vs CIM 对比。
最后生成**完整** `docs/lesson-04-systolic-array.md` 并同步 GitHub，附链接及真实提交 SHA。

后续讲次：05 GEMM 控制/Tiling；06 SRAM；07 AXI/DMA；08 ISA；09 Scoreboard/Barrier；10 特殊算子；11 Transformer/KV Cache；12 ONNX Graph；13 仿真性能；14 CIMFlow/MRAM-CIM 研究衔接。

> 新对话指令：按此交接继续第 04 讲，不必重讲前三讲。