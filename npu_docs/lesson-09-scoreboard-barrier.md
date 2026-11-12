# 第09讲：Scoreboard引擎忙闲管理与Barrier屏障同步

源码固定参考版本：tiny-NPU commit 8216c22b762011aa20c05fc2768423fd12dda59d。重点文件：[rtl/ctrl/scoreboard.sv](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/rtl/ctrl/scoreboard.sv)、[rtl/ctrl/barrier.sv](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/rtl/ctrl/barrier.sv)，连接参考[rtl/top.sv](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/rtl/top.sv)和[rtl/ctrl/ucode_decode.sv](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/rtl/ctrl/ucode_decode.sv)。

本讲先理解需要解决的控制问题、真实模块关系、信号、指令/数据/控制流，再按照两个源文件各自的实际顺序分段讲逻辑与代码。表格是基于固定源码和明确假设的沿前/沿后推导，不是已运行的仿真波形；未修改上游RTL或代替用户执行实验。

## 1. 为什么NPU需要记录引擎忙闲

tiny-NPU有多个功能引擎。Fetch取得一条微码，Decode识别opcode并决定目标引擎；引擎通常要多个周期才能完成一个任务，而下一条指令可能在前一个任务完成前来到Decode。

需要解决两件事：

1. 某个引擎仍在执行时，不要把新的命令误发给同一个尚无接收能力的引擎。
2. 前一阶段的多个引擎工作仍未完成时，后续依赖前一阶段结果的阶段需要等待。

Scoreboard通过每个受管理引擎的一个busy位记录忙闲：issue通知置忙，engine_done通知清忙，Decode观察can_issue判断目标引擎能否发射。Barrier利用all_idle等待受管理引擎全部空闲。

busy是控制状态，不是矩阵数据、计算结果、SRAM存储容量或引擎完成剩余周期。一个busy位也不表示任意数量的在途任务。

## 2. 先用一个计算例子建立数据依赖

假设软件准备了一段理论上的指令序列：

1. GEMM将矩阵乘结果Y写入片上SRAM。
2. BARRIER等待前一阶段受管理的引擎结束。
3. SOFTMAX从SRAM读取Y并进行归一化。

数据流是GEMM结果Y→SRAM→Softmax输入；指令流是Fetch→Decode→GEMM命令/BARRIER/Softmax命令；控制流是Decode发射、Scoreboard置忙并接收done、all_idle使Decode结束BARRIER等待。

若直接在GEMM尚未写完Y时启动Softmax，后者可能读到未更新或部分更新的数据。BARRIER的目的，是让消费指令在前一阶段合适的完成条件满足后再发射。但该方案的有效性取决于引擎done是否确实覆盖所需写回、总线及缓冲排空等条件；Scoreboard只根据done输入更新忙闲，不自行检查各SRAM地址的数据。

该序列是帮助理解依赖的理论示例。固定版本rtl/top.sv中GEMM等计算引擎是用计时逻辑生成done的stub，不可把它叙述为该顶层已经真实算出Y并完成Softmax。图计算仿真顶层有不同实现，不能与本top混作一条已验证的真实数据路径。

## 3. 实际硬件结构与数据、控制、指令流

~~~mermaid
flowchart TB
    F["微码Fetch"] -->|"instr_valid / instr_data"| D["Decode：译码与发射"]
    D -->|"功能引擎命令"| E["GEMM、Softmax、DMA等"]
    E -->|"engine_done向量"| S["Scoreboard：每引擎busy位"]
    D -->|"issue_valid / engine_id"| S
    S -->|"can_issue / all_idle"| D
    D -->|"barrier_trigger"| B["独立barrier FSM"]
    S -->|"all_idle"| B
~~~

图未画出独立barrier的stall回Decode或Fetch，因为固定版本top.sv没有这条反馈连接；barrier的done在top中也未连接下游。实际的屏障等待由Decode自身D_BARRIER状态读取all_idle执行。模块名或注释不能代替实例接线。

| 流 | 主要内容 | 本讲实际关注点 |
|---|---|---|
| 指令流 | 微码从Fetch到Decode，opcode选择GEMM、BARRIER或Softmax | Scoreboard不接128 bit指令，而接Decode提取后的issue通知与引擎编号 |
| 数据流 | 功能引擎访问SRAM并产生/消费张量 | Scoreboard和barrier不传张量数据，不检查地址和数据正确性 |
| 控制流 | issue登记、busy/can_issue、engine_done、all_idle和屏障等待 | 上升沿采样；寄存状态沿后变化，组合输出随后变化 |

## 4. 六个引擎和默认位图：先认清编号

npu_pkg.sv定义默认NUM_ENGINES=6。固定top.sv的done向量映射：

| ID | 计分板位 | 引擎 | 完成通知 |
|---:|---|---|---|
| 0 | bit 0 | GEMM | gemm_done |
| 1 | bit 1 | Softmax | softmax_done |
| 2 | bit 2 | LayerNorm | layernorm_done |
| 3 | bit 3 | GELU | gelu_done |
| 4 | bit 4 | Vec | vec_done |
| 5 | bit 5 | DMA | dma_rd_done 或 dma_wr_done |

例如二进制向量按常规从左到右写bit5…bit0：

~~~text
busy_q = 6'b000001：GEMM忙，其余五个空闲。
busy_q = 6'b000010：Softmax忙，其余五个空闲。
busy_q = 6'b000011：GEMM和Softmax都忙。
~~~

DMA读写共享bit5及或起来的done。正常调度需保证该共享忙闲语义与实际同时进行的操作一致；若系统其他路径允许多个共享bit的独立任务并发，仅一个done就清busy可能不足以证明全部完成。本源码没有计数多个在途DMA任务。

包中还定义ID 6和7用于RMSNorm/RoPE，但默认Scoreboard只有0～5六个位，top把Decode看到的can_issue高两位补1；补1不代表固定top已连接真实RMSNorm/RoPE引擎。

## 5. Scoreboard的端口、变量与单位

所有方向以scoreboard模块为参考，默认NUM_ENGINES=6。

| 名称 | 类型/宽度 | 含义、单位和有效时间 |
|---|---|---|
| clk | 输入1 bit | 采样busy_d的时钟上升沿 |
| rst_n | 输入1 bit | 低有效异步复位；busy_q清0 |
| NUM_ENGINES | int参数，默认6 | 实际管理的引擎位数，不是周期数 |
| issue_valid | 输入1 bit | 本沿有一条引擎发射通知 |
| issue_engine_id | 输入3 bit | 被通知引擎的编号，默认合法0～5；与issue_valid同时解释 |
| engine_done | 输入6 bit | 每位一个引擎完成通知，1表示该位所对应引擎完成事件 |
| engine_busy | 输出6 bit | 当前busy_q，每位1忙、0空闲 |
| can_issue | 输出6 bit | 逐位取反，1表示该引擎当前未记录为忙 |
| all_idle | 输出1 bit | busy_q全0时为1 |
| busy_q | 内部6 bit寄存器 | 当前每个引擎忙闲；只在复位或时钟沿更新 |
| busy_d | 内部6 bit组合量 | 基于当前busy_q、issue_onehot、engine_done算出的沿后候选值 |
| issue_onehot | 内部6 bit组合量 | 有效合法issue只置对应一位；无效或越界全0 |

issue_valid是分发通知，Scoreboard没有输入功能引擎的cmd_ready，也没有自行验证引擎实际接受命令。固定top中DMA的cmd_ready未反馈到Decode，因此不能把issue脉冲自动解释为所有引擎均完成了valid/ready接受握手。

## 6. Scoreboard数据结构：一个busy位如何控制发射

假设复位后busy_q=000000，则：

~~~text
engine_busy = busy_q       = 000000
can_issue   = ~busy_q      = 111111
all_idle    = (busy_q==0)  = 1
~~~

如果有效issue的engine_id=0，在对应时钟沿后busy_q的bit0变1，can_issue[0]变0；其他引擎的can_issue仍为1。之后engine_done[0]=1在某沿采样后，bit0清0，对应can_issue沿后恢复1。

can_issue反映的是Scoreboard当前已登记的busy_q，不会识别未登记的下游缓冲、任意存储冲突、尚未被真正接收的命令或“马上在本沿到来但尚未进入寄存器”的issue。

## 7. 按scoreboard.sv源码顺序：模块头和端口

源码先导入类型包，声明参数与端口：

~~~systemverilog
module scoreboard
  import npu_pkg::*;
  import isa_pkg::*;
#(
    parameter int NUM_ENGINES = 6
) (
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic                   issue_valid,
    input  logic [2:0]             issue_engine_id,
    input  logic [NUM_ENGINES-1:0] engine_done,
    output logic [NUM_ENGINES-1:0] engine_busy,
    output logic [NUM_ENGINES-1:0] can_issue,
    output logic                   all_idle
);
~~~

硬件目的：统一接收Decode的目标引擎和各引擎done，用状态位输出忙闲。NUM_ENGINES决定向量宽度；issue_engine_id固定3 bit，默认可表达0～7。参数是编译/实例化配置，不表示模块能安全支持任意引擎数量：ID宽度和范围比较也需匹配。

## 8. 按源码：busy_q / busy_d / issue_onehot声明

~~~systemverilog
logic [NUM_ENGINES-1:0] busy_q, busy_d;
logic [NUM_ENGINES-1:0] issue_onehot;
~~~

busy_q是寄存器当前值，busy_d是将被寄存的下一值，issue_onehot是组合解码结果。后缀q/d不是语言强制关键字，而是本项目的命名习惯。

~~~text
busy_q → 组合计算busy_d → 时钟沿保存 → 新busy_q
~~~

一个6 bit向量包含6个独立状态位；不是把一个6 bit数字解释为一个“引擎编号”。

## 9. 按源码：把引擎编号变成one-hot

### 9.1 逻辑

Decode给一个3 bit编号，例如1；Scoreboard需要把它转成6 bit位图，只有bit1为1，告诉后面组合逻辑要设置哪一位。

~~~systemverilog
always_comb begin
    issue_onehot = '0;
    if (issue_valid &&
        ({1'b0, issue_engine_id} < NUM_ENGINES[3:0])) begin
        issue_onehot[issue_engine_id] = 1'b1;
    end
end
~~~

- 默认issue_onehot='0，先给所有位赋0。
- issue_valid=1且编号小于NUM_ENGINES时，再将对应位设1。
- {1'b0, issue_engine_id}是在3 bit编号高位补0，得到4 bit。
- NUM_ENGINES[3:0]取得参数的低4 bit；默认值6。
- always_comb是组合硬件，不需要等待时钟沿才得出one-hot。

| issue_valid | issue_engine_id | issue_onehot | 意义 |
|---:|---:|---|---|
| 0 | 任意已知值 | 000000 | 没有发射通知 |
| 1 | 0 | 000001 | 对GEMM的通知 |
| 1 | 1 | 000010 | 对Softmax的通知 |
| 1 | 5 | 100000 | 对DMA的通知 |
| 1 | 6或7 | 000000 | 默认6引擎范围外，不设任何busy位 |

该模块自身只忽略越界ID，不在此产生error；固定top的仿真assert另有对issue_engine_id范围的检查，不能把“位图忽略”理解为系统完整错误处理。

## 10. 按源码：busy_d如何计算

### 10.1 逻辑

每一位有三个信息：

- busy_q：这个引擎沿前是否忙。
- issue_onehot：本沿前是否收到新发射通知。
- engine_done：本沿前是否收到完成通知。

先准备沿后应保持、清除或置位的busy_d；下一个上升沿再存入busy_q。

~~~systemverilog
always_comb begin
    busy_d = busy_q;

    busy_d = busy_d & ~engine_done;
    busy_d = busy_d | issue_onehot;

    for (int i = 0; i < NUM_ENGINES; i++) begin
        if (engine_done[i] && issue_onehot[i]) begin
            busy_d[i] = 1'b0;
        end
    end
end
~~~

这些是同一个always_comb中的阻塞赋值，按此组合过程的语句顺序计算busy_d；这和整个RTL文件中多个always/assign并发运行并不矛盾。

- 起始busy_d=busy_q表示无事件时保持。
- busy_d & ~engine_done清除报告完成的位。
- busy_d | issue_onehot设置收到发射通知的位。
- 最后for循环再次检查同一位同时done和issue，强制清0。

for循环描述并行的逐位判断硬件，不表示清6位需要6个时钟周期。

### 10.2 单个busy位的真值

| issue该位 | done该位 | 下一busy位 | 说明 |
|---:|---:|---:|---|
| 0 | 0 | 保持原值 | 无事件 |
| 1 | 0 | 1 | 登记发射 |
| 0 | 1 | 0 | 登记完成 |
| 1 | 1 | 0 | 本源码最后强制清0，done优先 |

对已知0/1输入，最终逻辑可等价写成：

~~~text
busy_d = (busy_q | issue_onehot) & ~engine_done
~~~

重要：源文件部分注释先描述同时发生“最终忙”，后面又描述“清零优先”；最终执行代码中for循环的最后赋值决定同位done优先。

同一位done和issue同时到来时，新issue被该组合逻辑清掉；Scoreboard内部没有保存它，也没有自动重发机制。源码注释假设上游正常调度避免这个组合，但不能把注释中的“以后会重新发”当成已经在该模块中实现。是否发生需看上游和实际时序，不能只凭该边界断言正常运行必然有故障。

### 10.3 不同引擎事件可以同拍

假设当前GEMM忙、Softmax空闲：

~~~text
busy_q      = 6'b000001
engine_done = 6'b000001   // GEMM完成
issue_onehot= 6'b000010   // 新发射Softmax
~~~

两事件属于不同位，组合结果：

~~~text
busy_d = 6'b000010
~~~

下一沿后GEMM空闲、Softmax忙。

## 11. 按源码：busy_q寄存器和输出

~~~systemverilog
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        busy_q <= '0;
    else
        busy_q <= busy_d;
end

assign engine_busy = busy_q;
assign can_issue   = ~busy_q;
assign all_idle    = (busy_q == '0);
~~~

rst_n拉低时所有忙位异步清0；正常时上升沿把busy_d保存到busy_q。can_issue、all_idle是busy_q的组合输出：busy_q沿后变化后，组合输出随之变化；它们不是新的独立寄存器。

all_idle只检查这6个busy位；不检查SRAM地址内容、AXI写响应或额外没有登记的引擎。若最终写数据仍留在其他缓冲中，但该引擎提前给done，Scoreboard也会清busy；控制器需要保证done语义足以覆盖相关依赖。

## 12. Scoreboard独立模块逐沿案例

先只观察scoreboard输入，不假设Decode可以每拍连续产生以下issue。取初值复位后busy_q=000000。

| 沿 | 沿前输入 | 本沿采样busy_d | 沿后busy_q | 沿后all_idle |
|---|---|---|---|---:|
| E0 | issue_valid=1、id=0，done=0 | 000001 | 000001，GEMM忙 | 0 |
| E1 | issue_valid=1、id=1，done=0 | 000011 | 000011，两引擎忙 | 0 |
| E2 | done[0]=1，issue=0 | 000010 | 000010，GEMM空闲 | 0 |
| E3 | done[1]=1，issue=0 | 000000 | 000000 | 1 |

E0、E1连续issue只是独立模块输入示例，固定Decode还存在D_DECODE状态与实际发射间隔。真正的issue与Decode握手差一拍，见后面的系统案例。

## 13. Barrier模块到底是什么

barrier.sv另有一个独立三状态FSM：收到trigger后，如果all_idle已为1就产生完成；否则置stall等待all_idle，再解除stall并给done脉冲。

它不接引擎编号、不检查指令具体地址、不传输张量，也没有记录“每个引擎有几个任务”。它依赖外部Scoreboard提供all_idle。

| 信号/变量 | 位宽 | 意义 |
|---|---:|---|
| clk / rst_n | 各1 bit | 时钟和低有效异步复位 |
| trigger | 1 bit | 外部发起屏障通知，按单拍脉冲约定 |
| all_idle | 1 bit | 所有受管理引擎是否空闲，输入 |
| stall | 1 bit | 已登记的屏障等待状态，输出 |
| done | 1 bit | 屏障满足的一个周期完成指示，输出 |
| state_q / state_d | 各2 bit | 当前/下一状态 |
| stall_q / stall_d | 各1 bit | 当前/下一停顿输出 |
| done_q / done_d | 各1 bit | 当前/下一完成输出 |

注意q是寄存器当前值、d是组合候选值。本模块输出stall和done都来自寄存器，不是trigger当拍直接组合输出。

## 14. 按barrier.sv源码顺序：状态和默认值

~~~systemverilog
typedef enum logic [1:0] {
    B_IDLE = 2'd0,
    B_WAIT = 2'd1,
    B_DONE = 2'd2
} barrier_state_e;

barrier_state_e state_q, state_d;
logic stall_q, stall_d;
logic done_q, done_d;
~~~

| 状态 | 含义 |
|---|---|
| B_IDLE | 等待trigger |
| B_WAIT | 先前trigger已接收，等待all_idle |
| B_DONE | 屏障完成的收尾状态，下一沿回IDLE |

组合逻辑最前面：

~~~systemverilog
state_d = state_q;
stall_d = stall_q;
done_d  = 1'b0;
~~~

默认状态、stall保持；done_d默认0，所以除非本次组合逻辑明确把done_d置1，否则下一沿done_q清0。完成后产生的是一个周期的done_q高电平。

## 15. 按源码：B_IDLE、B_WAIT、B_DONE

### 15.1 B_IDLE：收到trigger时如何判断

~~~systemverilog
B_IDLE: begin
    stall_d = 1'b0;
    if (trigger) begin
        if (all_idle) begin
            done_d  = 1'b1;
            state_d = B_DONE;
        end else begin
            stall_d = 1'b1;
            state_d = B_WAIT;
        end
    end
end
~~~

逻辑：无trigger时保持空闲；trigger在当前沿前为1且all_idle为1，则该沿后进入B_DONE并拉高done_q。若all_idle为0，该沿后进入B_WAIT并拉高stall_q。因为输出寄存，观察到stall或done变化在采样沿后。

### 15.2 B_WAIT：等待已登记的引擎完成

~~~systemverilog
B_WAIT: begin
    stall_d = 1'b1;
    if (all_idle) begin
        stall_d = 1'b0;
        done_d  = 1'b1;
        state_d = B_DONE;
    end
end
~~~

all_idle=0时继续等待；沿前all_idle=1时，下一沿后stall=0、done=1、进入B_DONE。

### 15.3 B_DONE：结束脉冲并返回

~~~systemverilog
B_DONE: begin
    stall_d = 1'b0;
    state_d = B_IDLE;
end
~~~

done_d在组合默认部分为0，因此下一沿返回B_IDLE时done_q清0。trigger仅在B_IDLE读取，B_WAIT/B_DONE期间的新trigger没有被本模块排队；外围需满足接口使用约定。

## 16. 按源码：barrier寄存器与输出

~~~systemverilog
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state_q <= B_IDLE;
        stall_q <= 1'b0;
        done_q  <= 1'b0;
    end else begin
        state_q <= state_d;
        stall_q <= stall_d;
        done_q  <= done_d;
    end
end

assign stall = stall_q;
assign done  = done_q;
~~~

同一个上升沿，Scoreboard的busy_q和Barrier的state_q/stall_q/done_q都是根据沿前值更新。Barrier不能在这一沿读取到Scoreboard在这个沿刚刚清除后的busy_q，必须等待沿后all_idle变化，再在下一沿作状态转移。

## 17. Barrier独立模块逐沿案例

### 17.1 触发时已经空闲

假设沿前B_IDLE、trigger=1、all_idle=1：

| 沿 | 沿前 | 沿后 |
|---|---|---|
| E0 | B_IDLE、trigger=1、all_idle=1 | B_DONE、stall=0、done=1 |
| E1 | B_DONE | B_IDLE、stall=0、done=0 |

done不是trigger刚拉高后立刻组合变化，而是在E0沿采样后为1。

### 17.2 正在忙，最后完成事件到来

假设E0沿前trigger=1、busy_q非0、all_idle=0：

| 沿 | 沿前输入/状态 | 本沿动作 | 沿后结果 |
|---|---|---|---|
| E0 | B_IDLE、trigger=1、all_idle=0 | 开始等待 | B_WAIT、stall=1、done=0 |
| E1 | B_WAIT、all_idle=0，最后引擎done=1 | Scoreboard清最后busy；Barrier仍看到旧all_idle=0 | busy_q沿后为0，all_idle变1；Barrier仍WAIT、stall=1 |
| E2 | B_WAIT、all_idle=1 | 屏障满足 | B_DONE、stall=0、done=1 |
| E3 | B_DONE | 完成收尾 | B_IDLE、done=0 |

E1不是Barrier“多等错了一拍”，而是两个时序模块同时采样沿前输入；busy_q清0及组合all_idle变1发生在E1沿后。

## 18. 实际top接线：独立barrier和Decode自身等待是两件事

固定top中有：

~~~systemverilog
barrier u_barrier (
    .trigger  (barrier_trigger),
    .all_idle (all_idle),
    .stall    (barrier_stall),
    .done     ()
);
~~~

top中barrier_stall没有接回Decode或Fetch，barrier.done悬空。Decode自己的D_BARRIER状态却直接判断all_idle并保持instr_ready=0，直到该条件满足。因此此版本实际阻塞下一条取指/译码的控制路径来自Decode内部，而非依靠独立barrier_stall反馈。

独立barrier存在，并从Decode接收barrier_trigger、从Scoreboard接收all_idle；但其输出没有形成控制闭环。不能只读barrier.sv的注释就把理想反馈画成当前top已连接结构。

## 19. 系统例子：GEMM → BARRIER → Softmax的指令和控制时序

假设GEMM指令先在E0被Decode接收、目标引擎空闲；后续BARRIER在Decode空闲时到达；GEMM在E4给出done。假设程序使用正确的指令格式和资源安排。此表只讲命令/状态，固定top的GEMM是stub，不声称真正计算。

| 沿 | 沿前关键条件 | 本沿动作 | 沿后结果 |
|---|---|---|---|
| E0 | Decode D_IDLE；GEMM valid，can_issue[0]=1 | Decode握手接收GEMM | Decode进入D_DECODE，GEMM cmd_valid和issue_valid有效；Scoreboard busy仍0 |
| E1 | issue_valid=1、engine_id=0 | 引擎采命令、Scoreboard采issue | busy[0]=1、all_idle=0；Decode回D_IDLE |
| E2 | Decode可接收BARRIER，busy[0]=1 | Decode接收BARRIER | Decode进入D_BARRIER、barrier_trigger有效；独立barrier此沿仍读旧trigger=0 |
| E3 | trigger=1、all_idle=0 | 独立barrier采trigger；Decode继续等待 | 独立barrier进入B_WAIT、stall=1；Decode仍D_BARRIER |
| E4 | GEMM done=1，沿前all_idle=0 | Scoreboard清busy；Decode与barrier仍看旧all_idle=0 | busy=0、all_idle沿后变1；两者仍等待 |
| E5 | 沿前all_idle=1 | Decode退出D_BARRIER；独立barrier也结束等待 | Decode回IDLE；独立barrier B_DONE、stall=0、done=1 |
| E6 | 假设Softmax指令此时有效且其can_issue=1 | Decode接收Softmax；独立barrier收尾 | Softmax cmd_valid/issue有效；barrier回IDLE |
| E7 | Softmax issue_valid=1 | Scoreboard登记Softmax忙 | busy[1]=1 |

E0到E1差一沿的原因：Decode先在E0沿把issue_valid_q更新为1，Scoreboard同E0沿看到的仍是旧issue；E1才采到新的issue_valid。

E2到E3也同理：Decode在E2沿将barrier_trigger_q更新为1，独立barrier到E3沿才采到它。Decode自身D_BARRIER控制等待，并未使用独立barrier的stall或done。

## 20. all_idle与未登记issue：需要说明的模块边界

all_idle是busy_q是否为0的组合结果，未直接把当前issue_valid组合进去。如果在独立模块接口下出现以下假设：

- 某沿之前busy_q=0，所以all_idle=1。
- 同一沿前一个有效issue和一个barrier trigger都为1。

那么该沿Barrier可能依据沿前all_idle=1认为屏障满足，而Scoreboard在同沿后才把引擎busy位置1。单独观察这两个模块，all_idle并不自动代表“包括同沿新issue的原子全空闲”。

这只是接口级条件分析，不能据此声称固定top正常相邻GEMM→BARRIER必然触发。当前Decode普通指令接收后有D_DECODE周期，Scoreboard在issue有效的下一沿登记；下一条BARRIER的正常接收还受Decode/Fetch时序约束。是否安全应结合完整路径、同步约定和所有前提验证；同时done是否覆盖本地存储落存仍是另一项系统条件。

## 21. 与其他硬件设计的关系及可迁移经验

1. 分清“指令被Decode接收”“issue通知被Scoreboard采样”“引擎实际接受命令”“运算和写回完成”四种事件；本top的某些链路还没有完整ready反馈。
2. 每个共享资源至少需要可解释的资源状态；一个busy位只适合其表示的任务并发约束，不能隐含支持任意排队数量。
3. busy状态依据显式issue和done事件更新；需要确认输入事件只出现一次、编号有效，且没有丢失或重复。
4. 相同位set和clear同沿发生时，逐条跟到最终赋值再定优先级；不要仅凭冲突注释作判断。
5. 指令依赖涉及数据落存和可见性；屏障是否可靠取决于done和all_idle覆盖范围，不能仅因bit清零就证明任意地址安全。
6. 寄存器同沿读取旧值；busy沿后清零后，另一个时序FSM一般要等下一沿再采到组合输出all_idle=1。
7. 模块的输出端口存在不代表接线已闭环；检查顶层实例、悬空端、补位和stub。
8. 用户亲自实验时才运行实际仿真并核对波形；当前表格仅为源码推导。

## 22. 本讲停点与源码边界

- 已解释两个新模块的硬件结构、数据/控制/指令流、变量、按源码顺序的逻辑与实现，以及多个逐沿例子。
- 固定top的计算引擎多为stub；独立barrier_stall和done未形成反馈闭环。
- Scoreboard管理六个引擎busy位；6/7补can_issue不等于引擎存在；KV相关命令若映射DMA，需根据实际done连接核实完成路径。
- 未修改RTL、未运行HDL仿真、未生成VCD；用户理解程度尚待交流。
- 下一步优先回答对busy、issue、done、all_idle、barrier时序或源码的具体问题，再依照用户需求与路线继续。

## 源码位置

- [scoreboard.sv](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/rtl/ctrl/scoreboard.sv)：one-hot、busy_q/busy_d与输出。
- [barrier.sv](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/rtl/ctrl/barrier.sv)：独立三状态FSM与注册输出。
- [ucode_decode.sv](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/rtl/ctrl/ucode_decode.sv)：issue、barrier_trigger寄存和D_BARRIER。
- [top.sv](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/rtl/top.sv)：实例、done向量、补位及占位连接。
- [npu_pkg.sv](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/rtl/pkg/npu_pkg.sv)：引擎编号。

