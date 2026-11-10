# 第07讲（下）：AXI写DMA的硬件结构、数据流与逐拍执行

2026-11-10。源码：[axi_dma_wr.sv，固定版本8216c22](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/rtl/bus/axi_dma_wr.sv)。

上一节补充了AXI基础。本讲从写DMA的硬件结构讲起，再分析信号含义与单位、数据和控制流、源代码及具体时序。已讲解不等于已掌握；优先回应用户的具体疑问。

## 1. 写DMA在系统中做什么

上层控制器提交命令：外部目标字节地址、写入字节数、tag。写DMA把命令拆成AXI写burst，发送写地址AW和写数据W，并接收每个burst的写响应B。这里“写”以外部存储为视角：内部产生的数据流向外部地址。

一条完整系统中的预期路径是：本地SRAM→数据打包/缓冲→写DMA输入流→AXI互连/存储控制器→外部存储。源地址、SRAM读口、8 bit到128 bit的打包、局部缓冲和有效字节管理都不由axi_dma_wr本身提供。

## 2. 硬件结构

~~~mermaid
flowchart TB
    CMD["命令：目标地址、长度、tag"] --> FSM["状态机与进度寄存器"]
    UP["上游数据源"] -->|"data_in、data_valid"| W["W数据直通及WSTRB生成"]
    W -->|"data_ready"| UP
    FSM -->|"burst长度、末拍与字节掩码"| W
    FSM -->|"AW地址与控制"| MEM["AXI互连与存储控制器"]
    W -->|"W数据、WSTRB、WLAST"| MEM
    MEM -->|"BVALID、BRESP、BID"| FSM
~~~

主要硬件：

- FSM状态寄存器与下一状态组合逻辑，六个状态。
- cur_addr、bytes_remaining、burst_len、beat_cnt、tag_r、error_r寄存器。
- burst拍数与4KiB边界的比较/选择逻辑。
- WSTRB尾字节生成的组合逻辑。
- WDATA的直接连线，没有内部数据FIFO。

128 bit打包器属于可能的外围实现，不是这个模块内现成的硬件。

## 3. 先分清协议允许和本模块选择

AXI的AW和W为独立通道，不要求AW握手一定先于W握手。写响应依赖写地址和最后一项写数据被接收。

本实现做了更简单的安排：先完成AW，再发送W，接收最后一项W后等待B。一个burst的B完成后才会发下一个burst。因而一次只有一个未完成burst，不会用多个在途burst隐藏B响应等待时间。

每个通道的传输条件仍是对应上升沿前valid与ready均为1。

## 4. 默认参数与单位

| 参数 | 默认值 | 意义 |
|---|---:|---|
| AXI_DATA_W | 128 bit | WDATA及data_in宽度 |
| AXI_ADDR_W | 32 bit | 外部字节地址宽度 |
| MAX_BURST_LEN | 16 beat | 一个burst最多的数据项数 |
| BYTES_PER_BEAT | 16 Byte | AXI_DATA_W/8 |
| BEAT_SHIFT | 4 | log2(16)，用于按16 Byte换算 |

一次满宽beat是16 Byte，不保证只占一个时钟周期；若ready为0就可能等待多个周期。

以下算例限定默认128 bit、起始地址16 Byte对齐。不能由端口注释byte-aligned推断本模块已完整处理任意非对齐地址的lane与数据重排。

## 5. 端口表：方向均相对于写DMA

### 5.1 命令接口

| 端口 | 位宽/方向 | 含义 |
|---|---|---|
| cmd_valid | 1，输入 | 上游有有效命令 |
| cmd_ready | 1，输出 | 在IDLE可接收命令 |
| cmd_addr | 32，输入 | 外部目标起始字节地址 |
| cmd_len | 24，输入 | 整个DMA命令的Byte数 |
| cmd_tag | 4，输入 | 锁存后用于AWID的任务标识 |

IDLE里cmd_ready=1，因此源码中IDLE且cmd_valid时接收等价于命令握手。该模块没有命令队列，发送方应在ready为0时保持有效命令至握手。

### 5.2 AW地址通道

| 端口 | 位宽/方向 | 含义 |
|---|---|---|
| m_axi_awid | 4，输出 | 当前tag_r |
| m_axi_awaddr | 32，输出 | 当前burst首字节地址 |
| m_axi_awlen | 8，输出 | 当前burst的beat数减1 |
| m_axi_awsize | 3，输出 | 默认4，即每beat 2^4=16 Byte |
| m_axi_awburst | 2，输出 | 固定INCR递增 |
| m_axi_awvalid | 1，输出 | AW内容有效 |
| m_axi_awready | 1，输入 | 从设备能接收AW |

AWVALID && AWREADY完成一个burst的写地址请求。等待AWREADY期间AWVALID及地址控制字段应保持。

### 5.3 W数据、上游输入与B响应

| 端口 | 位宽/方向 | 含义 |
|---|---|---|
| data_in | 128，输入 | 上游提供的一项数据 |
| data_valid | 1，输入 | 上游当前数据有效 |
| data_ready | 1，输出 | 当前能够接收上游数据 |
| data_last | 1，输入 | 声明了该输入，但本实现没有使用 |
| m_axi_wdata | 128，输出 | 直接等于data_in |
| m_axi_wstrb | 16，输出 | 每位对应一个8 bit字节通道的写使能 |
| m_axi_wlast | 1，输出 | 当前burst最后一项的标志 |
| m_axi_wvalid | 1，输出 | 发送的W项有效 |
| m_axi_wready | 1，输入 | 从设备能接收W项 |
| m_axi_bid | 4，输入 | B响应ID，本实现未检查 |
| m_axi_bresp | 2，输入 | B响应码 |
| m_axi_bvalid | 1，输入 | 从设备给出有效响应 |
| m_axi_bready | 1，输出 | 本DMA能接收B响应 |
| busy | 1，输出 | 任务执行中；DONE和IDLE时为0 |
| done | 1，输出 | 位于DONE状态时为1，下一沿回IDLE |
| error | 1，输出 | 任一响应非OKAY时置位并保持到下一命令 |

data_last虽然是输入，源码没有用它控制WLAST，也没有核验它。W/B字段在对应valid无效时不代表一笔有效传输。特别是WLAST组合表达式在其他状态也可能为1，必须结合WVALID解释。

## 6. 内部变量

| 变量 | 位宽/单位 | 含义 |
|---|---|---|
| state/state_nxt | 3 bit | 当前/下一FSM状态 |
| cur_addr | 32 bit，字节地址 | 当前进度，W握手时加16 |
| bytes_remaining | 24 bit，Byte | 本命令剩余有效字节数 |
| burst_len | 8 bit，beat数减1 | 当前burst经AWLEN输出的长度 |
| beat_cnt | 8 bit，beat索引/数量 | 当前burst已完成的W握手数，首项前为0 |
| tag_r | 4 bit | 已锁存的命令tag |
| error_r | 1 bit | B响应错误粘滞位 |
| remaining_beats | 24 bit，beat | 剩余Byte向上取整折算成beat |
| addr_in_4k | 12 bit，Byte偏移 | cur_addr在4KiB地址区间内的偏移 |
| bytes_to_4k | 13 bit，Byte | 到下一4KiB边界的字节数 |
| beats_to_4k | 9 bit，beat | 默认配置下到边界允许的拍数 |
| max_burst_beats | 9 bit，beat | 剩余拍数与MAX_BURST_LEN的较小值 |
| capped_beats | 9 bit，beat | 再受到4KiB边界限制后的拍数 |
| full_strb/last_strb | 各16 bit | 整拍字节使能/整个命令尾拍字节使能 |
| tail_bytes_raw | 4 bit，Byte数 | bytes_remaining低4位；非零时为尾部有效字节数 |
| is_last_beat_of_xfer | 1 bit | 当前项同时是burst末项和整个命令末项 |

## 7. 数据流、控制流和反压

源代码：

~~~systemverilog
assign m_axi_wdata  = data_in;
assign m_axi_wvalid = (state == S_SEND_WDATA) && data_valid;
assign data_ready   = (state == S_SEND_WDATA) && m_axi_wready;
~~~

数据流：上游提供data_in，经组合连线直接成为WDATA；WSTRB与WLAST由DMA自己的控制信息产生。

控制流：只有SEND_WDATA阶段且上游data_valid有效时WVALID为1。WREADY决定上游data_ready。处于该状态时：

~~~text
上游 data_valid && data_ready
      与
AXI WVALID && WREADY
在同一个上升沿同时成立
~~~

DMA没有数据FIFO。如果WREADY=0，那么data_ready=0；上游必须保持data_valid=1和data_in稳定，直到握手。DMA内部计数器在等待期间不动，因此由计数产生的WSTRB/WLAST也保持；WDATA能否稳定仍依赖上游遵守接口约定。

仅当WVALID && WREADY时beat_cnt加1、cur_addr加16、bytes_remaining减16并饱和到0。没有握手就不能推进。这是数据被实际接收的判断。

## 8. WSTRB：为什么20 Byte需要两项而第二项只写4 Byte

WSTRB每bit对应WDATA的一个Byte通道：

~~~text
WSTRB[0]  对应 WDATA[7:0]
WSTRB[1]  对应 WDATA[15:8]
...
WSTRB[15] 对应 WDATA[127:120]
~~~

WSTRB位为1表示相应字节通道有效并允许写入；0表示该字节不写。它控制字节，不是控制单个数据bit。

例子：cmd_addr=0x1000，cmd_len=20 Byte，默认128 bit总线。需要ceil(20/16)=2项：

| 当前项 | W握手前剩余量 | WSTRB | WLAST | 有效Byte及地址 |
|---|---:|---|---:|---|
| D0，beat_cnt=0 | 20 | 16'hFFFF | 0 | 16 Byte，0x1000～0x100F |
| D1，beat_cnt=1 | 4 | 16'h000F | 1 | 低4 Byte，0x1010～0x1013 |

D1的低4字节通道有写使能，其余12个lane的WSTRB为0，所以不会覆盖对应地址。若实际接口的数据字节排列不同，上游必须按接口约定准备好对应lane。

D0之前last_strb可能已经组合算出000F，但当前项不是整个命令的最后一项，输出选择full_strb=FFFF。

### 8.1 原码如何产生末拍写使能

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
~~~

默认BEAT_SHIFT=4。若剩余4 Byte，tail_bytes_raw=4，循环将第0、1、2、3位设1，其余位为0。for循环在这里描述组合硬件，对每一位生成判断，不表示要运行16个时钟周期。

如果最后正好剩16 Byte，低4位为0，last_strb=FFFF，表示整拍有效。

~~~systemverilog
assign is_last_beat_of_xfer = (beat_cnt == burst_len)
                              && (bytes_remaining <= BYTES_PER_BEAT[23:0]);
assign m_axi_wstrb = is_last_beat_of_xfer ? last_strb : full_strb;
~~~

两个条件必须同时满足：当前是burst末项，并且整个DMA剩余量至多一拍。它把“burst结束”和“整个命令最后一项”区别开。

例如共280 Byte、默认最大16 beat：第一个burst为16 beat；第二个burst为2 beat。第一个burst末项WLAST=1，但整个命令还未结束，WSTRB仍为FFFF；第二个burst最后一项只剩8 Byte，WSTRB=00FF。

## 9. WLAST：按计数生成

~~~systemverilog
assign m_axi_wlast = (beat_cnt == burst_len);
~~~

burst_len是本burst拍数减1，beat_cnt从0开始。两项burst的计数和WLAST：

| 本项 | 握手前beat_cnt | burst_len | WLAST |
|---|---:|---:|---:|
| D0 | 0 | 1 | 0 |
| D1 | 1 | 1 | 1 |

D1若被反压，beat_cnt保持1，WLAST保持1；直到有效握手才结束当前burst。WLAST是当前burst末项，不一定是整个DMA命令末项；本模块没有用输入data_last生成WLAST。

## 10. 六状态FSM

~~~mermaid
stateDiagram-v2
    [*] --> IDLE
    IDLE --> CALC: 命令握手
    CALC --> SEND_AW: 还有字节
    CALC --> DONE: 剩余为0
    SEND_AW --> SEND_AW: AW等待
    SEND_AW --> SEND_WDATA: AW握手
    SEND_WDATA --> SEND_WDATA: 尚未完成末项
    SEND_WDATA --> WAIT_BRESP: W末项握手
    WAIT_BRESP --> WAIT_BRESP: B等待
    WAIT_BRESP --> CALC: B握手且仍有字节
    WAIT_BRESP --> DONE: B握手且剩余为0
    DONE --> IDLE
~~~

| 状态 | 输出与作用 | 离开条件 |
|---|---|---|
| IDLE | cmd_ready=1，锁存新命令 | 接收cmd_valid |
| CALC_BURSTS | 计算并锁存burst_len，beat_cnt清零 | 剩余为0则DONE，否则SEND_AW |
| SEND_AW | AWVALID=1，提供地址等字段 | AWVALID && AWREADY |
| SEND_WDATA | 转发上游数据，生成WSTRB/WLAST | WVALID && WREADY && WLAST |
| WAIT_BRESP | BREADY=1，等待写响应 | BVALID && BREADY |
| DONE | done=1、busy=0 | 下一时钟沿回IDLE |

状态转换代码关键部分：

~~~systemverilog
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
~~~

对于最后一个burst，最后W握手后先进入WAIT_BRESP；最终B握手之后沿后进入DONE。与前面读DMA末拍后经过CALC不同，这里最终B握手时bytes_remaining已在之前的W握手沿更新为0，因此直接进入DONE。

## 11. 按源码顺序读寄存器和输出

### 11.1 IDLE锁存任务

~~~systemverilog
if (cmd_valid) begin
    cur_addr        <= cmd_addr;
    bytes_remaining <= cmd_len;
    tag_r           <= cmd_tag;
    error_r         <= 1'b0;
end
~~~

锁存后执行依赖寄存器，上一任务的error在新命令被接收时清零。由于IDLE时cmd_ready为1，这里与命令握手等价。

### 11.2 CALC选择长度

计算剩余beat、配置上限、4KiB边界可用beat的最小值，然后锁存：

~~~systemverilog
burst_len <= capped_beats[7:0] - 8'd1;
beat_cnt  <= 8'd0;
~~~

16 Byte对齐的20 Byte例子：capped_beats=2，burst_len=1，输出AWLEN=1。锁存使得SEND_AW等待期间AWLEN保持。

### 11.3 AW字段与写数据

~~~systemverilog
assign m_axi_awid    = tag_r;
assign m_axi_awaddr  = cur_addr;
assign m_axi_awlen   = burst_len;
assign m_axi_awsize  = axi_size_from_bytes(BYTES_PER_BEAT);
assign m_axi_awburst = AXI_BURST_INCR;
assign m_axi_awvalid = (state == S_SEND_AW);
~~~

这条AW只给当前burst的首地址；INCR模式后续beat地址由协议确定。这个模块的cur_addr仍在每次W握手后推进，用于跟踪进度和生成下一burst首地址。

### 11.4 W握手推进

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

最后不足16 Byte时剩余量饱和为0。cur_addr即使尾项只启用4 Byte仍加16，这是内部beat地址跟踪行为；本例末项后该值不表示还写入了额外12 Byte，实际写入受WSTRB控制。

### 11.5 B响应和错误

~~~systemverilog
assign m_axi_bready = (state == S_WAIT_BRESP);

if (m_axi_bvalid && m_axi_bready) begin
    if (m_axi_bresp != AXI_RESP_OKAY)
        error_r <= 1'b1;
end
~~~

一个burst的最后W握手并不代表其B响应已被接收。模块等B握手后才决定完成或发下一burst。非OKAY使error置1，任务不会立即中止；后续burst仍会继续，到下一命令被接收时才清零error。done可以与error同时为1，因此上层应结合两者解释结果。m_axi_bid没有被本实现检查。

## 12. 20 Byte逐拍例子：含AW等待、W反压、B等待

假设0x1000是16 Byte对齐地址、cmd_len=20 Byte、两个有效上游数据项D0/D1，BRESP=OKAY；采样表为源码推导，不是仿真波形。每行说明该上升沿前状态和该沿后结果。

| 上升沿 | 沿前状态与条件 | 本沿事件 | 沿后结果 |
|---|---|---|---|
| C0 | IDLE，cmd_valid=1、cmd_ready=1 | 接收命令 | CALC；addr=0x1000、剩20 |
| C1 | CALC，算出2项 | 锁存burst_len=1、beat_cnt=0 | SEND_AW |
| C2 | SEND_AW，AWVALID=1、AWREADY=0 | 等待 | SEND_AW，AW字段保持 |
| C3 | SEND_AW，AWVALID=1、AWREADY=1 | AW握手 | SEND_WDATA |
| C4 | SEND_WDATA，D0有效、WREADY=1、WLAST=0、WSTRB=FFFF | 接收D0 | SEND_WDATA；cnt=1、addr=0x1010、剩4 |
| C5 | SEND_WDATA，D1有效、WREADY=0、WLAST=1、WSTRB=000F | 等待 | 状态和进度保持 |
| C6 | SEND_WDATA，D1仍有效、WREADY=1、WLAST=1、WSTRB=000F | 接收D1 | WAIT_BRESP；addr=0x1020、剩0 |
| C7 | WAIT_BRESP，BREADY=1、BVALID=0 | 等待B响应 | WAIT_BRESP，done=0 |
| C8 | WAIT_BRESP，BVALID=1、BREADY=1、BRESP=OKAY | B握手 | DONE，沿后done=1、error=0 |
| C9 | DONE | 自动结束 | IDLE，沿后cmd_ready=1 |

C5的WSTRB和WLAST即使看起来都准备好了，也因为WREADY=0尚未写入。上游必须保持D1。C6最后W完成后done仍为0，要等C8接收B响应。若C8的BRESP非OKAY，该沿后done=1且error=1。

## 13. 当前顶层实际连接与局限

固定版本top.sv中：

~~~systemverilog
.data_valid (1'b0),       // Placeholder: connect when STORE implemented
.data_ready (),
.data_in    ({P_AXI_DATA_W{1'b0}}),
.data_last  (1'b0),
.error      ()
~~~

因此axi_dma_wr模块存在，但当前这个顶层并没有把实际SRAM数据接到上游数据口；对非零写命令，如果AW已被接受，data_valid一直为0会使其停在SEND_WDATA。不能把预期的SRAM→写DMA→DDR路径当作已集成实测结果。输出error在该实例也未连接到顶层错误汇总。onnx_sim_top使用DMA Shim供C++处理，不能用它替代AXI写RTL路径验证。

其他源码边界：

- cmd_len=0：IDLE→CALC→DONE，不产生AW/W/B。
- 不检查BID与tag是否一致；data_last输入未使用。
- 不提供自动超时；若AWREADY、上游数据或B响应一直不来则继续等待。
- 接口不包含本地SRAM源地址，外围要提供数据、打包及上游握手。
- 字节掩码按对齐起始、低字节尾部组织；任意非16 Byte对齐的起始地址没有完整lane重排和掩码处理保证。
- 默认128 bit下到4KiB最多256 beat，可放在9 bit变量中；较窄数据宽度等参数组合可能超出该位宽，不能断言所有参数可用。
- 一次仅一个在途burst；每次都等B再发下一笔，影响连续带宽。

## 14. 设计控制模块的经验

1. 先分清命令完成、一个burst完成、一个beat完成这三种事件。
2. 计数器和地址由真实握手推进，不能由VALID或某状态单独推进。
3. 给出等待状态，确认对方不ready时状态、地址、数据及辅助标志如何保持。
4. 把WLAST的burst边界和整个命令尾字节掩码分开推导。
5. 写数据接受与B响应接受分开跟踪；done时同时检查error。
6. 模块端口存在不等于已经接入系统：检查顶层连接、占位值与本地存储接口。
7. 参数化设计需要核对计数器表达范围与对齐/尾部条件。
8. 数据直通没有自带缓存，上游必须遵守valid/ready稳定性约定。

## 15. 本次验证范围与后续

本讲按真实源码推导，独立核对了状态、尾掩码、上游握手及顶层连接；没有运行仿真、没有生成VCD，也没有修改RTL。逐拍表是假设输入下的静态推导，不是实测波形。用户是否掌握仍待后续交流确认。

下一步优先回答具体问题；继续主线时，可结合当前项目明确未接入的接口，讲8 bit SRAM与128 bit AXI之间的双向打包/拆包、反压和完成协议，再继续ISA/Fetch/Decode/Dispatch。

## 参考资料

- [axi_dma_wr.sv](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/rtl/bus/axi_dma_wr.sv)。
- [top.sv](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/rtl/top.sv)。
- [Arm AXI规范：WSTRB和byte lane](https://documentation-service.arm.com/static/63ff0ebd56ea36189d4e7ee7)。
- [Arm AXI规范：写通道握手依赖](https://documentation-service.arm.com/static/68b03beb01ae952d9559f9eb)。
