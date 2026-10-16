# 第 02 讲：数字电路时序、SystemVerilog 与 INT8 MAC 两级流水

> 项目：<https://github.com/harishsg993010/tiny-NPU> ；源码：`rtl/gemm/mac_int8.sv`，关联 `rtl/gemm/pe.sv`。

## 1. 本讲目标与硬件背景

GEMM 的单个输出为 `C[i,j]=sum_k A[i,k]*B[k,j]`，MAC 实现 `acc_next=acc_old+a*b`。它不是单纯的乘法器，而是乘法器、寄存器、加法器、饱和判断与控制信号构成的时序电路。本节重点：组合/时序逻辑区别、时钟边沿、非阻塞赋值、流水线延迟/吞吐、控制对齐，以及逐行理解真实 SystemVerilog。

## 2. 从数学映射到硬件

例如 `A=[[1,2],[3,4]]`，`B=[[5,6],[7,8]]`，`C=[[19,22],[43,50]]`，其中 `C00=1*5+2*7=19`。一个复用 MAC 先算乘积 5，再算乘积 14；累加器从 0→5→19。输出产生于寄存器更新后，不应把这一过程误认为两个乘积都在一拍完成。

组合逻辑：`assign product=a*b;` 描述没有历史状态的逻辑，输出受到传播延迟影响。时序逻辑：`always_ff @(posedge clk) product<=a*b;` 描述在时钟上升沿采样并保存值。时钟周期至少需满足寄存器 clk-to-Q、组合路径、建立时间和时钟不确定度等约束。

流水：将乘法与累加分成两级，连续输入能在每个时钟沿接受新的一组乘数，但一组乘积需要跨两个寄存器边沿才能更新 ACC。延迟（latency）是单项工作的完成时间；吞吐（throughput）是单位时间处理的任务数；不能将两者混淆。这里连续乘积可以每拍进入一次，并不是每拍完成整次矩阵乘法。

## 3. 源码端口与数据类型

```systemverilog
module mac_int8 #(
 parameter int DATA_W = 8,
 parameter int ACC_W = 32
)(
 input wire clk, rst_n, clear_acc, en,
 input wire signed [DATA_W-1:0] a_in, b_in,
 output logic signed [ACC_W-1:0] acc_out
);
```

`module` 定义并行存在的电路模块，不是一次性调用的 C++ 函数；`parameter` 允许例化时配置位宽；`[7:0]` 为八位向量；`signed` 表示补码有符号算术；`logic` 是四态数据类型，不单独决定是否综合成寄存器。8-bit 补码取值 [-128,127]，8×8 位有符号相乘需要 16 位乘积，故 `logic signed [2*DATA_W-1:0] product;`。

## 4. 第一级：乘法与控制同步

真实源码：

```systemverilog
logic signed [2*DATA_W-1:0] product;
logic en_d1, clear_d1;
always_ff @(posedge clk or negedge rst_n) begin
 if (!rst_n) begin
  product <= '0;
  en_d1 <= 1'b0;
  clear_d1 <= 1'b0;
 end else begin
  en_d1 <= en;
  clear_d1 <= clear_acc;
  if (en) product <= a_in * b_in;
  else product <= '0;
 end
end
```

`posedge clk` 为上升沿；`negedge rst_n` 允许低有效异步复位；`'0` 为按目标宽度扩展的全零；`1'b0` 表示一位二进制零；`<=` 非阻塞赋值在同一时钟沿先用旧值求 RHS，再统一更新寄存器。数据乘积、有效信号和清零信号同步打一拍。

## 5. 第二级：累加与符号扩展

```systemverilog
logic signed [ACC_W-1:0] acc_reg;
logic signed [ACC_W:0] acc_ext;
always_ff @(posedge clk or negedge rst_n) begin
 if (!rst_n) acc_reg <= '0;
 else if (clear_d1) acc_reg <= '0;
 else if (en_d1) begin
  acc_ext = {acc_reg[ACC_W-1],acc_reg} +
   {{(ACC_W-2*DATA_W+1){product[2*DATA_W-1]}},product};
  if (acc_ext[ACC_W] != acc_ext[ACC_W-1]) begin
   if (acc_ext[ACC_W]) acc_reg <= {1'b1,{(ACC_W-1){1'b0}}};
   else acc_reg <= {1'b0,{(ACC_W-1){1'b1}}};
  end else acc_reg <= acc_ext[ACC_W-1:0];
 end
end
assign acc_out=acc_reg;
```

`acc_reg` 是 32 位（默认）有符号累加器。`acc_ext` 宽 33 位，提供检测有符号溢出所需的扩展位。`{x,y}` 为拼接，`{N{x}}` 为重复拼接；符号扩展应复制最高符号位，而不能简单补零，否则负数会变成巨大的正数。若扩展求和的最高两位不同，则 32 位有符号结果溢出，饱和为 INT32_MAX (2147483647) 或 INT32_MIN (-2147483648)。`clear_d1` 的优先级高于累加，不能在清零同拍误认为还会累计该乘积。

`acc_ext =` 为阻塞赋值，在时序块内部作中间表达式计算；`acc_reg <=` 才是寄存器下一值的非阻塞赋值。一般可把组合计算移到 `always_comb`，在时序块更新寄存器，使结构更清晰。

## 6. 逐周期精确追踪

假设复位释放后 `acc_reg=0`，`en=1`，`clear_acc=0`，在连续三个上升沿前依次给输入 (1,5)、(2,7)、(3,2)：

| 时钟上升沿 | 本沿输入 a,b | 本沿更新 product | 本沿使用的旧 product | 本沿使用的旧 en_d1 | 更新后 ACC |
|---|---|---:|---:|---:|---:|
| ↑1 | (1,5) | 5 | 0 | 0 | 0 |
| ↑2 | (2,7) | 14 | 5 | 1 | 5 |
| ↑3 | (3,2) | 6 | 14 | 1 | 19 |
| ↑4 | (保持 en=0) | 0 | 6 | 1 | 25 |
| ↑5 | en=0 | 0 | 0 | 0 | 25 |

解释：在 ↑2，第二级看到的是 ↑1 结束后已保存的 product=5，而不是 ↑2 刚采样产生的 14。这不是“慢了一步的错误”，而是流水线的正常行为。

注意：此例 `clear_acc` 始终为 0；如果在输入数据期间清空 ACC，清零请求晚一拍生效，并具有高于累加的优先级，需要保证请求与具体数据批次边界匹配。

## 7. 数字电路术语解释

- Setup time：时钟沿前输入至少稳定的时间；Hold time：时钟沿后仍需保持的时间。
- Critical path：确定最小时钟周期的最长寄存器到寄存器路径。
- Clock-to-Q：触发器采样时钟后，Q 输出变为新值所需时间。
- Pipeline register：切分组合路径；增加时序状态与可能的延迟，也可能提高可达时钟频率。
- Enable：控制本次数据是否有效/运算是否继续；即使 `en=0`，第一级仍更新 `en_d1`，从而保证流水泡正确传播。
- Asynchronous reset：复位不必等待时钟上升沿；撤销复位则需满足电路时序规范。

## 8. 接上 PE 与 Systolic Array

`rtl/gemm/pe.sv` 中，`a_out<=a_in`、`b_out<=b_in` 每个使能时钟沿将输入传给相邻 PE；同一 PE 内创建 `mac_int8` 和 `mac_fp16` 实例，依 `dtype_fp16` 选择计算路径。要区别“数据向东/向南传递的 1 拍寄存器”与“乘法到累加两级流水”——这是不同的硬件功能。在矩阵阵列中还必须偏斜（skew）A、B 数据，确保第 (i,j) 个 PE 同时收到正确的 `A[i,k]` 与 `B[k,j]`。

后续学习 `systolic_array.sv` 时，会从 2×2 阵列用周期表展示真实操作数如何逐点传播，然后研究 16×16 阵列的填充、排空、利用率、GEMM 分块和延迟模型。这里的 `acc_out` 是 ACC 寄存器输出，不等价于完整 GEMM tile 已经全局完成；后者取决于控制器运行周期及数据有效性。

## 9. 建议验证与代码阅读

先打开 `rtl/gemm/mac_int8.sv`，追踪 `clk`、`rst_n`、`en`、`clear_acc`、`product`、`en_d1`、`acc_reg`。以 (1,5)、(2,7)、(3,2) 为输入查看上表对应的边沿值。仿真可使用 Verilator 的测试平台，检查 (a) 连续输入累加，(b) en=0 的 bubble，(c) reset，(d) clear_acc 的延后生效，(e) 极值乘法及饱和，(f) 负数符号扩展。未经运行不要宣称测试通过。

### 本讲知识和科研的连接

基础 MAC 只是完整 PE/NPU 的第一层。未来做 CIMFlow 或 MRAM-CIM，需要进一步回答：累加位宽与量化如何影响面积/能量，GEMM/GEMV 形状如何影响阵列使用率，片上 SRAM 数据复用如何降低访存，以及数字 PE 与 CIM 宏的读计算写能量/延迟模型如何公平比较。这些都将在后续章节逐步展开。
