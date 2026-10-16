

仓库：https://github.com/harishsg993010/tiny-NPU

## 0. 学习定位

目标：从数字电路基础出发，逐层理解一个基于 SystemVerilog 的神经网络推理加速器，包括算法、PE、脉动阵列、片上存储、DMA、微码控制、ONNX 图执行、功能验证与性能建模，最后将这些知识迁移到 CIMFlow 和 MRAM-CIM 架构研究。

原则：先讲 **为什么有这个硬件模块**，再讲 **架构与数据流**，随后讲 **SystemVerilog 语法和具体 RTL**，最后讲 **仿真与性能证据**。不以死记语法代替架构理解。

## 1. 仓库概览

tiny-NPU 是一个用于学习的 RTL NPU。README 描述两个执行模式：

- LLM Mode：128 位微码、Fetch/Decode/Dispatch、Scoreboard、GEMM、Softmax、LayerNorm、GELU、Vec、DMA，以及 Transformer 与 KV Cache 推理流程。
- Graph Mode：面向 ONNX 的计算图编译与执行，Graph ISA、张量描述符表、算子引擎、DMA/GEMM 重叠与 INT8/FP16 混合精度。

默认脉动阵列为 16×16，包含 256 个 PE/MAC 位置；README 描述主 SRAM0 为 64 KB、辅助 SRAM1 为 8 KB。注意：这些是设计默认值和文档设定，不是流片测量数据。

### 1.1 源码地图

| 路径 | 主要功能 | 建议顺序 |
|---|---|---|
| `rtl/pkg/npu_pkg.sv` | 全局参数、数据位宽、地址等 | 1 |
| `rtl/gemm/mac_int8.sv` | INT8 乘累加、2 级流水 | 2 |
| `rtl/gemm/pe.sv` | PE 双精度 MAC、A/B 传递 | 3 |
| `rtl/gemm/systolic_array.sv` | 2D PE 阵列与数据流 | 4 |
| `rtl/gemm/gemm_ctrl.sv` | GEMM 形状、地址和时序控制 | 5 |
| `rtl/mem/sram_dp.sv`, `banked_sram.sv`, `tile_buffer.sv` | 存储端口、Bank、Buffer | 6 |
| `rtl/bus/axi_dma_rd.sv`, `axi_dma_wr.sv` | DDR 与 SRAM 搬运 | 7 |
| `rtl/ctrl/ucode_fetch.sv`, `ucode_decode.sv` | 微码取指、译码 | 8 |
| `rtl/ctrl/scoreboard.sv`, `barrier.sv` | 并行资源与依赖控制 | 9 |
| `rtl/ops/` | Softmax/LayerNorm/GELU 等 | 10 |
| `rtl/top.sv` | 顶层组合与接口 | 11（早期先粗读） |
| `rtl/graph/` | 图 ISA、执行、算子引擎 | 12 |
| `python/onnx_compiler/` | 模型编译与映射 | 13 |
| `python/golden/` | 软件参考模型 | 全程对应 |
| `sim/verilator/` | Testbench、集成仿真 | 全程对应 |

根目录 `Makefile` 中的 `SV_SRC` 是一个指定构建的文件列表，不能据此推断它包含所有 RTL 功能（例如 `mac_fp16.sv` 并未出现在其 `SV_SRC` 列表中）。此外 `sim/verilator/CMakeLists.txt` 和各专用 Testbench 可能采用不同的源码集与构建方式。运行前需逐项核对。

## 2. 必备基础知识地图

### A. 数字电路与时序

1. 二进制、补码、定点数，乘法积位宽：有符号 INT8 × INT8 通常需要 16 位积。
2. 组合逻辑与时序逻辑：`assign` / `always_comb` 和 `always_ff` 的区别。
3. 寄存器、时钟沿、复位与使能：为何同步电路的一拍前和一拍后不同。
4. 阻塞 `=` 和非阻塞 `<=`：时序块的状态更新要理解为同一时钟沿采样、更新随后生效。
5. 流水线：吞吐率不等于单个任务延迟；2 级流水不是两个乘法器。
6. 有限状态机：IDLE、LOAD、RUN、WRITE、DONE 的状态转换。
7. ready/valid、start/done/busy，背压、冒险、同步和时钟域概念。

### B. SystemVerilog 与仿真

`module`, `parameter`, `input/output`, `wire`, `logic`, `signed`, packed/unpacked arrays, `generate for`, `genvar`, `always_ff`, `always_comb`, `localparam`, `typedef enum`, `struct`, `package`, `$clog2`。学会阅读模块实例化、端口绑定、波形和 Testbench；工具为 Verilator、C++、Make/CMake、GTKWave。

### C. AI 算子与 Transformer

- GEMM：`C[M,N] = A[M,K] × B[K,N]`，`C[i,j] = Σ_k A[i,k]B[k,j]`。
- GEMV 是 M=1 或 N=1 的特殊形状，具体取决于定义方式。
- CNN 卷积通过 im2col/其他变换映射 GEMM，会增加或替代某些数据搬运。
- Transformer：Embedding → Q/K/V → Attention (`QK^T`, Softmax, `PV`) → 输出投影 → FFN → 归一化、残差。
- Prefill 与 Decode：前者处理多个 token，后者通常逐 token 追加；KV Cache 保存历史 K/V。
- 量化与 FP16：scale、舍入、溢出、饱和、INT32 累加与回量化。

### D. 计算体系结构和数据流

- PE/MAC、SIMD、空间阵列与 systolic array。
- Weight-stationary、output-stationary、input-stationary：明确什么驻留、什么流动、什么复用。
- Tiling 与片上 SRAM 容量、端口、Bank 冲突。
- Pipeline fill/steady/drain；吞吐、延迟和利用率的区别。
- DMA、AXI4、AXI4-Lite，控制面与数据面的区别。
- 冲突与依赖：RAW/WAR/WAW、scoreboard、barrier、双缓冲。

### E. 编译与软件硬件接口

- ONNX 是算子计算图表示，并非 RTL 或机器码。
- 编译过程：图解析 → shape/dtype 推导 → 算子映射 → 内存分配 → 发指令/生成数据镜像。
- 指令包含操作码、源/目的位置、维度、控制信息；指令语义必须和硬件译码匹配。
- Golden Model 与 RTL 的比较，要匹配算数精度、舍入规则、张量布局。

## 3. 学习主线（14 讲，建议 5–8 周，按理解调整）

| 讲次 | 主题 | 重点知识 | 对应文件 | 阶段成果 |
|---|---|---|---|---|
| 1 | NPU 全局架构 | 算法/控制流/数据流分层 | README, top.sv | 能解释系统方框图 |
| 2 | 数字时序与 RTL 语法 | 寄存器、两级流水、补码 | mac_int8.sv | 逐拍追踪乘加 |
| 3 | 单 PE 的实现 | 数据转发、两种 MAC、使能 | pe.sv | 画出 PE 内部结构 |
| 4 | 二维脉动阵列 | skew、传播、填充和排空 | systolic_array.sv | 画 2×2/3×3 时序表 |
| 5 | GEMM 控制 | M/N/K、分块、输出累加 | gemm_ctrl.sv, gemm_post.sv | 从矩阵 shape 推导计算步骤 |
| 6 | SRAM 与 Buffer | 双端口、Bank、仲裁 | mem/ | 说明读写时序及瓶颈 |
| 7 | DMA/AXI | burst、地址、传输与搬运重叠 | bus/ | 画 DDR-SRAM-PE 链路 |
| 8 | 微码与指令系统 | ISA、取指、译码 | isa_pkg.sv, ctrl/ | 解释一条 GEMM 指令 |
| 9 | 调度与依赖 | scoreboard、barrier | ctrl/ | 画启动/完成时序 |
| 10 | Softmax 等特殊单元 | Reduce、LUT、归一化 | ops/ | 分析逐阶段数据宽度 |
| 11 | Transformer 与 KV Cache | attention、prefill/decode | kv_ctrl.sv, golden/ | 解释 KV 数据放置 |
| 12 | ONNX 编译与图执行 | tensor table、Graph ISA | graph/, onnx_compiler/ | 贯通 MLP 编译执行 |
| 13 | 仿真验证与调试 | Testbench、VCD、回归、golden | sim/verilator/, python/tests/ | 复现一个正确性测试 |
| 14 | 性能建模与科研扩展 | utilization、bytes/MAC、energy | 多模块 | 提出 PE/CIM 映射问题 |

### 每讲固定教学结构

1. **算法目标**：本单元要计算什么？输入、输出的张量形状是什么？
2. **硬件动机**：单纯用 CPU/串行 MAC 有什么限制？该模块为什么存在？
3. **架构与数据流**：用图示分别追踪计算、读写和控制信号。
4. **RTL 代码**：先看 module/端口/寄存器，再看控制逻辑和关键语法。
5. **逐周期实例**：挑最小算例说明一个时钟周期发生哪些读写。
6. **验证**：golden、testbench、断言、波形以及预期输出。
7. **架构思考**：参数、资源、带宽、延迟、能耗及替代设计。

无需课后重复性练习；实际需要验证理解时运行项目并看波形。

## 4. 第一批基础讲解：MAC → PE → Array

### 4.1 先理解 MAC

一个神经元或矩阵乘法输出元素计算为 `c = Σ(a_k × b_k)`。硬件中 MAC (multiply-accumulate) 每次计算 `acc_next = acc_old + a × b`。一个有符号 INT8 数在 -128 到 127 之间；有符号 INT8 乘积通常保留 16 位；累加可使用 32 位，以降低溢出概率。

`rtl/gemm/mac_int8.sv` 有两级流水：

- Stage 1：在时钟沿根据 `en` 计算 `product <= a_in * b_in`，并延迟 `en` 与 `clear_acc` 控制信号。
- Stage 2：根据之前一拍的 `en_d1` 和 `product` 进行累加，对累加溢出做饱和处理。

重要：`<=` 非阻塞赋值使第二级读到的是旧 `product`，因此不能把两个 `always_ff` 当成同一拍串行执行的两条软件语句。另需注意 `clear_acc` 的时序：RTL 中 `clear_d1` 与数据同样经过寄存器，在波形中要检查清零与首个有效乘积的相对顺序。

### 4.2 再理解 PE

`rtl/gemm/pe.sv` 包含：

- A 数据从西侧 `a_in` 进入，经过寄存器向东侧 `a_out` 转发。
- B 数据从北侧 `b_in` 进入，经过寄存器向南侧 `b_out` 转发。
- INT8 MAC 和 FP16 MAC 两套计算路径。
- `dtype_fp16` 选择哪套 MAC 被使能，以及输出哪套累加结果。

因此 PE 不仅负责乘加，还负责按方向传递操作数。要严格区分数据转发延迟与 MAC 算术流水延迟。

### 4.3 最后理解 systolic array

`rtl/gemm/systolic_array.sv` 默认参数为 M=16, N=16。二维生成循环实例化 `M×N` 个 `pe`。

每行 A 向右传，每列 B 向下传，PE 在输入正确对齐后计算对应输出分量。`a_wire`、`b_wire` 是阵列连接信号；`a_pipe`、`b_pipe` 则考虑了额外流水寄存器边界。

源码默认 `PIPE_STAGE=32`，大于默认阵列边长 16，因此额外的边界寄存器默认未启用。注释说明此设置暂用于避免 A/B 失同步；不能简单把该参数改成 4 就断定功能正确。还有一个值得深究的细节：README 使用了 weight-stationary 术语，而 RTL 文件头明确写着 A 向东、B 向南。真正的数据驻留关系必须依据寄存器更新和输出累加时序验证，而不能只凭标签。

### 4.4 三个必要的时序概念

- **Latency（延迟）**：一组输入从进入到最终结果可用经历的周期数。
- **Throughput（吞吐）**：流水稳定后单位周期可处理的输入/输出数量。
- **Utilization（利用率）**：有效 MAC 运算次数与理论 MAC 总容量之比。

简单填充/排空公式，例如 `M+K+N−2`，只有在明确对应脉动阵列的数据注入方式、输出语义、流水深度、暂停、访存以及控制开销后才能套用。后续以 RTL 和波形为准。

## 5. 本地环境与初次运行

仓库主要依赖 Linux/WSL2、Verilator、C++ 工具链、Python3；运行特定模型需安装仓库 `python/requirements.txt` 中的包。下列命令适用于 Ubuntu/WSL 的一般入门环境；实际要求以仓库 README 为准。

```bash
sudo apt update
sudo apt install -y git make g++ cmake verilator gtkwave python3 python3-venv python3-pip

git clone https://github.com/harishsg993010/tiny-NPU.git
cd tiny-NPU

git rev-parse HEAD
verilator --version
make help
make lint
```

如需 Python tests：

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r python/requirements.txt
make test
```

`make sim` 通过根目录 Makefile 构建 `top.sv` 和 `tb_top.cpp`，需要注意其源码列表可能与新增加的模块不一致；如果失败，优先检查日志中的第一个报错、SV 文件清单、缺少的模块/包，以及 README 所推荐的其他构建入口。我们不会将未运行的测试声称为通过。

用于工程排错的基本命令：

```bash
find rtl -type f | sort
rg -n 'module |always_ff|always_comb|assign ' rtl/gemm
sed -n '1,220p' rtl/gemm/mac_int8.sv
make lint 2>&1 | tee lint.log
```

## 6. 与 CIMFlow / MRAM-CIM 的衔接

学习 tiny-NPU 的重点不是照搬架构，而是建立对照分析能力：

| tiny-NPU（RTL） | CIMFlow / CIM 研究要对照的问题 |
|---|---|
| MAC 与 PE | CIM macro 的乘累加怎样实现？精度与并行度如何变化？ |
| Systolic Array | 数据复用、脉动数据流与存算阵列映射有什么差别？ |
| SRAM / DMA | 权重与激活的移动量、Bank 访问和外部带宽如何变化？ |
| GEMM Controller | 不同 M/N/K 或 GEMV 的映射、tiling、发指令成本是什么？ |
| ISA / Scoreboard | 异构 PE+CIM 引擎应该如何调度、同步和选择？ |
| Golden / Verilator | Cycle-accurate RTL 与 SystemC 架构级模型有哪些抽象差异？ |
| 性能计数器 | 利用率、吞吐、能量估计的口径如何统一？ |

未来可围绕 PE 与 CIM 的算子动态选择、片上/存内数据复用、混合精度与 SRAM/MRAM 分层设计做小规模研究。选题仍需单独通过实验而非只改参数来证明架构价值。

## 7. 建议阅读资料

- 仓库 README: https://github.com/harishsg993010/tiny-NPU/blob/main/README.md
- 数字电路教材：Harris & Harris, *Digital Design and Computer Architecture*。
- 体系结构教材：Hennessy & Patterson, *Computer Architecture: A Quantitative Approach*。
- 张量阵列与数据流：Chen et al., *Eyeriss: An Energy-Efficient Reconfigurable Accelerator for Deep Convolutional Neural Networks*, ISSCC 2016。
- TPU 脉动阵列：Jouppi et al., *In-Datacenter Performance Analysis of a Tensor Processing Unit*, ISCA 2017。
- ONNX 文档：https://onnx.ai/onnx/
- Verilator 文档：https://verilator.org/guide/latest/
- SystemVerilog 教学：https://www.chipverify.com/systemverilog/systemverilog-tutorial

## 8. 学习完成标准

你应当可以：

1. 不依赖 README，自己画出 NPU 的控制/计算/存储三层架构。
2. 用 2×2 或 4×4 矩阵逐周期解释 PE、阵列数据流和 MAC 时序。
3. 从 `gemm_ctrl` 的控制信号推导 SRAM 地址及数据何时进入计算阵列。
4. 阅读一个完整的 Testbench，确认期望结果和 RTL 结果如何比较。
5. 跑通至少一个软件 golden + RTL 仿真闭环，并解读波形。
6. 为一组 GEMM/GEMV 形状建立可比较的计算周期和搬运量模型。
7. 清晰提出把阵列或数据流改成 CIM/MRAM-CIM 后需要验证的架构假设。

---

**下一讲入口：** `rtl/gemm/mac_int8.sv`，从基础同步时序、补码乘法、`always_ff`、非阻塞赋值开始，画出 2 级 MAC 每拍发生的事情，再对照 `rtl/gemm/pe.sv`。
