# 第07讲（上）：DMA与AXI读通路——从外部地址到片上数据流

日期：2026-11-09。主线恢复点：第06讲SRAM/Bank/Buffer及Ping-Pong补充之后。

本讲沿用“硬件结构→变量含义与单位→数据/控制流→代码顺序与时序”。阅读原项目SystemVerilog，不改写或修改上游RTL。作业中的Verilog-2005要求属于作业支线，不影响本次阅读原始源码。

## 1. 当前学习位置与本讲范围

已经讲解MAC、PE、脉动阵列、GEMM控制、gemm_post、SRAM/Bank/Buffer及Ping-Pong；这些内容不重新开课，也不把“已讲解”等同于用户已完全掌握。

原14讲计划下一站是DMA与AXI。第07讲分为：

1. 本次：AXI基础、axi_dma_rd真实结构、反压、burst拆分、源码及逐拍时序。
2. 下一次：axi_dma_wr，重点为AW/W/B独立通道、WSTRB、WLAST与写响应。
3. 随后：128 bit数据流与8 bit SRAM的适配，以及DMA完成和Tile就绪的区别，再进入第08讲ISA/Fetch/Decode/Dispatch。

课程作业有独立进度，与项目主线分别记录在根目录HANDOFF.md。本对话按用户2026-11-09的新指令恢复tiny-NPU项目主线，不将作业未完成作为继续主线的前置条件。主线交接见npu_docs/handoff-tiny-npu-mainline.md。

## 2. 先明确三个硬件实体

SRAM保存数据；DMA是自动执行批量搬运的控制与数据通路；AXI定义搬运双方传地址、传数据和等待的规则。

DMA的全称为Direct Memory Access。控制器给它一次任务，例如“从外部字节地址0x1000起读取640 Byte”；DMA随后自行拆分请求、等待存储系统、接收数据并报告完成，无需CPU逐个数执行读指令。

外部DRAM不能仅用一条地址线直接接到片上SRAM写口。真实系统通常经互连和存储控制器访问DRAM。当前axi_dma_rd是AXI读主设备，它并不实现DRAM的行激活、预充电或刷新。

### 2.1 DMA为何分读和写

这里的“读/写”以外部存储访问为准：

| 模块 | 外部存储动作 | NPU侧数据方向 | 使用通道 |
|---|---|---|---|
| axi_dma_rd | 从外部地址读取 | 外部数据流入NPU | AR、R |
| axi_dma_wr | 向外部地址写入 | NPU结果流向外部 | AW、W、B |

读DMA最终也可能引起本地SRAM写入，所以不要把“DMA读”误解为“片上所有端口都只能读”。

### 2.2 期望的数据路径与当前真实连接

完整系统所需的数据路径是“外部存储→读DMA数据流→宽度/字节适配→本地SRAM→计算引擎”。控制器还必须保存本地目的地址、长度、目标Bank等信息。

本版本axi_dma_rd端口只有外部cmd_addr、cmd_len、cmd_tag，输出data_out/valid/last/tag；没有本地SRAM目的地址和写端口。它负责将外部读取转成内部数据流，目的位置和落存由外围逻辑负责。

核对rtl/top.sv后发现：

~~~systemverilog
assign dma_rd_data_ready = 1'b1; // Always accept DMA data (placeholder)
~~~

读流连接到dma_rd_data等内部信号，当前文件未将它转换为数据SRAM写操作。写DMA的数据输入也被置为无效：

~~~systemverilog
.data_valid (1'b0),
.data_in    ({P_AXI_DATA_W{1'b0}}),
.data_last  (1'b0),
~~~

因此“DMA模块存在”和“整条DDR↔SRAM通路已完成”是两个不同层面的事实。

之前GEMM学习使用的sim/verilator/onnx_sim_top.sv采用DMA Shim：捕获命令并向C++ Testbench暴露地址、长度与方向，完成由dma_done_pulse输入确认。它没有实例化这两个AXI DMA。Graph仿真中的搬运机制不能当作AXI总线RTL已经运行的证据。

## 3. AXI五个通道：先数清信息的方向

| 通道 | 全称 | 主设备与从设备之间的信息方向 | 内容 |
|---|---|---|---|
| AR | Read Address | DMA→存储系统 | 读起始地址、拍数、每拍大小 |
| R | Read Data | 存储系统→DMA | 数据、响应、当前burst末拍 |
| AW | Write Address | DMA→存储系统 | 写起始地址、拍数、每拍大小 |
| W | Write Data | DMA→存储系统 | 写数据、字节使能、当前burst末拍 |
| B | Write Response | 存储系统→DMA | 写事务响应 |

每个通道还有反方向的READY反馈。R通道中存储系统发送RVALID，DMA发送RREADY；读操作仍由DMA作为主设备发起。主设备身份与某条数据线的传输方向不能混为一谈。

本讲只精读AR与R；AXI4-Lite控制寄存器接口先保留为系统位置知识，不在本讲展开。

## 4. 握手：什么时候才算一次真实传输

统一判断条件为：

$$fire = valid \land ready.$$

在上升沿前二者同时为1，该上升沿完成一次传输。VALID表示发送端提供有效内容，READY表示接收端本拍能够接收。

| valid | ready | 本沿含义 |
|---:|---:|---|
| 0 | 0 | 无传输 |
| 0 | 1 | 接收端可用，发送端没有有效项 |
| 1 | 0 | 有效项正在等待，未传输 |
| 1 | 1 | 接收一项 |

“一个beat”指一次数据项的传输；等待的周期不增加beat数量。一个burst包含若干beat，其间可以有空拍或反压，不保证每个时钟周期都传一个beat。

发送端一旦声明VALID，遇到READY=0必须保持VALID及对应内容，直到握手。发送端不应等待READY出现后才肯声明VALID。

本模块有三种独立握手：

| 名称 | 判定 | 完成的工作 |
|---|---|---|
| 命令握手 | cmd_valid && cmd_ready | 接受一整个DMA任务 |
| AR握手 | m_axi_arvalid && m_axi_arready | 接受一个burst的读地址请求 |
| R/输出握手 | m_axi_rvalid && m_axi_rready，等价于本模块data_valid && data_ready | 接受一份128 bit数据 |

命令握手不表示已经取到数据，AR握手也不表示burst已经完成。

## 5. 位宽、字节、beat与burst

默认参数：

~~~systemverilog
parameter int AXI_DATA_W    = 128;
parameter int AXI_ADDR_W    = 32;
parameter int MAX_BURST_LEN = 16;

localparam int BYTES_PER_BEAT = AXI_DATA_W / 8;
localparam int BEAT_SHIFT     = $clog2(BYTES_PER_BEAT);
~~~
$$
\text{每个beat的数据量}
=\frac{128}{8}
=16\ \text{Byte}
$$
- **Byte**：字节数量。
- **beat**：一份数据通过握手完成传输。
- **burst**：一个地址请求对应的一组beat。
得到每beat为16 Byte、BEAT_SHIFT为4。这里按16 Byte对齐的地址和完整16 Byte数据项讲解本模块。
每个burst最多16个beat，即最多256 Byte。

| 名称 | 默认值或表达式 | 单位/意义 |
|---|---:|---|
| AXI_DATA_W | 128 | bit，每份数据宽度 |
| BYTES_PER_BEAT | 16 | Byte/beat |
| MAX_BURST_LEN | 16 | beat/burst，当前设计配置 |
| 最大普通burst容量 | 16×16=256 | Byte/burst |
| AXI_ADDR_W | 32 | bit，外部字节地址宽度 |
| cmd_len | 24 bit | Byte，一整个任务所需长度 |
| ARLEN | beats−1 | 编码值，不是Byte |
| ARSIZE | log2(16)=4 | 编码值，表示每beat最多16 Byte |
| ARBURST | 2'b01 | INCR，递增地址模式 |

128 bit总线一份数据可以承载16个INT8或8个FP16。DMA不解释它们是权重、激活还是浮点数，只搬bit。

本模块把ARSIZE固定为总线满宽对应的值。不能将“参数AXI支持多种大小”直接理解为“本实现每次命令都能自由选择窄传输”。

## 6. axi_dma_rd的实际硬件结构

可以把模块拆成“控制寄存器与组合计算”以及“数据直通路径”。

~~~mermaid
flowchart TB
    CMD["命令：外部地址、长度、tag"] --> CTRL["FSM与进度寄存器"]
    CTRL --> CALC["剩余长度、4KiB边界、burst上限计算"]
    CALC --> AR["AR地址与控制输出"]
    AR --> MEM["AXI互连与存储系统"]
    MEM --> R["R数据直通到data_out"]
    OUT["下游接收端"] -->|"data_ready"| R
    R -->|"data_valid与128 bit数据"| OUT
    R -->|"成功握手事件"| CTRL
~~~

此图描述模块层次，不将尚未接好的本地SRAM适配器画成已集成实体。

实际需要的主要硬件：

- 3 bit状态寄存器与下一状态组合逻辑。
- 外部地址寄存器cur_addr及加法器。
- 剩余字节寄存器bytes_remaining及减法/比较逻辑。
- burst长度寄存器及几个最小值比较选择器。
- 计数、tag与错误寄存器。
- R数据到内部输出的组合连线。

源码没有128 bit数据FIFO，也没有完整tile存储空间。data_out不是将总线数据先存一拍再送出。

## 7. 端口与内部变量：名称、宽度、单位与生命周期

### 7.1 命令接口

| 信号 | 默认宽度 | 方向（相对读DMA） | 意义 |
|---|---:|---|---|
| cmd_valid | 1 bit | 输入 | 控制器提供有效命令 |
| cmd_ready | 1 bit | 输出 | 仅IDLE为1，DMA能收新命令 |
| cmd_addr | 32 bit | 输入 | 外部起始字节地址 |
| cmd_len | 24 bit | 输入 | 需要的字节数 |
| cmd_tag | 4 bit | 输入 | 任务标识，锁存后保持到任务结束 |

源码在IDLE且cmd_valid时锁存命令。因为cmd_ready恰好只在IDLE为1，这等价于命令握手。忙时到来的单拍cmd_valid不会排队，发送者必须按握手协议维持有效命令。

### 7.2 AR与R接口

| 信号 | 默认宽度 | 意义与有效条件 |
|---|---:|---|
| m_axi_arid | 4 bit | 请求ID，来自tag_r |
| m_axi_araddr | 32 bit | 当前burst首字节地址 |
| m_axi_arlen | 8 bit | 当前burst拍数减1 |
| m_axi_arsize | 3 bit | 默认4，代表16 Byte |
| m_axi_arburst | 2 bit | 固定INCR |
| m_axi_arvalid/arready | 各1 bit | AR握手 |
| m_axi_rid | 4 bit | 返回ID；本实现未校验 |
| m_axi_rdata | 128 bit | 当前返回数据 |
| m_axi_rresp | 2 bit | 响应码，非OKAY时记录错误 |
| m_axi_rlast | 1 bit | 当前burst的最后一个beat |
| m_axi_rvalid/rready | 各1 bit | R握手 |

AR字段只在ARVALID有效期间作为请求内容解释，RDATA只在RVALID有效时解释。不能把空闲期data_out的数值变化当作已接收新数据。

### 7.3 内部数据流及状态

| 信号 | 宽度 | 意义 |
|---|---:|---|
| data_out | 128 bit | 直接连接m_axi_rdata |
| data_valid | 1 bit | RECV状态且RVALID有效 |
| data_ready | 1 bit | 下游有能力接收完整一项 |
| data_last | 1 bit | 当前有效数据是整个命令的最后一项 |
| data_tag | 4 bit | 当前命令锁存的tag |
| busy | 1 bit | 计算burst、发AR或接收数据期间为1 |
| done | 1 bit | DONE状态的单周期指示 |
| error | 1 bit | 任务期间粘滞错误位；下一命令接收时清除 |

data_last跟随有效数据，允许在data_ready=0时保持为1；只有与data_valid和data_ready共同握手才表示最后一项真正被接收。

### 7.4 内部寄存器与组合信号

| 变量 | 宽度 | 单位及作用 |
|---|---:|---|
| state/state_nxt | 各3 bit | 当前状态/组合计算的下一状态 |
| cur_addr | 32 bit | Byte地址，初始化为cmd_addr，每次数据握手加16 |
| bytes_remaining | 24 bit | 任务尚待接收的Byte数 |
| burst_len | 8 bit | 当前burst拍数减1，与ARLEN同编码 |
| beat_cnt | 8 bit | 当前burst已接收拍数，计算新burst时清0 |
| total_beats | 24 bit | 整个命令向上取整的总拍数 |
| beats_done | 24 bit | 整个命令已接收拍数 |
| tag_r | 4 bit | 锁存命令tag |
| error_r | 1 bit | 记录是否见过非OKAY响应 |
| remaining_beats | 24 bit | 剩余字节向上取整折算为拍数 |
| addr_in_4k | 12 bit | 当前地址在4KiB区间内的字节偏移 |
| bytes_to_4k | 13 bit | 距下个4KiB边界的Byte数，可表示4096 |
| beats_to_4k | 9 bit | 默认128 bit配置下到边界可用的拍数，最大256 |
| max_burst_beats | 9 bit | 剩余拍数与配置上限的较小者 |
| capped_beats | 9 bit | 再受4KiB边界限制后的拍数 |

beat_cnt、total_beats和beats_done虽被维护，本版本没有用它们来核验RLAST或判定正常完成。读状态退出实际依赖握手后的RLAST，不能替源码补出“自动检查拍数”的能力。

## 8. 数据流、控制流与反压

数据流：RDATA→data_out→下游接收端。控制流：FSM决定何时发地址、何时允许接收；下游用data_ready控制接收速度。

原码：

~~~systemverilog
assign m_axi_rready = (state == S_RECV_DATA) && data_ready;
assign data_valid  = (state == S_RECV_DATA) && m_axi_rvalid;
assign data_out    = m_axi_rdata;
~~~

在RECV状态，m_axi_rready等于data_ready，所以总线接收和下游接收发生在同一个沿。本模块不会出现“已经接收R数据，却暂时放在内部FIFO”的阶段。

若下游无法接收，data_ready变0，RREADY随之为0；如果存储系统此时已经给出RVALID，它必须保持该数据直到握手。等待期间，DMA不推进地址、字节计数或已接收拍数。

这叫反压。它作用于数据流的接收节奏，不是在存储系统已经交付后再把数据丢弃。

## 9. 一个命令如何拆成多个burst

假设：

- cmd_addr=0x1000，16 Byte对齐。
- cmd_len=640 Byte。
- 每beat=16 Byte，MAX_BURST_LEN=16。

总拍数为640/16=40，需拆成16+16+8。

| burst | 首地址 | 拍数 | ARLEN | 本burst字节数 |
|---:|---|---:|---:|---:|
| 0 | 0x1000 | 16 | 15 | 256 |
| 1 | 0x1100 | 16 | 15 | 256 |
| 2 | 0x1200 | 8 | 7 | 128 |

一个burst只通过AR给出首地址和控制信息，后续beat地址由INCR规则推导，不需要每个beat重新握手一个AR地址。本模块仍在每次R握手时更新cur_addr，用来跟踪任务进度及准备下一burst地址。

### 9.1 为什么有4KiB边界

AXI规定单个burst不能跨越4KiB地址边界。整个DMA命令可以跨越，方法是拆成多个合法burst。

例如cmd_addr=0x0FF0、cmd_len=64 Byte：

| burst | 首地址 | 拍数 | 字节范围 |
|---:|---|---:|---|
| 0 | 0x0FF0 | 1 | 0x0FF0～0x0FFF |
| 1 | 0x1000 | 3 | 0x1000～0x102F |

这里4KiB只是总线地址分段边界，不意味着操作系统页表，也不等于DRAM行大小。

### 9.2 源码怎样计算

~~~systemverilog
assign remaining_beats = bytes_remaining[23:BEAT_SHIFT]
                       + (|bytes_remaining[BEAT_SHIFT-1:0] ? 24'd1 : 24'd0);

assign addr_in_4k = cur_addr[11:0];
wire [12:0] bytes_to_4k = 13'd4096 - {1'b0, addr_in_4k};

assign beats_to_4k = bytes_to_4k[12:BEAT_SHIFT]
                  + (|bytes_to_4k[BEAT_SHIFT-1:0] ? 9'd1 : 9'd0);
~~~

BEAT_SHIFT=4时：

- bytes_remaining[23:4]等价于无符号整数除以16取整。
- 低4 bit表示余数。
- 前缀“|”为归约或：低位任一bit为1就得到1。
- 有余数再加1，实现向上取整。
- {1'b0, addr_in_4k}将12 bit偏移扩成13 bit，使减法能保留4096。

随后比较选择：

~~~systemverilog
assign max_burst_beats = (remaining_beats < MAX_BURST_LEN[8:0])
                      ? remaining_beats[8:0] : MAX_BURST_LEN[8:0];
assign capped_beats = (max_burst_beats < beats_to_4k)
                    ? max_burst_beats : beats_to_4k;
~~~

默认对齐情形下，其含义是：

$$N_{\mathrm{burst}}=\min\left(
\left\lceil\frac{L_{\mathrm{remaining}}}{16}\right\rceil,
16,
\frac{4096-(addr\bmod4096)}{16}
\right).$$

硬件主要是固定位切片、归约或、加减法和比较选择器；这里无需通用除法器。

注意只针对已核对的默认128 bit配置讲解。beats_to_4k只有9 bit，不能据此推断任意更窄AXI_DATA_W参数组合都正确。

## 10. 按源码顺序读控制器

### 10.1 包导入、参数与常量

~~~systemverilog
module axi_dma_rd
    import axi_types_pkg::*;
#(
    parameter int AXI_DATA_W = 128,
    parameter int AXI_ADDR_W = 32,
    parameter int MAX_BURST_LEN = 16
) (...);
~~~

axi_types_pkg定义在rtl/bus/axi_types.sv，文件名不叫axi_types_pkg.sv。import引入ID位宽、响应编码、INCR编码和size辅助函数，不是实例化新的硬件模块。

localparam是派生常量；parameter是可配置参数。$clog2是编译时使用的向上取整log2，在本配置下为4。

### 10.2 状态声明与各状态硬件工作

~~~systemverilog
typedef enum logic [2:0] {
    S_IDLE,
    S_CALC_BURSTS,
    S_SEND_AR,
    S_RECV_DATA,
    S_DONE
} state_t;
~~~

| 状态 | 核心动作 | 等待条件 |
|---|---|---|
| IDLE | cmd_ready=1，接收并锁存命令 | cmd_valid |
| CALC | 根据剩余量确定burst_len；若已无字节则去DONE | 不等待外部握手 |
| SEND_AR | ARVALID=1，保持请求字段 | ARREADY |
| RECV_DATA | 将R数据转发给下游，按成功握手推进 | RVALID、data_ready、RLAST |
| DONE | done=1 | 下一沿自动回IDLE |

~~~mermaid
stateDiagram-v2
    [*] --> IDLE
    IDLE --> CALC: 命令握手
    CALC --> SEND_AR: 剩余字节大于0
    CALC --> DONE: 剩余字节等于0
    SEND_AR --> SEND_AR: AR尚未握手
    SEND_AR --> RECV: AR握手
    RECV --> RECV: 尚未接收burst末拍
    RECV --> CALC: 末拍握手且沿前剩余量非0
    RECV --> DONE: 末拍握手且沿前剩余量为0
    DONE --> IDLE
~~~

RECV→DONE是源码中存在的分支。正常非零命令的最后一个beat到达前，剩余量仍是1～16 Byte，因此通常走RECV→CALC→DONE；见后面的逐拍表。

### 10.3 下一状态组合逻辑

~~~systemverilog
S_SEND_AR:
    if (m_axi_arvalid && m_axi_arready)
        state_nxt = S_RECV_DATA;

S_RECV_DATA:
    if (m_axi_rvalid && m_axi_rready && m_axi_rlast) begin
        if (bytes_remaining == 24'd0)
            state_nxt = S_DONE;
        else
            state_nxt = S_CALC_BURSTS;
    end
~~~

地址阶段等AR握手，接收阶段等“R握手且当前项带RLAST”。仅看到RLAST=1而没有握手，不应切换状态。

state_nxt=state作为默认赋值，让未满足条件时保持状态；它不是在每次进入case时都重新从IDLE执行。

### 10.4 状态寄存器与非阻塞赋值

~~~systemverilog
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        state <= S_IDLE;
    else
        state <= state_nxt;
end
~~~

always_comb计算下一个选择结果，always_ff在沿上保存选择结果。两个时序块在同一沿都读取沿前寄存器值，不按代码书写顺序让一个块立刻看到另一个块的新值。

这正是最终beat握手后仍多停一拍CALC的原因。

### 10.5 IDLE锁存命令

~~~systemverilog
cur_addr        <= cmd_addr;
bytes_remaining <= cmd_len;
tag_r           <= cmd_tag;
error_r         <= 1'b0;
beats_done      <= 24'd0;
total_beats     <= cmd_len[23:BEAT_SHIFT]
                 + (|cmd_len[BEAT_SHIFT-1:0] ? 24'd1 : 24'd0);
~~~

任务开始后依赖内部寄存器推进，而非持续读取控制器的cmd_addr/cmd_len。任务发出者在握手后可以准备下一条命令，但不能在cmd_ready=0时假设下一条已被接受。

### 10.6 CALC锁存burst长度

~~~systemverilog
if (bytes_remaining != 24'd0) begin
    burst_len <= capped_beats[7:0] - 8'd1;
    beat_cnt  <= 8'd0;
end
~~~

capped_beats是“拍数”，burst_len是“拍数减1”。从CALC进入SEND_AR后，burst_len已经锁存，因此等待ARREADY期间ARLEN稳定。

### 10.7 RECV按实际握手更新进度

~~~systemverilog
if (m_axi_rvalid && m_axi_rready) begin
    beat_cnt   <= beat_cnt + 8'd1;
    beats_done <= beats_done + 24'd1;
    cur_addr   <= cur_addr + AXI_ADDR_W'(BYTES_PER_BEAT);

    if (bytes_remaining >= BYTES_PER_BEAT[23:0])
        bytes_remaining <= bytes_remaining - BYTES_PER_BEAT[23:0];
    else
        bytes_remaining <= 24'd0;

    if (m_axi_rresp != AXI_RESP_OKAY)
        error_r <= 1'b1;
end
~~~

AXI_ADDR_W'(BYTES_PER_BEAT)是SystemVerilog的指定位宽转换，在本配置下把常数16转换到32 bit地址计算的位宽；不是创建AXI_ADDR_W个寄存器实例。

最后不足16 Byte时，剩余量饱和到0，避免无符号减法下溢成很大的数。遇到错误仍继续接收，error_r保持1到下一命令开始；done不等价于无错误成功。

### 10.8 AR输出

~~~systemverilog
assign m_axi_arid    = tag_r;
assign m_axi_araddr  = cur_addr;
assign m_axi_arlen   = burst_len;
assign m_axi_arsize  = axi_size_from_bytes(BYTES_PER_BEAT);
assign m_axi_arburst = AXI_BURST_INCR;
assign m_axi_arvalid = (state == S_SEND_AR);
~~~

SEND_AR期间既不收R数据也不改变cur_addr/burst_len，所以如果ARREADY持续为0，AR地址、长度和ID会保持。R握手时的cur_addr递增发生在RECV，此时ARVALID为0，不会表示又发出一条地址请求。

此实现一次只允许一个burst未完成，上一burst末拍接收后才计算并发下一个，结构简单，但无法靠多个未完成请求隐藏存储延迟。

### 10.9 RLAST、data_last与done

~~~systemverilog
assign data_last = (state == S_RECV_DATA) && m_axi_rvalid
                 && m_axi_rlast
                 && (bytes_remaining <= BYTES_PER_BEAT[23:0]);

assign cmd_ready = (state == S_IDLE);
assign busy      = (state != S_IDLE) && (state != S_DONE);
assign done      = (state == S_DONE);
assign error     = error_r;
~~~

| 信号 | 所属范围 | 640 Byte、3个burst例子 |
|---|---|---|
| m_axi_rlast | 一个AXI burst | 各burst末拍都为1，共3项 |
| data_last | 整个DMA命令的数据流 | 只有第40项为1 |
| done | 命令控制完成状态 | 最后一项被下游接受后，经过CALC再进入DONE |

data_last是数据项属性，done是控制器状态。它们不是同一个周期语义。

## 11. 把32 Byte命令走完：包括AR等待和末拍反压

设cmd_addr=0x1000，cmd_len=32，tag=3，两份数据为D0、D1，正常响应OKAY。表格记录每个上升沿前的条件与沿后的状态。时序由源码推导，未声称来自RTL仿真。

| 沿 | 沿前状态 | 沿前关键条件 | 本沿事件 | 沿后状态、地址及剩余量 |
|---|---|---|---|---|
| C0 | IDLE | cmd_valid=1、cmd_ready=1 | 接收命令 | CALC；0x1000；32 Byte |
| C1 | CALC | capped_beats=2 | 锁存burst_len=1 | SEND_AR；0x1000；32 |
| C2 | SEND_AR | ARVALID=1、ARREADY=0 | 请求等待 | SEND_AR；0x1000；32 |
| C3 | SEND_AR | ARVALID=1、ARREADY=1 | AR握手 | RECV；0x1000；32 |
| C4 | RECV | RVALID=1、data_ready=1、D0、RLAST=0 | 接收D0 | RECV；0x1010；16 |
| C5 | RECV | RVALID=1、data_ready=0、D1、RLAST=1 | 未接收D1 | RECV；0x1010；16 |
| C6 | RECV | 条件同C5 | 继续等待 | RECV；0x1010；16 |
| C7 | RECV | RVALID=1、data_ready=1、D1、RLAST=1 | 接收最后一项 | CALC；0x1020；0 |
| C8 | CALC | bytes_remaining=0 | 不发新AR | DONE；done在沿后为1 |
| C9 | DONE | 无需外部条件 | 结束DONE | IDLE；cmd_ready在沿后为1 |

对应观察点：

- C2和C3之前的AR字段相同：地址0x1000、ARLEN=1、ARSIZE=4、ARID=3。
- C5、C6等待时，D1、RLAST和data_last都保持；data_last=1不代表已经完成接收。
- 只有C4、C7增加beats_done，因此共接收两项。
- C7沿前bytes_remaining仍是16，下一状态判断看到16，故选CALC；沿后它才变为0。
- C8沿后done=1，此时busy=0、cmd_ready=0；下一沿进入IDLE后才能收新任务。
- 若RVALID也有空拍，地址与计数同样不能前进。

因此不能将DMA总延迟简单写成“字节数/16”。还包含命令/计算/地址阶段、外部首次响应延迟、burst间切换以及反压。

## 12. 回到8 bit SRAM：为什么还需要适配器

前一讲的8 bit SRAM单写口每沿写1 Byte，读DMA一次成功握手则交付16 Byte。这是明确的宽度与吞吐差异。

一种可实现的适配结构（设计示意，当前top.sv未实现）为：

1. 用128 bit寄存器接住一项DMA数据。
2. 用4 bit字节索引0～15逐个选出8 bit。
3. 保存本地目的地址，每次SRAM成功写入后加1。
4. 缓存还没腾空时降低data_ready，让DMA反压外部R通道。
5. 保存命令长度，处理最后一项中真正有效的字节数。

这个适配器的128 bit寄存器可以容纳1项，却不能改变长期写带宽。若只有1 Byte/cycle的写口且没有额外并行写能力，长期吞吐受SRAM写口限制。若改为128 bit宽SRAM，或16条具备实际写端口的8 bit通道，才可能让16 Byte在一沿中同时落存；仅声明多个Bank并不足以自动获得这些独立通路。

### 12.1 任务最后不足16 Byte

例如cmd_len=20，外部会返回两项共32 Byte宽的数据。第二项只有4 Byte属于命令需要的范围。

当前读DMA没有data_keep或data_strb输出，它只提供data_last；下游必须保存原始长度或得到其他元信息，才能知道尾项只写4 Byte。否则会把额外12 Byte也写入目的SRAM。

本讲默认起始地址16 Byte对齐。原模块没有提供完整的任意非对齐起始地址重排、有效byte lane处理及错误拒绝机制，不能依据注释“byte-aligned”就认为任意字节地址都已正确支持。

### 12.2 DMA done与next_tile_ready

假设适配器在最后一次DMA握手时先将最后16 Byte收入寄存器，再逐字节写SRAM。此时读DMA可能已经进入完成阶段，但最后16 Byte尚未全部写入Tile Buffer。

因此安全的Tile就绪条件需要由外围控制确认：所需有效字节都已落入正确的目标Bank，而且本地写缓冲已经排空。不能直接将本模块done无条件接到next_tile_ready。

这正好衔接Ping-Pong：只有下一块可被计算侧安全读取，才满足“下一块已准备好”的含义。原tile_buffer占位输出并没有自动补齐这种DMA到存储的完成协议。

## 13. 阅读中确认的边界

| 项目 | 本版本可确认的行为 |
|---|---|
| 多命令排队 | 没有；IDLE才cmd_ready |
| 多burst并行未完成 | 没有；一个burst结束后才发下一个 |
| 数据缓存 | axi_dma_rd内部无数据FIFO |
| R响应错误 | 非OKAY记入粘滞error，继续搬运 |
| 返回ID核验 | 未使用m_axi_rid做匹配检查 |
| RLAST拍数核验 | 没有用计数器交叉核验 |
| 零长度命令 | 经过CALC到DONE，不发AR |
| 尾项有效字节 | 内部剩余量会饱和到0，输出无字节有效掩码 |
| 本地目的地址与写口 | 不在本模块中 |
| 顶层DDR到SRAM闭环 | 当前top.sv仍有占位连接 |
| Graph仿真搬运 | onnx_sim_top使用DMA Shim供C++处理，不是本AXI DMA |

这些结论来自固定版本源码阅读，不等于本讲已执行硬件修复或协议穷举验证。

## 14. 本次停点与下一步

本次已讲解第07讲上半部分，用户掌握程度仍待后续问题确认，不额外布置练习题。

下一次沿原计划继续axi_dma_wr：先看“写地址、写数据、写响应”三类硬件信息如何配合，再逐项解释beat_cnt、WSTRB、WLAST及WAIT_BRESP。之后补齐宽度适配与本地落存完成的结构，最后进入ISA/Fetch/Decode/Dispatch。

## 附录：来源及验证范围

源码统一固定到commit 8216c22b762011aa20c05fc2768423fd12dda59d：

- [axi_dma_rd.sv](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/rtl/bus/axi_dma_rd.sv)
- [axi_dma_wr.sv](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/rtl/bus/axi_dma_wr.sv)
- [axi_types.sv](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/rtl/bus/axi_types.sv)
- [top.sv](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/rtl/top.sv)
- [onnx_sim_top.sv](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/sim/verilator/onnx_sim_top.sv)
- [Arm AXI规范IHI0022H](https://developer.arm.com/-/media/Arm%20Developer%20Community/PDF/IHI0022H_amba_axi_protocol_spec.pdf)：A3.2握手、A3.4事务结构和burst/size编码。
- [Arm AXI规范IHI0022K](https://documentation-service.arm.com/static/651c285c15583d1bff972f94)：A3.2握手与稳定性要求。

本次实际读取上述RTL文件与仓库第06讲，逐分支核对读DMA；第07讲下半部分尚未展开讲解。未运行Icarus/Verilator，未生成VCD，逐拍表是源码推导。当前执行环境未发现iverilog或verilator；这不改变用户本机已安装工具的既有事实。没有修改上游RTL，没有改动课程作业文件。

