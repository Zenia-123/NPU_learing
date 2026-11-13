# 七文件专题一：C++ 测试台零基础精读

> 参考版本：`8216c22b762011aa20c05fc2768423fd12dda59d`。本篇是用户主动提出的七文件专题，源码与时序为静态阅读；没有进行 RTL 仿真。已写讲义不等于用户已掌握。返回[七文件代码树与学习路线](supplement-gpt2-seven-files-00-code-tree.md)。

## C++ 源码阅读地图：`tb_gpt2_block.cpp`

[打开固定版源码](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/sim/verilator/tb_gpt2_block.cpp)。它有 1228 行，不能假定“从第一行运行到最后一行”：定义函数时不执行其函数体；**程序运行从 `main()` 开始**，调用哪个函数才跳到该函数，返回后接着调用处执行。阅读时可先看这个调用索引，再依照文件定义顺序理解。

| 源码起始行 | 定义或区域 | 所属职责 |
|---:|---|---|
| 1 | 注释与 `#include` | 声明本测试的意图、导入头文件 |
| 32 | `main_time`、`sc_time_stamp`、`dut`、`tfp`、`tc` | 仿真时间和模型对象 |
| 42、50、84、105 | 常量 | 模型维度、数据 SRAM 地址、opcode/flag、量化参数 |
| 112、124 | `tick()`、`reset_dut()` | 推进时钟、复位 |
| 134、142、150、158 | SRAM0/1 的读写函数 | 以 TB 端口和 `tick()` 访问数据存储 |
| 166、177 | `ucode_write()`、`encode_instr()` | 指令写入、编码 |
| 194 | `gemm_golden()` | C++ 矩阵乘法参考 |
| 217、220、242 | `EXP_LUT`、`RECIP_LUT`、`build_softmax_luts()`、`softmax_golden()` | Softmax 参考计算 |
| 282、284、294、309、322 | `RSQRT_LUT`、`build_rsqrt_lut()`、`counting_div_mean()`、`counting_div_unsigned()`、`layernorm_golden()` | LayerNorm 定点参考及辅助除法 |
| 370、372、385、395 | `GELU_LUT`、`build_gelu_lut()`、`gelu_golden()`、`vec_add_golden()` | 激活和逐元素加法参考 |
| 407 | 输入、权重与参考结果数组 | 仿真测试数据及中间变量 |
| 442 | `generate_data_and_golden()` | 确定随机测试数据并运行 C++ 全流程参考 |
| 550 | `load_microcode()` | 人工按算子构造并写入全部微指令 |
| 736 | `load_data_to_srams()` | 把数据写进 RTL 数据 SRAM |
| 787 | `handle_dma_command()` | 软件模拟 SRAM0 → SRAM1 拷贝 |
| 804、809、829 | `VerifyResult`、`verify_matrix()`、`verify_matrix_strided()` | 从 SRAM 读出、比较参考值 |
| 850 | `dump_csv()` | 可选地把数值写 CSV |
| 872 | `main()` | 创建模型、装载、执行、验证、释放，C++ 程序入口 |

### 完整调用关系与读法

`main` 首先创建 DUT 和波形对象、设置输入；再依次 `build_softmax_luts` / `build_rsqrt_lut` / `build_gelu_lut`，执行 `reset_dut` → `tick`；接着 `generate_data_and_golden`，此函数调用 `layernorm_golden`（内部调用两个 counting_div 函数）、`gemm_golden`、`softmax_golden`、`gelu_golden`、`vec_add_golden`。然后 `load_microcode` 对每一条依次调用 `encode_instr` → `ucode_write` → `tick`，再 `load_data_to_srams` → `sram0_write` / `sram1_write` → `tick`。

执行阶段 main 自己驱动启动脉冲和 `tick`；DMA 被捕获时调用 `handle_dma_command` → `sram0_read` / `sram1_write` → `tick`；结束后 `verify_matrix` → `sram0_read` → `tick` 并比较，必要时 `dump_csv`。函数是主机软件代码，`dut->` 驱动和读取 RTL 端口；不能把 C++ 内 `for` 循环直接理解为电路中并行复制出的硬件。

### 附：阅读本文件马上会遇到的 C++ 语法

| 写法 | 在本文件中怎样理解 |
|---|---|
| `#include <cstdint>` | 预处理阶段引入头文件中的定宽整数声明；`#include "Vgpt2_block_top.h"` 引入 Verilator 生成的模型类头文件。 |
| `// ...` | 注释，不由 CPU 执行。 |
| `void f(...)` | 函数 `f` 不向调用者返回值；`int f(...)` 返回整数；调用前函数体不自动执行。 |
| `{ ... }` | 一段作用域或函数体，不能按排版缩进代替花括号。 |
| `uint8_t / int8_t` | 8 位无符号 / 有符号值；该文件的数据样本通常为后者，一个元素 1 字节。 |
| `uint16_t` | 16 位无符号值，如数据地址 `addr`；bit 宽度与地址所表示的单位是两回事。 |
| `int8_t* A` | A 是指向 `int8_t` 元素的指针，`A[i]` 读第 i 个元素；`const int8_t* A` 不通过 A 改写其所指元素。 |
| `&X[0][0]` | `&` 在这里取第一个元素的地址；与函数参数声明 `uint64_t& hi` 的引用语法不同，也与 `x & mask` 按位与不同。 |
| `dut->clk` | 通过指针访问 C++ 仿真对象的 clk 成员，赋值后需 `eval()` 才推进模型评估。 |
| `for (int i=0; i<n; i++)` | 初始化、判断条件、执行循环体、递增并重复；行省略大括号时通常只有下一条语句属于循环。 |
| `if (cond) ... else ...` | 依布尔条件选择执行路径；`&&` 需要两个条件同时为真，`!done` 表示 done 为假。 |
| `x ? a : b` | 三目表达式：x 为真选择 a，否则选择 b，例如测试退出码。 |
| `(uint64_t)x` | 把 x 转为 64 位无符号类型；应在移位前看清宽度。 |
| `<<` / `>>` / `|` / `&` | 在整数上分别是左移、右移、按位或、按位与；但 `std::cout <<` 是流输出，结合上下文判断。 |
| `std::vector<uint16_t> v(n)` | 标准库动态数组，创建 n 个 16 位元素；`v[i]` 访问下标。 |
| `std::cout << ...` | 向控制台输出；`std::endl` 换行并刷新。 |
| `new T`、`delete p` | 创建 / 释放动态对象；delete 不等于复位 RTL 的某个寄存器。 |
| `auto`、`[](args){...}` | 前者自动推导变量类型；后者定义匿名函数（lambda）。源码的 `read_sram_matrix` 用 lambda 封装按行读 SRAM。 |

# 第一部分：先沿 C++ 仿真程序读懂微指令从哪里来

本部分对应固定版本 [sim/verilator/tb_gpt2_block.cpp](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/sim/verilator/tb_gpt2_block.cpp)。文件共有 1228 物理行，含注释和空行。以下时序和指令数量是对该版本源码的静态分析，不代表本次已经成功执行仿真。

## 1. 首先区分三件经常混淆的事

1. **模型编译**：通常需要读取模型计算图、选择算子、切分矩阵、分配存储地址、安排执行顺序和同步，再生成设备指令。
2. **汇编/编码**：已知“要做什么操作、操作数地址和参数”后，把它们按照指令格式填进固定位域，形成二进制指令。
3. **RTL 仿真编译**：Verilator 把 SystemVerilog 硬件描述转换成可由 C++ 驱动的仿真模型；这与将神经网络模型编译成 NPU 指令是两件不同的事。

这个 GPT-2 block 测试的操作顺序、地址和尺寸由程序员在 C++ 中写死：`load_microcode()` 通过循环调用 `encode_instr()`，直接产生和写入 128 位指令。这个测试没有调用 `ucode_asm.py`，也没有读取 GPT-2 计算图并自动把它编译成微指令。故它展示了**人为安排模型算子后怎样编码、装载和执行**，不是完整的自动模型编译器。

这是一个缩小的、随机数据的 GPT-2 风格 Transformer block 仿真，并非读入预训练的 GPT-2 权重后生成文字。C++ 测试程序在主机上运行；`gpt2_block_top.sv` 是仿真里的被测硬件顶层；C++ 通过 Verilator 生成的接口驱动它们。硬件实例连接关系后文再通过 RTL 核对。

## 2. 代码从文件开头看起：程序的角色和尺寸

### 2.1 头文件和仿真对象

[文件开头](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/sim/verilator/tb_gpt2_block.cpp#L8) 包含 `verilated.h`、波形接口以及 `Vgpt2_block_top.h`。最后这个头文件来自 Verilator 对顶层模块的转换；它提供一个 C++ 类，类的成员让测试程序可以设置或读取对应仿真端口。

```cpp
static Vgpt2_block_top* dut;
static VerilatedVcdC* tfp;
```

- `Vgpt2_block_top`：表示被测 RTL 仿真模型的 C++ 类。
- `*`：声明这里存的是一个指针，即指向对象的变量。
- `dut`：device under test，被测设备。
- `tfp`：指向 VCD 波形记录对象。代码在运行时才创建对象。
- `static` 在这个位置使名称只在本源文件内可见。

`main()` 中的 `dut = new Vgpt2_block_top;` 创建仿真对象，之后 `dut->clk = 0;` 通过指针访问对象的 `clk` 成员。`->` 可以理解为“通过这个指针找到对象，再访问其中的成员”。不要把 C++ 对象本身误认为真实芯片。

### 2.2 尺寸与单位

[第 42 行起](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/sim/verilator/tb_gpt2_block.cpp#L42)：

| 常量 | 值 | 含义及单位 |
|---|---:|---|
| `SEQ_LEN` | 8 | 本次处理 8 个 token 位置 |
| `HIDDEN` | 64 | 每个 token 的隐藏向量 64 个元素 |
| `N_HEADS` | 4 | 注意力头数量 4 |
| `HEAD_DIM` | 16 | 每个头 16 个通道，4×16=64 |
| `FFN_DIM` | 256 | 前馈层中间向量 256 个元素 |

例如输入 `X` 为 `int8_t X[8][64]`，共 512 个元素；此测试每个元素 1 字节，因此是 512 字节。一个注意力头的 Q 权重是 `[64,16]`，其投影为 `[8,64] × [64,16] → [8,16]`。

`static const int SEQ_LEN = 8;` 声明一个整数常量。`int8_t` 是 8 位有符号整数，`uint16_t` 是 16 位无符号整数；不应把“16 位地址数值”误当成“传输 16 字节”。

### 2.3 SRAM 地址和 opcode

[第 50 行起](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/sim/verilator/tb_gpt2_block.cpp#L50) 给权重、激活和中间结果分配 SRAM **字节地址**。如：`ADDR_X=0xC000`、`ADDR_LN1_OUT=0xC400`、`ADDR_Q_H=0xC800`。这意味着它们存的是测试中各矩阵的起始位置，不是矩阵的数值本身。`0x` 表示后面的数字使用十六进制。

[第 84 行起](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/sim/verilator/tb_gpt2_block.cpp#L84) 定义操作码，如 `OP_GEMM=3`、`OP_BARRIER=10`、`OP_END=255`。`flags` 的同一位可以因 opcode 不同拥有不同意义：例如 0x04 在 GEMM 中表示 REQUANT，在 VEC 中用于 COPY2D，必须结合译码逻辑理解。

## 3. 时钟与测试接口：C++ 怎么“推动” RTL

[第 112 行的 `tick()`](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/sim/verilator/tb_gpt2_block.cpp#L112) 先令 `clk=0` 并 `dut->eval()`，再令 `clk=1` 并 `dut->eval()`；如果打开波形记录，会分别调用 `dump()`。`eval()` 使仿真模型依据当前输入更新，不等于物理硬件中的一个软件函数。一次 `tick()` 产生一个低电平和一次上升沿；`tc` 为波形时间管理变量，每次 tick 在两个半周期各自递增一次。

```cpp
void sram0_write(uint16_t addr, uint8_t data) {
    dut->tb_sram0_wr_en = 1;
    dut->tb_sram0_wr_addr = addr;
    dut->tb_sram0_wr_data = data;
    tick();
    dut->tb_sram0_wr_en = 0;
}
```

[源码第 134 行](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/sim/verilator/tb_gpt2_block.cpp#L134)。它通过测试端口将一个 8 位数据字节写入一个 16 位地址，再推进一个时钟；并不是通过真实 CPU 总线写权重。下一节看类似的微码写接口。

## 4. 指令是怎样变成 128 位的？

### 4.1 编码格式

[第 177 行 `encode_instr`](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/sim/verilator/tb_gpt2_block.cpp#L177) 接收 opcode、标志、地址、矩阵维度、立即数，并用两个 64 位整数输出整条指令。源码布局如下：

| 指令位段 | 字段 | 位宽 | 当前程序常见含义 |
|---|---|---:|---|
| `[7:0]` | `opcode` | 8 bit | 操作类型 |
| `[15:8]` | `flags` | 8 bit | 操作选项 |
| `[31:16]` | `dst` | 16 bit | 目的地址 |
| `[47:32]` | `src0` | 16 bit | 源地址 0 |
| `[63:48]` | `src1` | 16 bit | 源地址 1 |
| `[79:64]` | `M` | 16 bit | 通常是 GEMM 输出行数 |
| `[95:80]` | `N` | 16 bit | 通常是 GEMM 输出列数 |
| `[111:96]` | `K` | 16 bit | 通常是 GEMM 归约长度 |
| `[127:112]` | `imm` | 16 bit | 立即数，其解释随 opcode 而变 |

`M/N/K` 并不对所有操作都表示矩阵维度。例如 VEC COPY2D 中它们被复用为行数、列数和源步长。因此不能只看字段名字，还要看当前 opcode 对其具体的解释。

代码用 `<<` 左移、`|` 按位或，将互不重叠的字段放到相应位置。例如 `((uint64_t)dst << 16)` 是先将 `dst` 转成 64 位，再向左移动 16 位；`(uint64_t)` 是类型转换。`uint64_t& hi` 中的 `&` 是 **C++ 引用参数**：函数里对 `hi` 赋值会改变调用者传进来的变量，不是按位与运算。

### 4.2 跟踪一条真正的 Q 投影指令

[第 568 行附近](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/sim/verilator/tb_gpt2_block.cpp#L568) 当 `h=0`：

```cpp
encode_instr(OP_GEMM, FLAG_REQUANT,
             ADDR_Q_H, ADDR_LN1_OUT, wq_h_addr,
             SEQ_LEN, HEAD_DIM, HIDDEN, GEMM_IMM_K64,
             hi, lo);
ucode_write(addr++, hi, lo);
```

代入常量：

| 参数 | 数值 | 含义 |
|---|---:|---|
| opcode | `0x03` | GEMM |
| flags | `0x04` | 启用再量化选项 |
| dst | `0xC800` | Q 输出 SRAM0 首地址 |
| src0 | `0xC400` | LN1 输出 SRAM0 首地址 |
| src1 | `0x0000` | 第 0 个头的 Q 权重首地址 |
| M, N, K | 8, 16, 64 | `[8,64] × [64,16] → [8,16]` |
| imm | `0x0901` | 该测试中 scale=1、shift=9 |

填入位段后：

```text
hi = 0x0901004000100008
lo = 0x0000C400C8000403
128位（高位写左边）= 0x09010040001000080000C400C8000403
```

它位于微码地址 9，因为前面是 8 条按行 LayerNorm 加 1 条 Barrier。这里的 `addr++` 是后置自增：**先把当前地址用于函数调用，再令 `addr` 增加 1**。它不是 `addr = addr + 1` 再写入。

### 4.3 128 位怎么通过 C++ 端口装入硬件？

[第 166 行](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/sim/verilator/tb_gpt2_block.cpp#L166) `ucode_write(addr, hi, lo)` 将 128 位按 32 位拆成四份，给 Verilator 生成的宽端口数组赋值：

| 数组元素 | 示例值 | 对应指令位 |
|---|---|---|
| `[0]` | `0xC8000403` | `[31:0]` |
| `[1]` | `0x0000C400` | `[63:32]` |
| `[2]` | `0x00100008` | `[95:64]` |
| `[3]` | `0x09010040` | `[127:96]` |

例如 `lo & 0xFFFFFFFF` 保留低 32 位，`lo >> 32` 把高 32 位移到低位。`uc_wr_en=1`、`uc_wr_addr=addr` 和 128 位写数据准备好之后调用 `tick()`，产生写入时钟沿，随后撤销写使能。数组拆分只是仿真接口表达一个宽信号的方式，不能由此断言真实硬件一定是四次 32 位总线写。

## 5. 模型算子顺序如何写成微指令程序？

[第 550 行 `load_microcode()`](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/sim/verilator/tb_gpt2_block.cpp#L550) 先设 `int addr=0`；以下循环都在 **C++ 装载阶段**运行，依次写入微指令存储器。这里的 `for` 不是发给 NPU 的循环控制指令；它把循环体展开为多条指令。

### 5.1 按行 LayerNorm，再设置同步

`for (int i=0; i<SEQ_LEN; i++)` 的三部分分别是：初始化 `i=0`；每轮判断 `i<8`；每轮结束后 `i++`。代码为每一行生成一条 LN 指令，`src=ADDR_X+i*64`、`dst=ADDR_LN1_OUT+i*64`，所以相邻行地址差 64 **字节**，每行 64 个 INT8 元素。完成 8 条后写入 Barrier，要求后续阶段按 RTL 所实现的同步条件等待。

### 5.2 对 4 个注意力头循环展开

每个头生成以下顺序：

1. 计算 Q、K、V：每次投影是 `[8,64]×[64,16]→[8,16]`；3 条 GEMM，每条后面各有 Barrier。
2. 计算分数：`Q[8,16] × Kᵀ[16,8] → S[8,8]`，1 条 GEMM，加 Barrier。代码通过转置 B 的 flag 表示如何读取 B。
3. 对 S 的 8 行逐行发送 Softmax：8 条 Softmax，最后加 1 条 Barrier；`K` 字段承载行索引以配合 causal mask 的操作含义。
4. `P[8,8] × V[8,16] → ATTN_H[8,16]`：1 条 GEMM 和 1 条 Barrier。
5. VEC COPY2D 将 `[8,16]` 这一头的输出逐行复制到 `[8,64]` 的对应 16 列；1 条 VEC 和 1 条 Barrier。源行步长为 16 字节，目的行步长为 64 字节。

每个头共 `3×2 + 2 + 9 + 2 + 2 = 21` 条。四个头各自 Q/K/V 等中间缓冲区复用，合并输出落到 ATTN 的不同列。`wq_h_addr = ADDR_WQ + h*64*16` 是第 h 个头权重块的起点，每头 1024 个 INT8 元素，即 1024 字节。

### 5.3 输出投影、残差与 FFN

随后依次生成：输出投影 `ATTN×Wo`、第一次残差加法、将残差 X2 从 SRAM0 搬到 SRAM1 的 DMA 命令、8 条 LN2、FFN1 GEMM、原址 GELU、FFN2 GEMM、第二次残差加法和 END。每个大的操作阶段之后安排 Barrier。源码里的 DMA 在这个测试由 C++ 侧模拟服务，后文解释，不能直接宣称已使用完整 AXI DMA。

### 5.4 一共多少条指令？

| 指令阶段 | 静态展开后的数量 |
|---|---:|
| LN1 8 条 + Barrier 1 条 | 9 |
| 4 个头，每头 21 条 | 84 |
| 输出投影、残差 1、DMA：各一条操作和一条 Barrier | 6 |
| LN2 8 条 + Barrier 1 条 | 9 |
| FFN1、GELU、FFN2、残差 2：各一条操作和一条 Barrier | 8 |
| END | 1 |
| **合计** | **117** |

按类别核对：GEMM 23、Softmax 32、LayerNorm 16、VEC 6、DMA 1、GELU 1、Barrier 37、END 1，总计 117。上述是本代码静态展开的计算结果，不是实际运行日志。`load_microcode()` 最后 `return addr;` 返回下一空地址，因此它也等于已写入的指令数。

## 6. 初始化输入和权重：数值不是来自真实模型

[第 442 行](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/sim/verilator/tb_gpt2_block.cpp#L442) 的 `generate_data_and_golden()` 用 `srand(42)` 设定伪随机种子，再用 `rand()` 生成输入、权重和 beta；同时用 C++ 函数算出软件参考值。举例 `((rand() % 21) - 10)` 产生范围为 -10 至 10 的整数：`%` 是求余，减 10 将范围移动到零附近。随机序列的具体结果与 C 库实现有关，不应将同一 seed 理解成跨平台一定相同。

[第 736 行](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/sim/verilator/tb_gpt2_block.cpp#L736) `load_data_to_srams()` 调用测试接口把这些数逐字节写到 SRAM0；LN beta 和第一次残差所需 X 写 SRAM1。数组访问例如 `X[i][j]` 是第 i 行第 j 列，`ADDR_X + i*HIDDEN + j` 是该 INT8 元素的字节地址。

C++ 算出的 `golden` 是参考结果；它不是送到 NPU 的指令。数据流和指令流分开：权重、激活进入 SRAM，128 位控制指令进入微码存储器；运行时指令字段指导硬件从指定地址访问数据。

## 7. 从 main 追一次完整控制流

[第 872 行 `main()`](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/sim/verilator/tb_gpt2_block.cpp#L872) 是 C++ 程序入口，按顺序执行：

1. 创建 RTL 仿真对象和 VCD 追踪对象，初始化输入端口；
2. 建立 C++ 参考函数使用的查找表并复位；
3. 生成随机数据并计算软件参考；
4. `int num_instrs = load_microcode();` 逐条编码与装载指令；
5. `load_data_to_srams();` 装入数据；
6. 设置 `dut->ucode_len = num_instrs`，给 `start_pulse` 拉高一个 `tick()`，再拉低；
7. 进入 `while (cycle < MAX_CYCLES && !done)`，逐 tick 推进模型，处理 DMA、统计完成信号，直到 `program_end` 或超时；
8. 从 SRAM 回读结果，计算比较与最终判定，关闭波形并释放对象。

`while` 是条件为真就循环，`&&` 表示两个条件都为真，`!done` 表示尚未结束。代码中的 `cycle` 不是启动以来所有硬件时钟的精确总数：装载、验证阶段的 tick 不包含在该变量内，并且 DMA 复制内部的许多 tick 也没有逐次增加 `cycle`。因此打印的 `cycle` 要按其源码计数口径理解。

当 `dma_cmd_captured` 有效时，[第 787 行的 `handle_dma_command`](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/sim/verilator/tb_gpt2_block.cpp#L787) 用 `dma_src/dst/len` 逐字节从 SRAM0 读、写到 SRAM1；随后测试程序脉冲 `dma_done_pulse` 通知硬件。本项测试中数据复制由 C++ testbench 完成，其实际功能和延迟不等价于 AXI DMA 硬件实现。

## 8. 验证到底证明了什么？

[第 1006 行起](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/sim/verilator/tb_gpt2_block.cpp#L1006) 采用 follow-actual：读取某一阶段 RTL 的实际结果，再用 C++ 参考计算它的下一阶段结果，与下一阶段 RTL 输出比较。这有利于定位局部错误，但不能直接证明“从原始输入到最终输出与独立参考端到端一致”，因为早期误差可能被带入后续参考。

LN1、LN2 的比较设置容差 20 并只作信息显示，未纳入 `all_pass`；例如注意力、WO、残差、FFN 等检查则更新 `all_pass`。最后 [第 1204 行](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/sim/verilator/tb_gpt2_block.cpp#L1204) 的最终条件是：

```cpp
bool pass = all_pass && (hw_gemm_count == 23) && (dma_count == 1);
```

Softmax、LayerNorm、GELU、VEC 的完成次数会打印，但不直接加入这条最终布尔判断。`return pass ? 0 : 1;` 使用三目运算：条件真返回 0，否则返回 1，通常给操作系统表示成功或失败。即使某次运行输出 PASS，也必须结合这些比较口径来解释，不能当作真实预训练 GPT-2 完整推理精度已验证。

## 附：参考计算代码逐段看懂

这里按源码 [194 行](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/sim/verilator/tb_gpt2_block.cpp#L194)往后再把 golden 部分补全。Golden 是在 CPU 上计算的对照值，不是 RTL 引擎，也不会自动保证与真实浮点 GPT-2 一致。

### A. `gemm_golden` 的循环、索引、累加和再量化

原逻辑的计算核心为：

```cpp
for (int i = 0; i < M; i++) {
    for (int j = 0; j < N; j++) {
        int32_t acc = 0;
        for (int k = 0; k < K; k++) {
            int8_t b_val = transpose_b ? B[j*K + k] : B[k*N + j];
            acc += (int32_t)A[i*K + k] * (int32_t)b_val;
        }
        // 缩放、移位、饱和，再写 C[i*N+j]
    }
}
```

先看 `i` 选择 C 的一行，`j` 选择 C 的一列，`k` 依次扫描归约维，`acc` 从零累加这一格 C 的乘积。虽然 A、B 在数学上是二维矩阵，函数参数是指向一维连续元素的指针：行优先存储中，A 的第 i 行 k 列的位置为 `i*K+k`；普通 B 的 k 行 j 列为 `k*N+j`。若 `transpose_b=true`，程序按 `B[j*K+k]` 访问已存储的转置前矩阵。例 A 为 2×3 时，`A[1*3+2]=A[5]` 就是第二行第三列。`acc += x` 等价于 `acc = acc + x`。

`acc` 为 int32，乘 scale 前转换 int64 得 `prod`；如果 shift>0，代码添加 `1LL << (shift-1)`，再右移，最后夹在 -128～127 后转 int8 写 C。`1LL` 是 long long 整数字面量；具体舍入与负数行为要按源码操作分析，不宜仅用“标准浮点运算”等同。更要注意：C++ golden 为拟合此 RTL 的定点行为，不能直接代替高精度模型。

### B. `build_softmax_luts` 与 `softmax_golden`

[220 行](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/sim/verilator/tb_gpt2_block.cpp#L220)先填 `EXP_LUT[256]` 与 `RECIP_LUT[256]`：每个表项为 uint16，分别基于固定缩放约定计算近似指数和倒数。`(int8_t)(uint8_t)i` 是先截为 8 位无符号，再按带符号的数解释，帮助覆盖 256 种字节模式。

[242 行](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/sim/verilator/tb_gpt2_block.cpp#L242)首先对一行找 `max_val`：若 `causal_mask_en && i > causal_limit`，将该位置当作 -128；随后逐项求差、裁剪到 int8 范围、查指数表、累加 `exp_sum`；最后取和的部分位查倒数表，乘指数后移位截取为输出。这里 `std::vector<uint16_t> exp_vals(length)` 是临时数组，用于保存每个位置的表值。`memset(output, 0, length)` 在此 `output` 是 int8 数组、每个元素 1 字节的前提下将 length 字节清零。代码中的近似、裁剪和因果掩码都影响数值，不能直接说这是无限精度数学 Softmax。

### C. LayerNorm 辅助除法和定点参考

[284 行](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/sim/verilator/tb_gpt2_block.cpp#L284) `build_rsqrt_lut()` 使用 `4096/sqrt(i)` 产生缩放倒数平方根查找表。两个 `counting_div_*` 将被除数等转入寄存量，循环 32 次进行左移、比较和减法，输出 32 位 quotient；这是具体源码中的计算过程，阅读时应遵循它的每一步而非假定它等于任意通用除法实现。`MASK48=(1ULL<<48)-1` 保留低 48 位，`ULL` 表示无符号长长整数字面量。

`layernorm_golden()` 先计算 `sum` 与 `sum_sq`，随后将数据左移、调用辅助函数形成均值和平方均值的中间近似，计算方差并对负方向情况钳到 0，再用 `variance >> 24` 的低 8 位作为 rsqrt 表地址；对每个输入减均值、乘倒数标准差、乘固定 `p_gamma=127`、加 beta，最后取整、饱和到 INT8。所有缩放和位截断以代码为准，并不意味着它与标准浮点 LayerNorm 完全相同。

### D. GELU、向量加法

[372 行](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/sim/verilator/tb_gpt2_block.cpp#L372)循环创建 256 个 GELU 表项：先将字节解释成有符号值，按 1/32 缩放，利用 `erf()` 计算，再缩放和饱和；`gelu_golden` 用输入的 8 位比特作为索引查这个表。`vec_add_golden` 则先用 16 位求和，然后饱和并写 8 位值。两个函数均属于 C++ 参考执行，不能认为它们就是 RTL datapath。

## 附：`main()` 的完整分支与验证细节

[872 行 `main(int argc, char** argv)`](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/sim/verilator/tb_gpt2_block.cpp#L872)：`argc` 是命令行参数个数，`argv` 是指向参数字符串的数组；`Verilated::commandArgs` 将它们交给 Verilator。`tfp->open("gpt2_block_sim.vcd")` 打开波形文件只是源码行为；本次没执行仿真，因此没有生成该 VCD。

1. 881–909 行将 clk、复位、启动、微码写口、数据 SRAM TB 口、DMA done 等输入初始化，构建三个 LUT 并复位。
2. 912–937 行生成数据和软件 golden，加载微码和数据。`num_instrs` 是 load_microcode 返回的条数，静态推算为 117。
3. 940–945 行先设置 `ucode_len`，将 `start_pulse` 置 1 后调用一次 `tick`，然后拉低；此后同步电路依据自身寄存状态运行。
4. 947–983 行 `while (cycle < MAX_CYCLES && !done)` 先 `tick(); cycle++;`，若看到 DMA 捕获就调用逐字节拷贝，再拉高 DMA done 并额外 tick。注意 `handle_dma_command` 自己调用的每次 SRAM 读/写都有 tick，**这些内部 tick 没有逐次增加 main 中 `cycle` 变量**，所以打印数不包含全部仿真时钟。
5. 985–989 行超时即关闭波形、释放对象并返回 1。正常结束后，进入验证并通过 `assert` 检查 vec 非忙；`assert` 在禁用断言的构建配置中可能不起作用，不能当作独立测试证明。
6. 1021–1025 行的 `auto read_sram_matrix = [](uint16_t base, int rows, int cols, int8_t* buf) {...};` 定义局部匿名函数。`[]` 是捕获列表，此处为空；它双层循环通过 `sram0_read()` 把 SRAM0 字节写入以 `buf` 指向的连续内存，`i*cols+j` 是行优先索引。
7. LN1 检查只是信息输出；接着用 **actual_ln1** 作为 C++ 对照的输入计算多头结果，对 ATTN_concat 进行比较。然后多次读取 **actual_attn、actual_wo、actual_ln2、actual_gelu、actual_ffn2**，为下一段重算参考。LN2 同样只是信息输出。
8. `verify_matrix` 在不一致超过 tolerance 时递增 `mismatches`；参与布尔判定的部分若 mismatch，则 `all_pass=false`。1177–1184 行对最终 X_OUT 比较用的是 actual_ffn2 和 actual_x2，而非全程纯软件的 X_OUT_gold。
9. 1204 行 `pass = all_pass && (hw_gemm_count == 23) && (dma_count == 1)`。其他 completion count 有打印，但不直接参与这个表达式；1223–1227 行关闭并释放对象，返回状态。

`verify_matrix_strided` 虽然在文件中定义，阅读时不能仅因为函数存在就断言 main 运行时调用它；逐处核对调用点。类似地，golden 全模型和 follow-actual 两条参考路径均存在，要弄清具体断言实际用的是哪一条。
