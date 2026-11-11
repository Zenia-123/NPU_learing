# axi_dma_wr：硬件结构、变量与源码顺序精读

日期：2026-11-11。按用户要求，先讲硬件/数据/控制/指令关系，再按程序文本的真实顺序，逐段先讲逻辑、再讲代码、变量和时序。已讲解不等于用户已经掌握。

源码：[rtl/bus/axi_dma_wr.sv](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/rtl/bus/axi_dma_wr.sv)，固定版本8216c22b762011aa20c05fc2768423fd12dda59d；相关包位于rtl/bus/axi_types.sv。此文件为SystemVerilog；作业分支的Verilog-2005约束不要求改写项目原码。

例子默认AXI_DATA_W=128 bit，AXI_ADDR_W=32 bit，MAX_BURST_LEN=16 beat，地址16 Byte对齐。默认一项beat=16 Byte。周期表是源码推导，未运行HDL仿真。

## 一、先讲硬件：这个模块做什么

axi_dma_wr把**上游提供的128 bit数据流**发送到外部AXI存储系统。控制器给它外部起始字节地址cmd_addr、总字节数cmd_len和tag；它拆分burst，先发AW，再发W，最后接收B。

用户可把整条写回任务理解为“告诉存储系统放哪里→提供数据→收取写响应”。以外部存储的视角称为写DMA；本模块本身没有本地SRAM源地址和读口，也不负责把8 bit SRAM数据拼成128 bit。

### 1.1 逻辑位置和三条信息流

~~~mermaid
flowchart TB
    DEC["微码译码与顶层命令翻译"] -->|"外部目标地址、长度、tag"| CTRL["写DMA控制器"]
    UP["内部数据源或宽度适配器"] -->|"data_in、data_valid"| DATA["写DMA数据通路"]
    CTRL -->|"AW地址与控制"| MEM["AXI互连与存储系统"]
    DATA -->|"W数据、WSTRB、WLAST"| MEM
    MEM -->|"BVALID、BRESP"| CTRL
    DATA -->|"data_ready"| UP
    CTRL -->|"burst控制"| DATA
~~~

图表示模块边界和理想数据来源，不表示当前top已经把SRAM接到写DMA。

- 指令/命令流：固定版本top中，译码输出的写目标、长度、flags经顶层翻译变为外部地址、长度和tag。flags[2:0]=0使用activation基址，=3或默认使用output基址；加上零扩展的dec_dma_wr_dst。flags[6:3]送tag。DMA内不解码128 bit微码。
- 数据流：上游data_in直接成为AXI WDATA，数据本身不在此模块内加FIFO。
- 控制流：DMA锁存命令，计算burst，驱动AW/W，控制ready和WLAST，等待B并维护done/error。
- 当前真实top.sv中data_valid固定0、data_in固定0，data_ready悬空；译码出的本地dec_dma_wr_src没有形成这条模块的SRAM读路径。非零命令若AW已握手，将等待有效写数据。模块error输出在该实例悬空，top的npu_error固定0；不能把模块内错误检测说成已在顶层汇总。命令ready虽接内部线，源码中没有直接反馈到decode，不能只据此推断完整调度行为。
- onnx_sim_top使用DMA Shim供C++测试平台处理，不能等同于AW/W/B硬件数据路径已被仿真验证。

### 1.2 AW/W/B各负责什么

| 通道 | 主要信息方向 | 功能 |
|---|---|---|
| AW写地址 | DMA→存储系统 | 起始地址、每项大小、beat数和ID |
| W写数据 | DMA→存储系统 | 128 bit数据、字节使能、当前burst末项 |
| B写响应 | 存储系统→DMA | 当前burst写事务响应状态 |

每个通道都有自己的valid/ready。实际传输发生在上升沿前两者同时为1时。协议允许AW与W独立；本模块选择**先AW握手，再W，等B后再发下个burst**，一次只允许一个未完成burst。B响应不能被扩展为对任意系统持久化的保证。

## 二、同一个例子贯穿各段代码

~~~text
cmd_addr = 0x1000       外部Byte地址，16 Byte对齐
cmd_len  = 20           有效Byte数
cmd_tag  = 3

D0：16 Byte有效，写0x1000～0x100F
D1：低4 Byte有效，写0x1010～0x1013
~~~

20 Byte需要ceil(20/16)=2个beat。假设没有碰到4KiB边界，两个beat属于同一个burst：

~~~text
AWADDR = 0x1000
AWLEN  = 1             beat数−1
AWSIZE = 4             2^4 = 16 Byte/beat
D0：WSTRB=16'hFFFF，WLAST=0
D1：WSTRB=16'h000F，WLAST=1
~~~

16'h000F的低4位为1，每位对应WDATA的一个8 bit字节lane。只在对应WVALID有效时解释WLAST/WSTRB。

## 三、端口的方向、宽度、单位和作用

方向均相对于axi_dma_wr。AXI_ID_W从axi_types_pkg导入，固定包中为4 bit。

### 3.1 时钟和命令

| 信号 | 方向/默认宽度 | 作用与单位 |
|---|---|---|
| clk | 输入1 bit | 寄存器上升沿时钟 |
| rst_n | 输入1 bit | 低有效异步复位 |
| cmd_valid | 输入1 bit | 命令有效 |
| cmd_ready | 输出1 bit | IDLE时为1，可接收命令 |
| cmd_addr | 输入32 bit | 外部目标起始Byte地址 |
| cmd_len | 输入24 bit | 整条命令的有效Byte数 |
| cmd_tag | 输入4 bit | 命令标识，锁存后形成AWID |

cmd_valid && cmd_ready在上升沿成立才接收命令。源码在IDLE只判断cmd_valid，因为本状态cmd_ready恒1。模块不排队；上游必须保持命令到握手。若cmd_valid一直保持1，DONE回到IDLE后可能再次接收相同命令。

### 3.2 AW通道

| 信号 | 方向/默认宽度 | 作用 |
|---|---|---|
| m_axi_awid | 输出4 bit | tag_r，当前burst的ID |
| m_axi_awaddr | 输出32 bit | 当前burst起始外部Byte地址 |
| m_axi_awlen | 输出8 bit | burst beat数减1 |
| m_axi_awsize | 输出3 bit | log2(每beat的Byte数)，默认4 |
| m_axi_awburst | 输出2 bit | 默认INCR=2'b01，地址递增 |
| m_axi_awvalid | 输出1 bit | AW字段有效，SEND_AW时为1 |
| m_axi_awready | 输入1 bit | 对端可以接收AW |

### 3.3 上游数据与W通道

| 信号 | 方向/默认宽度 | 作用 |
|---|---|---|
| data_in | 输入128 bit | 上游提供的整项写数据 |
| data_valid | 输入1 bit | 上游数据有效 |
| data_ready | 输出1 bit | 本DMA可以在当前沿接收该项 |
| data_last | 输入1 bit | 端口已声明，但本模块未使用 |
| m_axi_wdata | 输出128 bit | 直接等于data_in |
| m_axi_wstrb | 输出16 bit | 每位控制WDATA一个Byte lane |
| m_axi_wlast | 输出1 bit | 当前burst最后一项的属性 |
| m_axi_wvalid | 输出1 bit | 当前W项有效 |
| m_axi_wready | 输入1 bit | 存储系统能接收W项 |

在SEND_WDATA中，data_valid&&data_ready与m_axi_wvalid&&m_axi_wready在同一个沿同时发生；这个DMA没有内部数据FIFO。上游必须在valid=1、ready=0时保持数据及valid，直到握手。

### 3.4 B通道与状态

| 信号 | 方向/默认宽度 | 作用 |
|---|---|---|
| m_axi_bid | 输入4 bit | 响应ID；源码未比较tag_r |
| m_axi_bresp | 输入2 bit | 当前burst的写响应码 |
| m_axi_bvalid | 输入1 bit | B响应有效 |
| m_axi_bready | 输出1 bit | WAIT_BRESP期间可接收响应 |
| busy | 输出1 bit | 非IDLE和非DONE时为1 |
| done | 输出1 bit | state= S_DONE时为1 |
| error | 输出1 bit | error_r：记录本命令是否出现过非OKAY B响应 |

done表示控制流程完成；error=1表明至少一个已接收响应非OKAY，done和error可同时为1。新命令被接收时error清零。

## 四、内部变量与硬件意义

### 4.1 参数和状态寄存器

| 变量 | 宽度/单位 | 意义、更新时机 |
|---|---|---|
| AXI_DATA_W | 参数，128 bit | 总线数据宽度 |
| AXI_ADDR_W | 参数，32 bit | 外部地址宽度 |
| MAX_BURST_LEN | 参数，默认16 beat | 每burst上限 |
| BYTES_PER_BEAT | 常数，16 Byte/beat | AXI_DATA_W/8 |
| BEAT_SHIFT | 常数，4 | clog2(16)，用于位切片换算 |
| state | 3 bit | 当前状态，时钟沿更新 |
| state_nxt | 3 bit | 当前组合条件下的下一状态 |
| cur_addr | 32 bit，Byte地址 | cmd握手时装载，W握手时每项加16 |
| bytes_remaining | 24 bit，Byte | cmd握手时装载，W握手时减16或饱和到0 |
| burst_len | 8 bit，beat数−1 | CALC时保存AWLEN编码 |
| beat_cnt | 8 bit，beat计数 | 每个非零burst的CALC置0，每次W握手加1 |
| tag_r | 4 bit | 锁存cmd_tag并驱动AWID |
| error_r | 1 bit | 复位或新命令清0；B握手且非OKAY置1并保持 |

cur_addr在AW阶段表示当前burst首地址；在后续W阶段每次真实握手都会加16，故并非burst期间保持不动。AWVALID在W阶段为0，不表示它在每次W握手时发出新地址。

### 4.2 burst计算和尾掩码组合量

| 变量 | 宽度/单位 | 作用 |
|---|---|---|
| remaining_beats | 24 bit，beat | ceil(bytes_remaining/16) |
| addr_in_4k | 12 bit，Byte偏移 | cur_addr低12位 |
| bytes_to_4k | 13 bit，Byte | 距下一4KiB边界的字节数 |
| beats_to_4k | 9 bit，beat | 默认宽度和对齐假设下，边界前可放beat数 |
| max_burst_beats | 9 bit，beat | 剩余beat与MAX_BURST_LEN较小者 |
| capped_beats | 9 bit，beat | 再限制不跨4KiB边界，最终beat数 |
| full_strb | 16 bit | 全1写掩码 |
| last_strb | 16 bit | 假定最后一项时，根据尾部Byte生成的掩码 |
| tail_bytes_raw | 4 bit | bytes_remaining低4位；最后一项时为1～15的尾数，0代表满16 Byte |
| is_last_beat_of_xfer | 1 bit | 当前是burst末项且整条命令剩余量≤16 Byte |

last_strb可以在非最后项时已经计算成000F；只有is_last_beat_of_xfer=1时才被选到WSTRB。别把组合量理解成时钟寄存器。

## 五、源码第1段：模块声明和包（第11～72行）

### 5.1 逻辑

模块定义参数和六类接口：命令、AW、W、B、内部数据、状态。ID位宽和常量来自包。

### 5.2 代码

~~~systemverilog
module axi_dma_wr
    import axi_types_pkg::*;
#(
    parameter int AXI_DATA_W    = 128,
    parameter int AXI_ADDR_W    = 32,
    parameter int MAX_BURST_LEN = 16
) (
    // 完整端口列表见第三节
);
~~~

import让本模块可使用axi_types_pkg中的AXI_ID_W、AXI_BURST_INCR、AXI_RESP_OKAY和axi_size_from_bytes，不会实例化一个独立模块。实际包路径是rtl/bus/axi_types.sv。logic [AXI_DATA_W/8-1:0]在默认参数下为logic [15:0]，也就是16个字节写使能。

## 六、第2段：派生常数（第77～78行）

### 6.1 逻辑

总线128 bit需要换算成每项16 Byte，再得到log2(16)=4以便进行除以16的位切片。

~~~systemverilog
localparam int BYTES_PER_BEAT = AXI_DATA_W / 8;
localparam int BEAT_SHIFT     = $clog2(BYTES_PER_BEAT);
~~~

localparam是设计期派生常数，不是每拍变化的寄存器。默认BYTES_PER_BEAT=16、BEAT_SHIFT=4。

## 七、第3段：状态和内部寄存器声明（第83～102行）

### 7.1 逻辑

六个状态分别承担接收命令、计算长度、发地址、发数据、等响应和报告完成。state是当前状态寄存器，state_nxt是组合下一状态。其他寄存器保存当前地址、剩余长度、burst配置、进度、tag和错误。

### 7.2 代码

~~~systemverilog
typedef enum logic [2:0] {
    S_IDLE, S_CALC_BURSTS, S_SEND_AW,
    S_SEND_WDATA, S_WAIT_BRESP, S_DONE
} state_t;

state_t state, state_nxt;
logic [AXI_ADDR_W-1:0] cur_addr;
logic [23:0] bytes_remaining;
logic [7:0] burst_len, beat_cnt;
logic [3:0] tag_r;
logic error_r;
~~~

这段是按原声明合并排版的等义摘录；实际文件将burst_len和beat_cnt分别声明。枚举类型用3 bit表示6个命名状态，不是6个时钟进程。

## 八、第4段：如何确定下一笔burst（第107～127行）

### 8.1 逻辑

对默认对齐配置：

~~~text
burst实际beat数 = min(
  ceil(剩余Byte / 16),
  MAX_BURST_LEN,
  下个4KiB边界之前可用beat数
)
~~~

一个AXI burst不跨4KiB边界，整个命令可以通过多笔burst跨越。计算组合量，不是每个变量各等一个时钟。

### 8.2 代码与逐项解释

~~~systemverilog
assign remaining_beats = bytes_remaining[23:BEAT_SHIFT]
                       + (|bytes_remaining[BEAT_SHIFT-1:0]
                          ? 24'd1 : 24'd0);
assign addr_in_4k = cur_addr[11:0];
wire [12:0] bytes_to_4k = 13'd4096 - {1'b0, addr_in_4k};
assign beats_to_4k = bytes_to_4k[12:BEAT_SHIFT]
                    + (|bytes_to_4k[BEAT_SHIFT-1:0]
                       ? 9'd1 : 9'd0);
assign max_burst_beats = (remaining_beats < MAX_BURST_LEN[8:0])
                         ? remaining_beats[8:0] : MAX_BURST_LEN[8:0];
assign capped_beats = (max_burst_beats < beats_to_4k)
                      ? max_burst_beats : beats_to_4k;
~~~

BEAT_SHIFT=4时，[23:4]是除16向下取整，[3:0]是余数；归约或前缀“|”表示低4位任一位为1。20 Byte→商1、余数4→remaining_beats=2。三目运算条件真取?后、假取:后。cur_addr低12位是4KiB内的Byte偏移；{1'b0, addr_in_4k}把12 bit扩到13 bit以便表示4096。

0x1000、20 Byte例：remaining_beats=2、bytes_to_4k=4096、beats_to_4k=256，和16取最小得到capped_beats=2，随后burst_len=1。

### 8.3 另一个例子：0x0FF0、20 Byte

| 阶段 | 当前地址 | 剩余Byte | 到边界 | capped_beats | AWLEN |
|---|---|---:|---:|---:|---:|
| burst 0 | 0x0FF0 | 20 | 16 Byte | 1 | 0 |
| burst 1 | 0x1000 | 4 | 4096 Byte | 1 | 0 |

第一笔仅1 beat并带WLAST，先收一个B；第二笔也1 beat并带WLAST且尾部WSTRB=000F，再收B后才结束整条命令。

## 九、第5段：生成WSTRB与“整个命令末项”（第134～161行）

### 9.1 逻辑

每个WSTRB bit对应WDATA的一个Byte。完整项写16个Byte；只有整条命令最后一项不足16 Byte时，选择低N位为1的尾掩码。某burst的WLAST并不自动意味着整个命令完成。

### 9.2 代码

~~~systemverilog
assign full_strb = {(AXI_DATA_W/8){1'b1}};
assign tail_bytes_raw = bytes_remaining[BEAT_SHIFT-1:0];

always_comb begin
    if (tail_bytes_raw == '0) begin
        last_strb = full_strb;
    end else begin
        last_strb = '0;
        for (int i = 0; i < BYTES_PER_BEAT; i++) begin
            if (i[BEAT_SHIFT-1:0] < tail_bytes_raw)
                last_strb[i] = 1'b1;
        end
    end
end

assign is_last_beat_of_xfer = (beat_cnt == burst_len)
                              && (bytes_remaining <= BYTES_PER_BEAT[23:0]);
~~~

{16{1'b1}}是复制拼接，得到16个1，即FFFF。20 Byte时低4位尾数为4，因此组合last_strb=000F；源码后面的多路选择只在真正整个命令末项时使用它。16 Byte整除时尾数为0，last_strb=FFFF。组合for用于生成多位组合判断，不代表顺次经过16拍。

两个条件说明：beat_cnt==burst_len是当前burst末项；bytes_remaining<=16说明整条命令也只剩最后一项。两者一起才is_last_beat_of_xfer=1。

默认0x1000、20 Byte：

| W项 | 沿前beat_cnt | burst_len | bytes_remaining | is_last_beat_of_xfer | WSTRB |
|---|---:|---:|---:|---:|---|
| D0 | 0 | 1 | 20 | 0 | FFFF |
| D1 | 1 | 1 | 4 | 1 | 000F |

## 十、第6段：FSM组合下一状态（第166～202行）

### 10.1 逻辑

默认保持当前state；只在命令/AW/W末项/B真正握手时推进。先读这个状态表，再看代码。

| 状态 | 作用 | 离开条件 |
|---|---|---|
| S_IDLE | 可接收命令 | cmd握手 |
| S_CALC_BURSTS | 形成并锁存长度 | 剩0→DONE，否则→SEND_AW |
| S_SEND_AW | 发AW、等待接收 | AWVALID&&AWREADY |
| S_SEND_WDATA | 发W | WVALID&&WREADY&&WLAST |
| S_WAIT_BRESP | 接收B | BVALID&&BREADY；剩0→DONE，否则→CALC |
| S_DONE | done=1 | 下一沿回IDLE |

### 10.2 代码

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
                state_nxt = S_SEND_AW;
        S_SEND_AW:
            if (m_axi_awvalid && m_axi_awready)
                state_nxt = S_SEND_WDATA;
        S_SEND_WDATA:
            if (m_axi_wvalid && m_axi_wready && m_axi_wlast)
                state_nxt = S_WAIT_BRESP;
        S_WAIT_BRESP:
            if (m_axi_bvalid && m_axi_bready) begin
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

state_nxt=state默认保持。S_IDLE时cmd_ready=1，检查cmd_valid等价于命令握手。WLAST=1但WREADY=0不能前进。最后W握手时沿后bytes_remaining已经更新；B响应发生在后续沿，WAIT_BRESP判断时看到更新后的值，故最后B握手沿后可直接DONE。

零长度命令走IDLE→CALC→DONE，无AW/W/B。

## 十一、第7段：状态寄存器（第204～209行）

### 11.1 逻辑

组合状态选择不会立即改变状态；上升沿保存state_nxt。rst_n下降沿异步复位state。

~~~systemverilog
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        state <= S_IDLE;
    else
        state <= state_nxt;
end
~~~

非阻塞赋值<=在同一沿读取沿前值、沿后更新。后面的数据通路always_ff与此并发，不是文件前面的块先更新、后面的块立刻看到新state。

## 十二、第8段：数据通路寄存器（第214～279行）

### 12.1 逻辑

复位清进度；IDLE锁存命令；CALC保存当前burst；SEND_AW不更新数据寄存器；每次实际W握手推进；等待B时锁存错误。分开看每个状态。

### 12.2 复位和IDLE

~~~systemverilog
if (!rst_n) begin
    cur_addr        <= '0;
    bytes_remaining <= 24'd0;
    burst_len       <= 8'd0;
    beat_cnt        <= 8'd0;
    tag_r           <= 4'd0;
    error_r         <= 1'b0;
end
~~~

IDLE分支：

~~~systemverilog
if (cmd_valid) begin
    cur_addr        <= cmd_addr;
    bytes_remaining <= cmd_len;
    tag_r           <= cmd_tag;
    error_r         <= 1'b0;
end
~~~

本例命令握手后cur_addr=0x1000、remaining=20、tag_r=3、error=0。

### 12.3 CALC与SEND_AW

~~~systemverilog
if (bytes_remaining != 24'd0) begin
    burst_len <= capped_beats[7:0] - 8'd1;
    beat_cnt  <= 8'd0;
end
~~~

capped_beats为真实项数2，burst_len保存1，beat_cnt清0。SEND_AW分支不更新这些寄存器，故等待AWREADY期间AW字段保持。

MAX_BURST_LEN=256时，9'd256取低8位为0，8 bit减1得到FF，恰是256 beat的AWLEN编码；默认上限16，不代表所有其他参数组合正确。

### 12.4 SEND_WDATA：按W握手推进

~~~systemverilog
if (m_axi_wvalid && m_axi_wready) begin
    beat_cnt <= beat_cnt + 8'd1;
    cur_addr <= cur_addr + AXI_ADDR_W'(BYTES_PER_BEAT);
    if (bytes_remaining >= BYTES_PER_BEAT[23:0])
        bytes_remaining <= bytes_remaining - BYTES_PER_BEAT[23:0];
    else
        bytes_remaining <= 24'd0;
end
~~~

D0握手：cnt 0→1，addr 1000→1010，remaining 20→4；D1握手：cnt 1→2，addr 1010→1020，remaining 4→0。最后只写4 Byte由WSTRB决定；内部地址加16不等于其余12个Byte被写入。

AXI_ADDR_W'(BYTES_PER_BEAT)是SystemVerilog位宽转换。当前WREADY=0时计数器、地址、剩余量均保持；写数据稳定需要上游配合。

### 12.5 WAIT_BRESP：记录错误

~~~systemverilog
if (m_axi_bvalid && m_axi_bready) begin
    if (m_axi_bresp != AXI_RESP_OKAY)
        error_r <= 1'b1;
end
~~~

只在B握手时检查BRESP；遇非OKAY置粘滞错误，但源码不会立即终止后续burst。错误可与done同周期为1，新命令接收时清除。BID输入未核验。

## 十三、第9段：AW通道输出（第284～289行）

### 13.1 逻辑

由tag_r、cur_addr、burst_len驱动当前burst请求；state为SEND_AW时将其标记有效。等待AWREADY时寄存器保持。

~~~systemverilog
assign m_axi_awid    = tag_r;
assign m_axi_awaddr  = cur_addr;
assign m_axi_awlen   = burst_len;
assign m_axi_awsize  = axi_size_from_bytes(BYTES_PER_BEAT);
assign m_axi_awburst = AXI_BURST_INCR;
assign m_axi_awvalid = (state == S_SEND_AW);
~~~

20 Byte例：AWID=3、AWADDR=1000、AWLEN=1、AWSIZE=4、AWBURST=INCR。W阶段cur_addr递增时AWVALID=0，所以不能当作每项都重新发送了AW。

## 十四、第10段：W通道及反压（第296～302行）

### 14.1 逻辑

数据直通，无FIFO；WSTRB由整条命令末项选择；WLAST由当前burst计数比较；状态和上游valid共同决定WVALID。外部WREADY向上游传播为data_ready。

### 14.2 代码

~~~systemverilog
assign m_axi_wdata  = data_in;
assign m_axi_wstrb  = is_last_beat_of_xfer ? last_strb : full_strb;
assign m_axi_wlast  = (beat_cnt == burst_len);
assign m_axi_wvalid = (state == S_SEND_WDATA) && data_valid;
assign data_ready   = (state == S_SEND_WDATA) && m_axi_wready;
~~~

SEND_WDATA中，上游data_valid&&data_ready与WVALID&&WREADY在同一沿相等。WREADY=0时data_ready=0；上游必须保持data_valid和data_in。控制寄存器不推进，所以WLAST/WSTRB保持，WDATA稳定依赖上游。跨burst在WAIT_BRESP、CALC、SEND_AW期间data_ready均为0，已准备下一个数据项的上游仍需保持。

WSTRB和WLAST是组合信号，空闲时也可能出现1；只有WVALID有效时才作为当前W项的属性。data_last输入没有用于生成WLAST或检查长度。

## 十五、第11段：B和状态输出（第307～315行）

~~~systemverilog
assign m_axi_bready = (state == S_WAIT_BRESP);
assign cmd_ready   = (state == S_IDLE);
assign busy        = (state != S_IDLE) && (state != S_DONE);
assign done        = (state == S_DONE);
assign error       = error_r;
~~~

| 状态 | cmd_ready | busy | done | bready |
|---|---:|---:|---:|---:|
| IDLE | 1 | 0 | 0 | 0 |
| CALC/AW/W | 0 | 1 | 0 | 0 |
| WAIT_BRESP | 0 | 1 | 0 | 1 |
| DONE | 0 | 0 | 1 | 0 |

DONE期间busy=0但cmd_ready=0，下一沿回IDLE才可接收新命令。BVALID&&BREADY握手后才是响应被DMA接收；错误由error_r同时反映。

## 十六、把20 Byte贯穿全模块：沿前/沿后

假设地址1000、长度20、上游D0/D1有效、B响应OKAY；C2人为加入AW等待，C5加入W反压，C7加入B等待。

| 上升沿 | 沿前条件 | 本沿事件 | 沿后状态与变量 |
|---|---|---|---|
| C0 | IDLE，cmd_valid&&cmd_ready | 锁存命令 | CALC，addr=1000、remaining=20 |
| C1 | CALC，capped=2 | 保存长度，beat_cnt=0 | SEND_AW，burst_len=1 |
| C2 | SEND_AW，AWVALID=1/AWREADY=0 | 等待 | 保持SEND_AW及AW字段 |
| C3 | SEND_AW，AWVALID&&AWREADY | 接收地址 | SEND_WDATA |
| C4 | D0有效、WREADY=1，WLAST=0/WSTRB=FFFF | W握手 | SEND_WDATA；cnt=1、addr=1010、remaining=4 |
| C5 | D1有效、WREADY=0，WLAST=1/WSTRB=000F | 未握手 | 保持D1和状态、进度 |
| C6 | D1仍有效、WREADY=1，WLAST=1 | 最后W握手 | WAIT_BRESP；cnt=2、addr=1020、remaining=0 |
| C7 | BREADY=1、BVALID=0 | 等待B | WAIT_BRESP |
| C8 | BREADY&&BVALID，BRESP=OKAY | 接收B | DONE；done=1、busy=0、cmd_ready=0 |
| C9 | DONE | 结束状态 | IDLE；cmd_ready=1 |

全部地址按十六进制书写。C5中WSTRB/WLAST虽有效但未被接收；C6数据完成后仍须等待B；C8为错误响应时沿后done=1且error=1。加入的等待是示例，不是固定延迟。

## 十七、范围与设计经验

- WLAST表示burst末项；只有同时满足整条命令末项和尾数条件才使用last_strb。跨4KiB的0x0FF0、20 Byte会各有一次WLAST和B。
- 一个burst在途；每次等待B，不能借多个未完成burst隐藏全部存储/响应延迟。
- 无本地源地址/数据FIFO；上游需保证完整数据及握手稳定，当前top数据输入仍是占位。
- BID未核验、data_last未使用；错误粘滞并继续后续burst，无自动超时。
- 教学例限定16 Byte对齐。模块没有完整实现一般非对齐首尾lane与旋转处理；不能凭注释断言任意地址可用。
- 参数化存在边界：beats_to_4k只有9 bit，默认128 bit页首为256 beat可表示；64 bit页首为512会截断；8 bit时BEAT_SHIFT=0存在负位选；非2次幂Byte宽度的切片/size编码不能简单保证正确。
- 应区分源码推导、真实接线和仿真结果；本讲没有运行仿真、未生成VCD或修改RTL。

源码与资料：[axi_dma_wr.sv](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/rtl/bus/axi_dma_wr.sv)、[axi_types.sv](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/rtl/bus/axi_types.sv)、[top.sv](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/rtl/top.sv)、[Arm AXI规范WSTRB](https://documentation-service.arm.com/static/651c285c15583d1bff972f94)。

当前停点：用户主动要求精读写DMA，优先回答具体问题，不假设已掌握；其他对话的第08讲fetch进度保持，后续如用户要求下一讲再接Decode/Dispatch与Scoreboard。作业实验由用户亲自操作。
