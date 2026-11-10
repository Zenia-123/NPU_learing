# axi_dma_rd：按程序顺序精读源码与全部变量

日期：2026-11-10。用户要求：按照程序顺序，先讲逻辑、再讲代码，并说明变量的含义与作用。

[固定版本原始源码：rtl/bus/axi_dma_rd.sv](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/rtl/bus/axi_dma_rd.sv)，共281行。与包定义和top连接均固定参考commit 8216c22b762011aa20c05fc2768423fd12dda59d。本讲逐段阅读原文件；不把程序文本自上而下逐行执行当成硬件运行方式。

例子默认AXI_DATA_W=128 bit、AXI_ADDR_W=32 bit、MAX_BURST_LEN=16 beat、外部起始地址16 Byte对齐。

## 一、先建立完整硬件逻辑

axi_dma_rd接受外部字节地址、总长度和tag，将一次读命令拆成一个或多个AXI读burst，发出AR地址，等待R返回，再把128 bit数据以valid/ready形式转发给下游。

~~~mermaid
flowchart TB
    CMD["控制器：命令、地址、长度、tag"] --> REG["命令与进度寄存器"]
    REG --> CALC["burst长度计算：剩余量、上限、边界"]
    CALC --> FSM["状态机"]
    FSM -->|"AR地址与控制"| MEM["AXI互连与存储系统"]
    MEM -->|"R数据、响应、RLAST"| OUT["数据直通输出"]
    OUT --> DOWN["内部数据接收者"]
    DOWN -->|"data_ready"| OUT
    OUT -->|"真实接收事件"| REG
~~~

这里的downstream是抽象接口，不证明当前top已接通SRAM。模块内部没有128 bit数据FIFO。实际top.sv中data_ready被固定1作为占位，读流尚未接入完整SRAM写路径。

一个命令的工作顺序：

1. IDLE中cmd_valid && cmd_ready：锁存外部字节地址、Byte长度和tag。
2. CALC计算当前burst能够读取的beat数，再锁存burst_len=beat数−1。
3. SEND_AR发送ARADDR、ARLEN、ARSIZE等，等待AR握手。
4. RECV_DATA：逐项转发RDATA；仅在RVALID && RREADY时推进计数、地址和剩余量。
5. 一项同时握手且RLAST=1时，结束当前burst；如有剩余回CALC准备下一burst。
6. 正常命令最后一项握手时，沿前bytes_remaining仍为1～16；源码先回CALC，剩余量沿后变0，下一沿进入DONE。
7. DONE状态done=1，一个周期后回IDLE。

三种不同的边界：一次DMA命令可以包含多个burst；一个burst可以包含多个beat；一个beat可以因等待持续多个时钟周期。模块一次只允许一个burst未完成。

## 二、外部端口：方向相对axi_dma_rd，单位必须分清

### 2.1 时钟和命令

| 信号 | 方向/默认位宽 | 内容、单位及什么时候有效 |
|---|---|---|
| clk | 输入1 bit | 状态及寄存器的上升沿时钟 |
| rst_n | 输入1 bit | 低有效异步复位；下降沿触发复位 |
| cmd_valid | 输入1 bit | 控制器正在提供有效命令 |
| cmd_ready | 输出1 bit | state为IDLE时为1；能在本沿接收命令 |
| cmd_addr | 输入32 bit | 整条命令的外部起始地址，按Byte编址 |
| cmd_len | 输入24 bit | 整条命令的字节数，单位Byte，范围由24 bit约束 |
| cmd_tag | 输入4 bit | 事务/命令标识，接收时锁存到tag_r |

cmd_valid && cmd_ready在上升沿表示实际接收。源代码只在IDLE检查cmd_valid，因为cmd_ready恰在IDLE为1。模块无命令FIFO：忙时控制器需要维持合法命令直到握手，短脉冲不会被缓存。

### 2.2 AR读地址通道

| 信号 | 方向/默认位宽 | 功能 |
|---|---|---|
| m_axi_arid | 输出4 bit | 当前请求的AXI ID，由tag_r驱动；AXI_ID_W来自axi_types_pkg |
| m_axi_araddr | 输出32 bit | 当前burst第一个地址，单位外部Byte地址 |
| m_axi_arlen | 输出8 bit | 当前burst拍数减1：2拍编码为1 |
| m_axi_arsize | 输出3 bit | 每拍Byte数的对数编码；默认16 Byte时为4，即3'b100 |
| m_axi_arburst | 输出2 bit | 地址变化方式；INCR=2'b01 |
| m_axi_arvalid | 输出1 bit | DMA给出的AR字段有效；SEND_AR时为1 |
| m_axi_arready | 输入1 bit | 对端本周期能够接收AR |

ARVALID且ARREADY在沿前都为1，那个沿接受整笔burst的首地址与控制信息。未握手前AR字段保持。后续beat地址按照INCR规则计算，不代表每beat发一次AR。

### 2.3 R读数据、内部数据流与状态

| 信号 | 方向/默认位宽 | 功能 |
|---|---|---|
| m_axi_rid | 输入4 bit | 返回的AXI ID；当前源码没有使用它核对tag |
| m_axi_rdata | 输入128 bit | 当前返回数据项；RVALID有效时才应解释 |
| m_axi_rresp | 输入2 bit | 当前项的响应；非AXI_RESP_OKAY会被记录 |
| m_axi_rlast | 输入1 bit | 当前AXI burst的最后一项标记 |
| m_axi_rvalid | 输入1 bit | 对端当前R数据有效 |
| m_axi_rready | 输出1 bit | DMA当前愿意接收R项；受data_ready控制 |
| data_out | 输出128 bit | 直接连接m_axi_rdata，没有FIFO |
| data_valid | 输出1 bit | RECV状态且m_axi_rvalid为1时有效 |
| data_ready | 输入1 bit | 下游本周期可以接收该128 bit项 |
| data_last | 输出1 bit | 当前有效数据是整个DMA命令的末项；可能在阻塞期间持续1 |
| data_tag | 输出4 bit | 当前锁存的命令tag；top实例没有接此输出 |
| busy | 输出1 bit | state既非IDLE也非DONE时为1 |
| done | 输出1 bit | state为DONE时为1，表示控制器结束，不单独保证无错或本地SRAM落存 |
| error | 输出1 bit | error_r粘滞输出，下一命令被接收时清零 |

data_last只在data_valid=1时解释；若data_ready=0，虽然data_last已经为1，但最终项还没有被下游接收。整个命令的末项交付发生在data_valid && data_ready && data_last同沿成立。

## 三、内部变量：它们是寄存器还是组合线？

### 3.1 参数和派生常数

| 名称 | 默认值/位宽 | 作用 |
|---|---|---|
| AXI_DATA_W | 128 bit | RDATA和data_out总线位宽 |
| AXI_ADDR_W | 32 bit | 外部字节地址位宽 |
| MAX_BURST_LEN | 16 beat | 一笔burst最多拍数，是模块配置上限 |
| BYTES_PER_BEAT | 16 Byte/beat | AXI_DATA_W/8 |
| BEAT_SHIFT | 4 | clog2(16)，用于按16的倍数换算 |
| AXI_ID_W | 4 bit | package中定义的AXI ID宽度 |

parameter/localparam不是在运行时递增的计数器，它们是参数和派生常数。localparam由模块参数确定，不在此作为独立运行态变量配置。

### 3.2 状态与寄存器

| 变量 | 默认位宽/单位 | 何时改变、实际作用 |
|---|---|---|
| state | 3 bit | 时钟沿保存当前FSM状态；复位IDLE |
| state_nxt | 3 bit | always_comb组合算出的下一状态，不是独立状态寄存器 |
| cur_addr | 32 bit，外部Byte地址 | 命令握手载入cmd_addr；每次R握手加16，指示当前进度及下一burst起始位置 |
| bytes_remaining | 24 bit，Byte | 命令握手载入cmd_len；每次R握手减16，尾项不足16时饱和到0 |
| burst_len | 8 bit，beat数减1 | CALC状态锁存capped_beats−1；驱动ARLEN |
| beat_cnt | 8 bit，beat | 每个burst计算时清0，每次R握手加1；本实现未用于完成或RLAST检查 |
| total_beats | 24 bit，beat | 命令接收时锁存ceil(cmd_len/16)；本实现未用于FSM和输出判断 |
| beats_done | 24 bit，beat | 命令开始清0，每次R握手加1；本实现未用于FSM和输出判断 |
| tag_r | 4 bit | 命令接收时锁存cmd_tag，驱动ARID和data_tag |
| error_r | 1 bit | reset或新命令时清0；任何有效R握手的RRESP非OKAY时置1，其后保持 |

重要：不要以为total_beats/beats_done虽然算了就必然参与控制。实际完成路径由RLAST和bytes_remaining决定。beat_cnt也没有用于核验RLAST位置。它们未被其他逻辑观察时可能被综合工具优化。

cur_addr在CALC/SEND_AR时用于本burst首地址；RECV_DATA中随着已接收beat逐项加16，并不是整个burst期间一直不变。最后尾项仅需要4 Byte时该寄存器仍加16，这是内部地址进度，不表示多出来的12 Byte都属于命令需要的数据。

### 3.3 组合中间量

| 名称 | 位宽/单位 | 功能 |
|---|---|---|
| remaining_beats | 24 bit，beat | 将bytes_remaining按16 Byte/beat向上取整 |
| addr_in_4k | 12 bit，Byte偏移 | cur_addr在4KiB地址区间中的偏移，即低12位 |
| bytes_to_4k | 13 bit，Byte | 从cur_addr到下个4KiB边界剩余字节；需要表示4096 |
| beats_to_4k | 9 bit，beat | 默认配置下，从当前地址到边界可安排的beat数 |
| max_burst_beats | 9 bit，beat | remaining_beats与MAX_BURST_LEN中的较小者 |
| capped_beats | 9 bit，beat | max_burst_beats和beats_to_4k中的较小者，是真实beat数 |

这些值由assign驱动，随着输入寄存器变化自动变化；它们不表示额外经过一个时钟沿存储。burst_len才是在CALC状态沿上保存的8 bit结果。

## 四、按源码顺序：第1站模块头、参数和端口（约第10～65行）

~~~systemverilog
module axi_dma_rd
    import axi_types_pkg::*;
#(
    parameter int AXI_DATA_W    = 128,
    parameter int AXI_ADDR_W    = 32,
    parameter int MAX_BURST_LEN = 16
) (
    input logic clk,
    input logic rst_n,
    // 命令、AR、R、数据输出、状态端口见第二节
);
~~~

实际文件各端口以信号列表逐一声明；本处省略端口列表，仅展示模块头部组织。

import axi_types_pkg::*引入包里的定义，比如AXI_ID_W、AXI_BURST_INCR、AXI_RESP_OKAY和axi_size_from_bytes。包的文件名是rtl/bus/axi_types.sv。import用于可见性，不会实例化一个独立硬件模块。

input/output是以当前DMA模块为参考定义方向。例如RDATA从存储系统进入DMA，是input；RREADY从DMA送回存储系统，是output。logic [AXI_DATA_W-1:0]在默认参数下是logic [127:0]，共128 bit。

parameter允许在实例化模块时设置值；代码当前包和切片宽度存在参数边界，不可把“参数化”误解为任意数据宽度都经验证。

## 五、第2站派生常数（约第70～72行）

~~~systemverilog
localparam int BYTES_PER_BEAT = AXI_DATA_W / 8;
localparam int BEAT_SHIFT = $clog2(BYTES_PER_BEAT);
~~~

- 128 bit / 8 = 16 Byte，BYTES_PER_BEAT=16。
- 2^4=16，所以BEAT_SHIFT=4。
- $clog2是向上取整的对数函数；在这个默认参数组合下用于常数计算。
- 后面通过位切片与归约或完成按16的向上取整，不是每次实例化一个通用除法器。

## 六、第3站状态定义（约第78～96行）

~~~systemverilog
typedef enum logic [2:0] {
    S_IDLE,
    S_CALC_BURSTS,
    S_SEND_AR,
    S_RECV_DATA,
    S_DONE
} state_t;

state_t state, state_nxt;
~~~

typedef enum定义有名字的状态编码类型state_t，底层3 bit；state保存当前状态，state_nxt由组合逻辑计算。枚举值不是五个独立的状态寄存器；具体硬件编码仍取决于综合。

| 状态 | 做什么 | 等待/推进 |
|---|---|---|
| S_IDLE | 允许接收并锁存命令 | cmd_valid && cmd_ready |
| S_CALC_BURSTS | 根据剩余量、burst上限、4KiB边界决定下一burst长度 | 剩余0则DONE；否则SEND_AR |
| S_SEND_AR | 提供一笔burst的AR地址和控制 | ARVALID && ARREADY |
| S_RECV_DATA | 数据直通下游并在握手时更新进度 | 本burst的RLAST项完成R握手 |
| S_DONE | done=1、busy=0 | 下一沿回IDLE |

这些状态与寄存器由时钟驱动。always_comb、always_ff和assign是并行协作的硬件进程，不是每拍从文件第一行顺序运行到最后一行的CPU程序。

## 七、第4站burst拍数计算（约第104～130行）

### 7.1 逻辑：为什么要取三个量的最小值

以下只对本讲的默认128 bit和16 Byte对齐地址：

- 不能超过剩余命令需要的beat数。
- 不能超过MAX_BURST_LEN=16 beat。
- 一个AXI burst不能跨4KiB地址边界。

~~~text
当前burst拍数
= min(剩余所需拍数, 配置上限, 距4KiB边界的拍数)
~~~

AXI规则是“一个burst不跨4KiB”，不是“整个DMA命令不能跨4KiB”。整个命令可以通过拆分多个burst跨界。

### 7.2 代码：剩余Byte转换成beat

~~~systemverilog
assign remaining_beats = bytes_remaining[23:BEAT_SHIFT]
                       + (|bytes_remaining[BEAT_SHIFT-1:0]
                          ? 24'd1 : 24'd0);
~~~

默认BEAT_SHIFT=4：

- bytes_remaining[23:4]相当于无符号数除以16向下取整。
- bytes_remaining[3:0]是除以16的余数。
- 一元归约或 |bytes_remaining[3:0]：4个低位只要有1个为1，结果就是1。
- 三目运算 condition ? A : B：条件真选A，假选B。
- 因此有余数加1，得到ceil(bytes_remaining/16)。

例：20 Byte = 16 + 4；高位商为1、低4位非零，remaining_beats=1+1=2。32 Byte时商为2、余数为0，结果2，不额外加1。

不能把24'd1理解为24个beat；它是“位宽24 bit、十进制数值1”。

### 7.3 代码：当前地址离4KiB边界还有多远

~~~systemverilog
assign addr_in_4k = cur_addr[11:0];

wire [12:0] bytes_to_4k =
    13'd4096 - {1'b0, addr_in_4k};

assign beats_to_4k = bytes_to_4k[12:BEAT_SHIFT]
                    + (|bytes_to_4k[BEAT_SHIFT-1:0]
                       ? 9'd1 : 9'd0);
~~~

4KiB=4096=2^12 Byte，所以地址低12位是该区间内的Byte偏移。

大括号{1'b0, addr_in_4k}为拼接：在12 bit偏移最高位补一个0变成13 bit。13 bit的bytes_to_4k可以表示4096；12 bit无符号最大只能表示4095。

beats_to_4k也是除16向上取整。对16 Byte对齐地址，bytes_to_4k本身为16的倍数，因此余数为0。该实现并未完整处理一般非对齐起始地址的数据lane、地址推进与有效字节；不能因为这里使用向上取整就断言任意字节地址均被正确支持。

### 7.4 代码：两级最小值选择

~~~systemverilog
assign max_burst_beats =
    (remaining_beats < MAX_BURST_LEN[8:0])
        ? remaining_beats[8:0]
        : MAX_BURST_LEN[8:0];

assign capped_beats =
    (max_burst_beats < beats_to_4k)
        ? max_burst_beats
        : beats_to_4k;
~~~

第一行选择“剩余所需”和“配置上限”的较小值；第二行再和4KiB边界比较。硬件是比较器和选择器。

注意capped_beats单位是beat数量，ARLEN/burst_len编码为数量减1；两个变量不是同一个编码。

### 7.5 用0x0FF0、64 Byte算一遍

本例addr=0x0FF0，len=64，16 Byte/beat：

| 变量 | 本次计算 | 结果 |
|---|---|---:|
| addr_in_4k | 0x0FF0 | 4080 Byte |
| bytes_to_4k | 4096−4080 | 16 Byte |
| beats_to_4k | 16/16 | 1 beat |
| remaining_beats | 64/16 | 4 beat |
| max_burst_beats | min(4,16) | 4 beat |
| capped_beats | min(4,1) | 1 beat |
| burst_len/ARLEN | 1−1 | 0 |

第一笔只读0x0FF0～0x0FFF，完成后cur_addr=0x1000、剩余48 Byte；下次CALC得到3 beat，第二笔ARADDR=0x1000、ARLEN=2。

## 八、第5站下一状态组合逻辑（约第135～167行）

### 8.1 先说逻辑

本段读取当前state和输入/寄存器值，给state_nxt默认赋当前state，然后在满足条件时覆盖。没有满足跳转时保持当前状态。这是下一状态的组合计算，状态寄存器何时变由后面的always_ff决定。

~~~systemverilog
always_comb begin
    state_nxt = state;
    case (state)
        S_IDLE:
            if (cmd_valid)
                state_nxt = S_CALC_BURSTS;

        S_CALC_BURSTS:
            if (bytes_remaining == 24'd0)
                state_nxt = S_DONE;
            else
                state_nxt = S_SEND_AR;

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

        S_DONE: state_nxt = S_IDLE;
        default: state_nxt = S_IDLE;
    endcase
end
~~~

逐状态：

- IDLE中cmd_ready恒1，因此if(cmd_valid)等价于本沿命令握手。
- CALC中如bytes_remaining为0直接完成；因此零长度命令不产生AR/R传输。
- SEND_AR只有ARVALID和ARREADY同时为1才切到RECV。
- RECV只有RVALID、RREADY和RLAST同时为1才结束当前burst。RLAST=1但RREADY=0只是最后一项在等待。
- DONE下一沿回IDLE。异常状态default回IDLE不是对输入协议的全面错误恢复机制。

### 8.2 为什么最后一项不直接DONE

正常最后一项到达前，bytes_remaining为1～16 Byte，而不是0。状态组合逻辑在该握手沿依据的是沿前值，因此通常选择CALC；同一个沿的数据通路才把remaining更新为0。之后在CALC看到0，下一沿进入DONE。

源码包含RECV直接到DONE的分支，但正常非零长度、符合长度的最后beat握手前通常不走该分支；不能把“分支存在”说成正常最后一项通常立即DONE。在异常或不符合预期的R序列中remaining已饱和为0时，该分支可能被触发。

## 九、第6站状态寄存器（约第169～175行）

~~~systemverilog
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        state <= S_IDLE;
    else
        state <= state_nxt;
end
~~~

posedge clk表示时钟上升沿；negedge rst_n表示复位信号下降沿。rst_n拉低时异步复位state，不等下一个时钟；rst_n为1时，每个时钟上升沿采样state_nxt。<=是非阻塞赋值：本沿右值取沿前值，寄存器新值在沿后更新。

因此要区分state_nxt在沿前已计算、state在沿后才更新。数据通路另一个always_ff在同一个沿也看到沿前state和寄存器旧值。

## 十、第7站数据通路寄存器（约第179～247行）

### 10.1 复位

~~~systemverilog
if (!rst_n) begin
    cur_addr        <= '0;
    bytes_remaining <= 24'd0;
    burst_len       <= 8'd0;
    beat_cnt        <= 8'd0;
    total_beats     <= 24'd0;
    beats_done      <= 24'd0;
    tag_r           <= 4'd0;
    error_r         <= 1'b0;
end
~~~

'0表示按目标位宽全零；24'd0、8'd0等明确位宽和十进制数。清的是地址、计数、状态标识和错误寄存器，本模块没有数据FIFO需要清空。

### 10.2 IDLE：接收一整条命令

~~~systemverilog
if (cmd_valid) begin
    cur_addr        <= cmd_addr;
    bytes_remaining <= cmd_len;
    tag_r           <= cmd_tag;
    error_r         <= 1'b0;
    beats_done      <= 24'd0;
    total_beats     <= cmd_len[23:BEAT_SHIFT]
                     + (|cmd_len[BEAT_SHIFT-1:0] ? 24'd1 : 24'd0);
end
~~~

以地址0x1000、长度20 Byte、tag=3为例，握手沿后：cur_addr=0x1000，bytes_remaining=20，tag_r=3，beats_done=0，total_beats=2，error_r=0。

beat_cnt不是在此分支清零，而是在下一次CALC计算非零burst时清零。total_beats只是被保存，并未用于决定何时done。

### 10.3 CALC：保存当前burst的ARLEN

~~~systemverilog
if (bytes_remaining != 24'd0) begin
    burst_len <= capped_beats[7:0] - 8'd1;
    beat_cnt  <= 8'd0;
end
~~~

先前算出的capped_beats是beat数量，burst_len是数量−1。20 Byte时capped_beats=2，所以burst_len=1。状态沿后进入SEND_AR，此时ARLEN已经稳定。

MAX_BURST_LEN=256的极限若capped_beats=9'd256，低8位为0，8 bit减1环绕为8'hFF，对应AXI编码256 beat；不应仅看低8位0就误判该编码。默认上限仅16 beat。

### 10.4 SEND_AR：为什么数据通路没有寄存器更新

SEND_AR分支没有更新寄存器。AR字段由后面的assign持续从cur_addr、burst_len、tag_r等驱动；AW不是此读DMA所用通道。等待ARREADY时state保持，相关寄存器不变，所以有效AR信息保持。

### 10.5 RECV_DATA：仅在真实R握手时推进

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

条件为真实握手，而不是只看RVALID。

- beat_cnt加1：当前burst已接收项数。
- beats_done加1：整个命令已接收项数。
- cur_addr加16：推进一项总线宽度；AXI_ADDR_W'(…)为SystemVerilog指定位宽转换。
- bytes_remaining不少于16则减16，不足16则变0，避免无符号下溢。
- RRESP非OKAY时error_r置1，源码没有中止当前事务，也没有自动重试。

20 Byte例中D0握手：remaining 20→4、addr 0x1000→0x1010；D1握手：remaining 4→0、addr 0x1010→0x1020。第二项128 bit中只有4 Byte属于请求的长度；data_out没有keep信号，下游需保存原始长度并自行处理尾项。对于20 Byte命令，满宽读取也可能取得请求范围外的12 Byte；只应在允许额外读取的普通存储区域使用，不能无条件用于读有副作用的设备寄存器或不可访问区域。

接收响应error的同一沿也可以交付数据；done和error可以同时为1。新命令被接收才清error，不是DONE自动清。

## 十一、第8站AR输出（约第252～257行）

~~~systemverilog
assign m_axi_arid    = tag_r;
assign m_axi_araddr  = cur_addr;
assign m_axi_arlen   = burst_len;
assign m_axi_arsize  = axi_size_from_bytes(BYTES_PER_BEAT);
assign m_axi_arburst = AXI_BURST_INCR;
assign m_axi_arvalid = (state == S_SEND_AR);
~~~

默认20 Byte的第一笔：ARID=tag_r，ARADDR=0x1000，ARLEN=1，ARSIZE=4，ARBURST=2'b01；SEND_AR使ARVALID=1。编码4代表每拍16 Byte，ARLEN=1表示2拍。

axi_size_from_bytes在axi_types.sv中将16映射到3'b100。只在ARVALID有效时解释地址通道请求。若ARREADY未到，SEND_AR不改cur_addr和burst_len，因而请求字段保持。

## 十二、第9站R数据直通和反压（约第263～270行）

~~~systemverilog
assign m_axi_rready = (state == S_RECV_DATA) && data_ready;

assign data_valid = (state == S_RECV_DATA) && m_axi_rvalid;
assign data_out   = m_axi_rdata;
assign data_tag   = tag_r;

assign data_last = (state == S_RECV_DATA) && m_axi_rvalid
                 && m_axi_rlast
                 && (bytes_remaining <= BYTES_PER_BEAT[23:0]);
~~~

RECV状态中：RREADY=data_ready，data_valid=RVALID，data_out=RDATA。DMA不缓存数据；如果下游ready=0，RREADY就为0，符合握手规则的R发送方要保持有效项直到被接收。

m_axi_rlast表明当前burst末项；data_last还需要bytes_remaining<=16，表达此项也是整个命令末项。在RVALID=1、RLAST=1、remaining=4但data_ready=0时，data_last已为1，却还没有完成交付。只有data_valid && data_ready && data_last同沿才是最后一项实际交付。

模块假设对端正确给出RLAST；当前没有比较beat_cnt与burst_len来验证末项位置。RID也没有与tag_r核对。对端一直不给RLAST时，可能持续停在RECV，没有自动超时。

## 十三、第10站命令和状态输出（约第275～278行）

~~~systemverilog
assign cmd_ready = (state == S_IDLE);
assign busy      = (state != S_IDLE) && (state != S_DONE);
assign done      = (state == S_DONE);
assign error     = error_r;
~~~

| 当前状态 | cmd_ready | busy | done |
|---|---:|---:|---:|
| IDLE | 1 | 0 | 0 |
| CALC/SEND_AR/RECV | 0 | 1 | 0 |
| DONE | 0 | 0 | 1 |

DONE周期busy=0但cmd_ready=0，不能说busy=0就一定能接收命令。下一沿回IDLE后cmd_ready才为1。error独立保持，done=1时可能error=1。

## 十四、整条代码跑一次：0x1000读取20 Byte

假定一笔2 beat burst，RRESP=OKAY，第2项为RLAST；表为源码与输入假设推导，不是仿真波形。

| 沿 | 沿前状态与条件 | 本沿事件 | 沿后state、关键值 |
|---|---|---|---|
| C0 | IDLE，cmd_valid=cmd_ready=1，len=20 | 锁存命令 | CALC；addr=1000，remaining=20，total=2 |
| C1 | CALC，capped_beats=2 | 保存burst_len=1，beat_cnt=0 | SEND_AR |
| C2 | SEND_AR，ARVALID=1、ARREADY=0 | 等待 | 状态及AR字段保持 |
| C3 | SEND_AR，ARVALID=ARREADY=1 | AR握手 | RECV；本burst要2项 |
| C4 | RECV，D0有效、ready=1、RLAST=0 | 接收D0 | RECV；addr=1010，remaining=4，beat_cnt=1，beats_done=1 |
| C5 | RECV，D1有效、RLAST=1、下游ready=0 | 不握手 | 状态及计数保持；data_last=1但尚未交付 |
| C6 | RECV，D1仍有效、RLAST=1、ready=1 | 接收最后项 | CALC；addr=1020，remaining=0，beat_cnt=2，beats_done=2 |
| C7 | CALC，remaining=0 | 不发新AR | DONE；沿后done=1、busy=0 |
| C8 | DONE | 完成状态结束 | IDLE；沿后cmd_ready=1 |

地址表中1000、1010、1020均为十六进制；C6内部地址加16，不表示那额外12 Byte都属于请求的20 Byte。

## 十五、读源码的设计经验和边界

1. 对每个控制条件先问“是信号有效，还是valid&&ready真实握手”。
2. 分开命令长度Byte、beat数、ARLEN编码和时钟周期。
3. 将组合下一状态与时序寄存器更新分开，并在同一沿使用旧值判断。
4. 明确状态跳转到底依赖哪个变量，不因为计算了total_beats就推断它参与控制。
5. 复核最后一项等待时data_last和有效数据如何保持，不把last=1单独视为成功传输。
6. 检查RLAST/RID、RRESP、零长度、没有对端响应时的超时和尾项有效字节；指出源码行为及实现未覆盖的内容。
7. 区分理想/假设的外围SRAM适配和当前top.sv实际连接。done不是SRAM所有字节落存完成证明。
8. 参数化边界：默认128 bit时页起始距边界为256 beat，9 bit beats_to_4k可表示；64 bit时为512 beat，9 bit可能截断；8 bit使BEAT_SHIFT=0导致负位选问题。任意参数宽度或非对齐地址均不能据此断言可用。

本讲未修改RTL、未运行仿真或生成VCD。下游握手和R通道都遵循模块接口约定；公式与逐沿表均是对固定源码的静态推导，非实测。已讲解不代表用户已掌握；优先回答本模块问题，后续再衔接已有第08讲fetch后的Decode/Dispatch和Scoreboard。

来源：
- [axi_dma_rd.sv](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/rtl/bus/axi_dma_rd.sv)
- [axi_types.sv](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/rtl/bus/axi_types.sv)
- [top.sv](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/rtl/top.sv)
- [Arm AXI规范：A3事务结构与4KiB边界](https://developer.arm.com/-/media/Arm%20Developer%20Community/PDF/IHI0022H_amba_axi_protocol_spec.pdf)
