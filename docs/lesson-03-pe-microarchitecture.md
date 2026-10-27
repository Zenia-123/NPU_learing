# 第 03 讲：PE 微架构——数据转发、双精度 MAC 与二维阵列连接

原始仓库：https://github.com/harishsg993010/tiny-NPU

源码：`rtl/gemm/pe.sv`、`rtl/gemm/mac_int8.sv`、`rtl/gemm/mac_fp16.sv`、`rtl/gemm/systolic_array.sv`。本讲以所读取的实际 RTL 为准。

## 一、硬件逻辑：为什么 MAC 还不是 PE

MAC 完成 `acc <- acc + a*b`，而 PE 除计算外必须把操作数向邻近 PE 传递，并提供复位、使能、清累加器以及数据格式控制。在 tiny-NPU 中，每个 PE 有 A 向东和 B 向南的两条转发数据路径（各自一拍），以及各一份 INT8、FP16 MAC 计算路径，通过 `dtype_fp16` 选择输出。

特别重要：PE 当前拍的计算和转发都从同一个 `a_in,b_in` 接收值。计算没有先经过本 PE 的转发寄存器。`a_out`、`b_out` 给相邻 PE 下一拍使用。

## 二、实际端口与参数

```systemverilog
module pe #(parameter int DATA_W=8, parameter int ACC_W=32)(
 input wire clk, rst_n, clear_acc, en, dtype_fp16,
 input wire signed [DATA_W-1:0] a_in,b_in,
 output logic signed [DATA_W-1:0] a_out,b_out,
 input wire signed [15:0] a_in_fp16,b_in_fp16,
 output logic signed [15:0] a_out_fp16,b_out_fp16,
 output logic signed [ACC_W-1:0] acc_out
);
```

`parameter` 允许在不同阵列实例中设定位宽；`input/output` 是硬件端口；`logic` 表示四态变量，不代表一定生成寄存器；`signed` 为补码整数解释。在 PE 的 FP16 端口，16 位向量是浮点编码的位模式，而不是应当直接按补码做 FP 计算的整数。

## 三、转发寄存器：每个时钟沿如何传播

```systemverilog
always_ff @(posedge clk or negedge rst_n) begin
 if (!rst_n) begin
  a_out <= '0;
  b_out <= '0;
 end else if (en) begin
  a_out <= a_in;
  b_out <= b_in;
 end
end
```

FP16 也有另一组几乎相同的转发寄存器：`a_out_fp16`、`b_out_fp16`。两套转发都由 `en` 驱动；无论 dtype 选择哪条 MAC 路径，两组转发寄存器在 en=1 时都会更新。

若两个 PE 水平相邻，PE0 的 `a_out` 接 PE1 的 `a_in`：时钟沿 ↑1，PE0 读外部 A=5，更新其 a_out=5，但 PE1 当沿读到的是先前 a_out；到 ↑2，PE1 才读到 5。因此相邻 PE 之间有一拍数据传播延迟。竖向 B 同理。

异步复位 `rst_n` 拉低即可清转发寄存器；`en=0` 时输出保持旧值。对原 RTL 而言，并无附属于每组数据的逐 PE valid 标记，这意味着填充 0、停顿和可用性需由上层流控正确处理；不能把任意空泡都理解为无影响。

## 四、INT8 和 FP16 双路径的例化和选择

```systemverilog
mac_int8 #(.DATA_W(DATA_W),.ACC_W(ACC_W)) u_mac_int8 (
 .clk(clk),.rst_n(rst_n),.clear_acc(clear_acc),
 .en(en && !dtype_fp16),.a_in(a_in),.b_in(b_in),.acc_out(int8_acc)
);
mac_fp16 #(.DATA_W(16),.ACC_W(ACC_W)) u_mac_fp16 (
 .clk(clk),.rst_n(rst_n),.clear_acc(clear_acc),
 .en(en && dtype_fp16),.a_in(a_in_fp16),.b_in(b_in_fp16),
 .acc_out(fp16_acc)
);
assign acc_out = dtype_fp16 ? fp16_acc : int8_acc;
```

`#(...)` 覆盖例化参数，`u_mac_int8` 是实例名，`.clk(clk)` 为端口绑定。这里不是共享一套可以随意改变计算精度的算术硬件，而是实例化两条 MAC 路径，并在输出端选择。请注意输出 MUX 用的是当拍的 `dtype_fp16`，如果中途切换 dtype，现有累加状态、使能延迟、转发延迟可能导致混合批次问题；上层需要提供一致的模式控制、清零与周期协议。

## 五、浮点基础与 FP16 MAC

IEEE 754 binary16 编码：1 位符号、5 位阶码、10 位 fraction；正常数数值是 `(-1)^s × (1.f) × 2^(e-15)`。binary32 为 1+8+23，阶码偏置 127。零、次正规数、无穷与 NaN 分别有特殊编码。

源码 `mac_fp16.sv` 两级计算：
- Stage1：提取 sign/exp/mant，调用 `fp16_mul` 算 FP16×FP16，输出 32 位 FP 乘积保存到 `product_fp32`；`en_d1`、`clear_d1` 同步打一拍。
- Stage2：`acc_reg <= fp32_add(product_fp32, acc_reg)`，执行 FP32 累加。`acc_out` 是 32-bit FP 编码，而 INT8 路径的 `acc_out` 是 32-bit 整数。相同位宽不意味着相同数值编码，外围格式转换和解释要一致。

FP16 乘法：符号异或、指数求和及偏置调整、尾数乘法、规格化、特殊值处理；FP32 加法：指数对齐、尾数加减、规格化、GRS 舍入。源码存在浮点特殊情形的简化，不能无测试宣称完全 IEEE 754 兼容。

为什么 FP16 输入常用 FP32 累加？提高多项乘加时的累加精度，避免每次中间和都舍入到 16 位；代价是更多算术硬件和寄存器位。

## 六、PE 的两种延迟不能混淆

`pe.sv` 转发寄存器使 A、B 各在对应方向跨一个 PE 传播耗费一个时钟沿；`mac_int8.sv` 中乘法乘积寄存器、累加寄存器又形成两级计算流水。这不是让同一个 PE 的两个输入先转发一拍再去本地计算，也不意味着 PE 一次 MAC 的吞吐率必然是每两拍一组。

在持续 en=1 且数据已排好时间的情况下，整数 MAC 每个时钟沿可以接受新一组操作数，前一组在下一时钟沿更新 ACC；连续运算的累加器可以逐拍更新。假定复位后 (1,5)、(2,7) 依次送入，第一个上升沿 product=5、ACC=0；第二个上升沿 product=14、ACC=5；第三个上升沿如 en=0，乘积无效、ACC=19。需同时跟踪 en_d1、clear_d1。

## 七、从 PE 到阵列

`systolic_array.sv` 默认 M=N=16，使用嵌套 `generate for` 产生 256 个 PE 实例。这是 elaboration 时生成 256 份电路，不是运行中的软件循环。核心连接关系：

```systemverilog
.a_in(a_pipe[gi][gj]),
.b_in(b_pipe[gi][gj]),
.a_out(a_wire[gi][gj+1]),
.b_out(b_wire[gi+1][gj]),
.acc_out(pe_acc[gi][gj])
```

边界：`a_wire[row][0]=a_col[row]`、`b_wire[0][col]=b_row[col]`。A 向右流动，B 向下流动，各 PE 本地积累部分和。尽管源码注释使用“Weight-stationary style”，从实际信号连接来看 B 也在向南转发，且本地存储的是 ACC，并没有明确的常驻权重载入寄存器；数据流判定应以连接和控制方式为准。

`PIPE_STAGE=32`，对于默认 16×16 的阵列，不触发额外的 A/B 边界流水寄存器；可调参数不能随意缩小，否则 A/B 传播路径的额外延迟可能不同步。源代码 `acc_valid` 使用全局计数器和 DRAIN_LATENCY=M+N+...，这是控制标志，不是逐输出元素的合法性验证，是否与所有 K 及清零/控制阶段严格匹配还需通过上层控制及 testbench 核查。

## 八、2×2 数据对齐概念与逐周期表

令 A 和 B 为 2×2：A=[[1,2],[3,4]]，B=[[5,6],[7,8]]。要在 (i,j) PE 连续计算 A[i,0]B[0,j]、A[i,1]B[1,j]，一种常见输入偏斜方式是左侧行 i 在 t=i+k 注入 A[i,k]，顶部列 j 在 t=j+k 注入 B[k,j]，因此 (i,j) 同时接收相同 k 的 A、B（所有时间只表示相对拍次，具体 MAC 累加输出再延迟一级）。

在 t=0：PE00 接 A00=1,B00=5，形成乘积5；其他 PE 应收到填充/无效数据。
在 t=1：PE00 接 A01=2,B10=7，乘积14；PE01 接 A00=1,B01=6，乘积6；PE10 接 A10=3,B00=5，乘积15。
在 t=2：PE01 接 A01=2,B11=8，乘积16；PE10 接 A11=4,B10=7，乘积28；PE11 接 A10=3,B01=6，乘积18。
在 t=3：PE11 接 A11=4,B11=8，乘积32。
这样各 PE 的数值和分别为 19、22、43、50。值得强调：为了得到这样的预期结果，真正 RTL 上还需要设置 clear、输入填充、en、模式切换及足够的流水 drain 周期。不能只凭这个数学时序表认定任何现有 testbench 一定执行成功。

## 九、源码阅读方法和未来科研

首先从 `pe.sv` 模块的输入输出画框图，分清计算路径和转发路径；其次分别进入两个 MAC 子模块，确定数值编码、计算阶段和清零延迟；最后再进入 `systolic_array.sv`，观察 `generate` 和 4 类连线 a_wire/b_wire/a_pipe/b_pipe。下次继续用二维 PE 阵列逐拍表、fill/steady/drain 统计、阵列利用率以及 GEMM/GEMV 映射，衔接后续 PE 与 CIM 对比。

科研衔接：在面积能量模型中，两套同时例化的 MAC 路径与仅一条路径的硬件代价不同；PE 邻接传播对应寄存器时钟/翻转能耗；本地 ACC 保持会减少部分和在大存储之间往返。进一步设计 MRAM-CIM/NMC 时，要把 PE 算术能量、SRAM 数据搬运、阵列利用率与 CIM 宏读计算写能耗独立建模后再比较。
