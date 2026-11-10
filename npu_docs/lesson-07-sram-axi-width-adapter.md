# 第07讲补充：8 bit SRAM与128 bit AXI之间的宽度适配

日期：2026-11-10。源码固定参考版本：8216c22b762011aa20c05fc2768423fd12dda59d。

本讲目标是把之前的SRAM和读写DMA连接起来：DDR→SRAM方向解释128 bit拆成8 bit；SRAM→DDR方向解释8 bit打包成128 bit。遵循“硬件结构→变量与单位→数据/控制→逐沿时序→设计逻辑”。这里的适配器是依据接口设计的教学方案，不是该版本已接入的模块，也不是已经验证的RTL实现。

## 1. 为什么需要位宽适配

以图计算仿真封装中的8 bit SRAM0为例，每个地址对应1 Byte；上一讲的AXI数据宽度是128 bit，即16 Byte。

| 项目 | 8 bit SRAM口 | 128 bit DMA数据流 |
|---|---|---|
| 单项宽度 | 8 bit | 128 bit |
| 单项容量 | 1 Byte | 16 Byte |
| 地址/握手单位 | SRAM地址加1，对应下一个Byte | 一个valid/ready握手交付1个beat |
| 假设的接入能力 | 每周期最多接受或发起1个8 bit访问 | 峰值接口可一拍交付1个128 bit beat，实际可等待 |

两个方向需要不同动作：

- 外部读取到SRAM：一项128 bit拆成16个8 bit字节，依次提交本地写口。
- SRAM数据写往外部：逐字节读取，打包成一项128 bit，交给写DMA。

位宽适配本身不意味着系统吞吐达到16 Byte/周期。如果最终只有一个每周期1 Byte的SRAM端口，长期有效吞吐受该端口限制；单缓冲的切换和读流水还可能引入额外空拍。假设同一时钟、无压缩并且所有字节都必须通过该口，稳态上限至多1 Byte/cycle，而不是AXI宽度除以8得到的16 Byte/cycle。

## 2. 先核对项目：哪些是已有的，哪些是本讲设计

固定版本的真实边界：

| 项目文件 | 真实行为 |
|---|---|
| rtl/bus/axi_dma_rd.sv | 接收AXI R，向内部输出128 bit data_out/data_valid/data_last；data_ready可反压；没有本地SRAM目的地址或data_keep |
| rtl/bus/axi_dma_wr.sv | 接收128 bit data_in/data_valid，转为AXI W；没有本地SRAM源地址；输入data_last未被使用；根据命令长度生成WSTRB |
| rtl/mem/sram_dp.sv | 参数化双口同步SRAM；WIDTH=8时每地址1 Byte；读数据寄存到dout |
| rtl/top.sv | 读DMA data_ready恒1为占位，未接实际SRAM写适配；写DMA的data_valid恒0、data_in恒0；尚无完整DMA↔数据SRAM连接 |
| sim/verilator/onnx_sim_top.sv | 用DMA Shim将命令和地址交给C++ TB处理，并由TB写接口访问SRAM，不是上述AXI DMA的128↔8 RTL适配器 |

top.sv里另有128 bit宽微码SRAM，其每个地址对应一项128 bit微码；不能把它的地址单位混同于8 bit SRAM0的字节地址。当前top的微码SRAM另一端口也未由DMA直接写入。

这一节的外围适配器是可行的设计示意，不表示已经在上游仓库实现，也没有修改上游RTL。

## 3. 共用示例与假设

命令长度为20 Byte，外部地址与本地地址分别为：

~~~text
外部地址：0x1000
本地8 bit SRAM基地址：0x0200
有效数据：b0、b1、……、b19
~~~

外部起始地址16 Byte对齐，低地址对应低字节lane。本地基地址只是本示例假设。DMA一次传输16 Byte：

~~~text
D0：b0～b15，16个有效字节
D1：b16～b19，只有低4个字节有效
~~~

采用单个128 bit缓冲，填满时不再接下一项；为简单起见，缓冲释放的同一沿不能再次装入，即下一沿才接收下一项。假设本地端口每沿最多完成1 Byte，示例中除明确标出的W反压外都能拿到SRAM访问许可；如多个模块争用，需要实际仲裁和grant，不能假定每个请求自动成功。

L=20，非零，外部地址对齐。稍后说明零长度、错误和额外读取边界。

命令信息必须同时发往DMA和适配器：DMA需要外部地址和20 Byte长度；适配器需要本地地址和相同的20 Byte长度。两份长度要在一次真正的命令握手时一致锁存，不能任意时刻读取外部正在变化的cmd_len。

## 4. 读方向硬件：AXI读DMA输出怎样落进SRAM

~~~mermaid
flowchart TB
    EXT["外部存储与AXI R"] --> DMA["axi_dma_rd"]
    DMA -->|"128 bit数据流"| BUF["128 bit接收缓冲"]
    BUF --> MUX["16选1字节选择"]
    MUX --> SRAM["8 bit SRAM写端口"]
    COUNT["本地地址、剩余量与字节索引"] --> MUX
    COUNT --> SRAM
    BUF -->|"data_ready反压"| DMA
    DMA -->|"done / error"| COUNT
~~~

本方案新增：

1. 128 bit缓冲寄存器beat_buf，保存整个已接收beat。
2. 1 bit buf_valid，表示缓冲是否持有尚未写完的数据。
3. 4 bit byte_index，选择lane 0～15。
4. 至少5 bit valid_bytes_this，表示本次缓冲有0～16个有效字节。
5. 本地字节写地址dst_addr。
6. 与命令长度同范围的bytes_left，以及对DMA done/error的记录。
7. SRAM写端口选择/仲裁逻辑；示例按写口每沿有许可处理。

为什么索引4 bit而有效字节数至少5 bit？

~~~text
lane索引：0～15，共16个值，4 bit足够。
有效字节数：0～16，包含数值16，需要5 bit。
~~~

### 4.1 数据流

对一项已经被接收的beat，定义本示例的低lane优先排列：

~~~text
beat_buf[7:0]    = 当前beat的第0个Byte
beat_buf[15:8]   = 当前beat的第1个Byte
...
beat_buf[127:120]= 当前beat的第15个Byte
~~~

字节选择器选择beat_buf[8*byte_index +: 8]，送给SRAM写数据端。这里是SystemVerilog的变宽起点、固定宽度切片写法：从bit 8*byte_index开始选8 bit，物理上可以实现为字节选择多路器。

数据类型如INT8/FP16由上层存储格式决定；适配器只按约定搬字节。对FP16必须由系统明确低/高字节顺序，本讲不以排列约定替代项目实际张量布局。

### 4.2 控制流与反压

一种保守控制条件：

~~~text
dma_data_ready = transfer_active && !buf_valid
接收事件        = dma_data_valid && dma_data_ready
本地提交事件    = sram_wr_request && sram_wr_grant
~~~

其中sram_wr_grant代表外围仲裁实际选中该写请求；固定的sram_dp端口本身没有通用ready/grant，这里是本例为系统集成引入的控制条件。若已独占该端口，则grant可恒1。

- 缓冲空时可接受一项DMA数据，并锁存对应的valid_bytes_this。
- 缓冲满时dma_data_ready=0；读DMA会将反压传向AXI R通道。
- 每次本地提交事件，SRAM地址加1、byte_index加1、bytes_left减1。
- 当前beat最后一个有效字节写入后，沿后清除buf_valid。
- 本例不支持同沿释放并重装；沿后下一周期才再次ready。

AXI发送方必须在VALID=1而READY=0期间保持该项及其附属信息；此约束从AXI R接口通过读DMA传递到下游的反压结构。

### 4.3 为什么必须另存原始长度

读DMA的data_last只告诉你“这是整个命令最后一项”，不说明尾项包含多少有效Byte，也没有data_keep。因此适配器需要独立保存L=20，并计算：

~~~text
valid_bytes_this = min(16, bytes_left)
~~~

在本示例简单设计中，下一beat只有上一beat写完才接收，所以接收D0时bytes_left=20，valid_bytes_this=16；接收D1时bytes_left=4，valid_bytes_this=4。如果扩展为多个接收项排队，需要分别维护“已接收/已分配的字节数”和“已落存的字节数”，不能用单一落存计数错误地给多个在途beat分配长度。

## 5. 读方向逐沿时序：20 Byte从DMA到SRAM

假设D0最早在E0有效，D1在之后尽早可用且会在反压时保持；8 bit SRAM写口每沿获得许可。

| 上升沿 | 沿前动作 | 本沿事件 | 沿后缓冲 / 本地结果 |
|---|---|---|---|
| E0 | DMA提供D0，adapter ready=1 | 接收D0 | beat_buf保存D0，valid_bytes_this=16，buf_valid=1 |
| E1 | 写地址0x0200，选择lane0 | 写b0 | bytes_left=19 |
| E2 | 写地址0x0201，选择lane1 | 写b1 | bytes_left=18 |
| … | 每沿写一个Byte | 逐项提交 | … |
| E16 | 写地址0x020F，选择lane15 | 写b15 | bytes_left=4，buf_valid沿后清0 |
| E17 | 缓冲为空，DMA提供D1 | 接收D1 | valid_bytes_this=4，buf_valid=1 |
| E18 | 写地址0x0210，选择lane0 | 写b16 | bytes_left=3 |
| E19 | 写地址0x0211，选择lane1 | 写b17 | bytes_left=2 |
| E20 | 写地址0x0212，选择lane2 | 写b18 | bytes_left=1 |
| E21 | 写地址0x0213，选择lane3 | 写b19 | bytes_left=0，缓冲清空、本地最后写已提交 |

E1～E16期间D1如果已经到达，data_ready=0，不会覆盖D0。本示例有意不在E16同沿重装，故E17才可接收D1。

本地最后一项写“提交”是指E21沿上SRAM写端口采样写使能、地址与数据；如果外部接口有额外写缓冲或写响应，完成条件还要按照实际接口延后。

### 5.1 读DMA done为什么会比本地写完早

结合固定版本axi_dma_rd，在D1是整个命令最后一项且RLAST正常时：

- E17沿接收最后一项R数据；沿后DMA进入CALC。
- E18沿检查bytes_remaining已为0；沿后进入DONE，done拉高。
- 适配器仍需E18～E21四个沿逐字节写尾项。
- E21最后一个Byte才提交到SRAM。

所以E18的DMA done不能直接当作“20 Byte已写完SRAM”。本表明确区分E18沿之前和之后：done在E18沿后拉高，持续DONE状态一周期。

### 5.2 tile_ready应由哪些事实组成

一个保守方案针对本次任务分别锁存：

- dma_done_seen：观察过读DMA的done脉冲。
- dma_error_seen：在done时锁存该次DMA的error。
- local_write_done：20个有效Byte都已经在本地写口提交，缓冲为空。

当三者依次满足“DMA完成、本地完成、本次无错误”，才宣告tile_ready。由于done可能早于最后本地写，必须保存done事件，不能在E21才临时看可能早已消失的done脉冲。也要在DMA开始下一条命令清error前保存本次结果；发生错误时应向控制器报告失败，不把tile标成有效。

可以选择在最后一写之后的下一沿再拉高ready，这会多一个周期但便于避免同沿使用旧标志的歧义。上面是教学协议选择，并非原tile_buffer现有的ready逻辑。

### 5.3 尾部多取与零长度

20 Byte的读命令在本满宽实现中会请求两个16 Byte beat，尾项的12 Byte虽然被适配器丢弃，外部读请求仍可能访问覆盖到的额外地址。因此本方案只在目标普通存储区域允许这些额外读取时安全；不能对带读副作用的设备寄存器或不可访问区域作同样假设。

长度为0时读DMA不会输出数据beat，也就没有data_last；适配器需要由命令/完成控制单独处理0字节，不应永远等待尾项。是否把空tile视为就绪需要上层定义。

## 6. 写方向硬件：SRAM的8 bit数据怎样交给写DMA

~~~mermaid
flowchart TB
    ADDR["本地读地址与请求计数"] --> SRAM["8 bit同步读SRAM"]
    SRAM -->|"每次返回8 bit"| PACK["128 bit打包寄存器"]
    INDEX["返回有效位与延迟索引"] --> PACK
    PACK -->|"data_in / data_valid"| DMA["axi_dma_wr"]
    DMA -->|"data_ready"| PACK
    DMA -->|"AW、W、B"| EXT["AXI与外部存储"]
~~~

打包器需要：

1. 本地源地址src_addr，每发出一个实际SRAM读请求前进1 Byte。
2. 128 bit pack_buf，保存已捕获的字节。
3. 4 bit请求lane索引和与返回对齐的延迟lane索引。
4. rd_pending/rd_valid，用于区分dout是新返回还是保持的旧值。
5. 本项有效字节目标，范围1～16，至少5 bit。
6. pack_valid，表示该128 bit打包项已经准备好。
7. 用于记录剩余总字节、请求是否完成、是否有未捕获读响应的控制。

写DMA会用自己锁存的cmd_len生成WSTRB，打包器不向该DMA传入WSTRB。打包器必须把有效的尾部字节放入约定的低lane；其余lane可以清0，但最终不写入由写DMA产生的WSTRB控制。

### 6.1 同步SRAM读的关键时钟沿

原sram_dp的读端逻辑：

~~~systemverilog
always_ff @(posedge clk) begin
    if (en_a && !we_a)
        dout_a <= mem[addr_a];
end
~~~

假设E0沿之前地址0x0200有效：

- E0沿：SRAM采样读地址。
- E0沿后：SRAM的dout_a更新为地址0x0200的数据b0。
- 若打包器也在E0沿用always_ff采样dout_a，它读到的是E0沿前的旧值。
- E1沿：打包寄存器才捕获E0读出的b0。

这是非阻塞赋值对应的同沿语义。连续读允许E1沿一边捕获b0、一边发起b1读请求；要把请求索引同步延迟，使b0进入lane0，而不是用已更新的请求索引把它误放到lane1。

### 6.2 第一项16 Byte的连续读时序

假设SRAM每沿可接收1个读请求且打包器已经启动；“捕获”指打包寄存器在该沿采样前一沿读出的dout。

| 上升沿 | 发起本沿读请求 | 本沿捕获到pack_buf | 沿后结果 |
|---|---|---|---|
| E0 | 请求b0 | 无新返回 | dout沿后为b0 |
| E1 | 请求b1 | lane0←b0 | dout沿后为b1 |
| E2 | 请求b2 | lane1←b1 | dout沿后为b2 |
| … | … | … | … |
| E15 | 请求b15 | lane14←b14 | dout沿后为b15 |
| E16 | 不再请求本项数据 | lane15←b15 | pack_buf完整，pack_valid沿后置1 |
| E17 | 本例不同时重填 | 若data_ready=1，打包项握手 | DMA接收128 bit数据 |

E16不能既用非阻塞赋值更新pack_buf的最后一个lane，又在同一沿把旧pack_buf复制到另一个输出寄存器而期望它包含新lane15；同沿后者读到旧pack_buf。可直接把pack_buf连到DMA data_in并在沿后置pack_valid，或者显式构造包含最后返回字节的下一值。示例假设pack_buf直连、无额外输出寄存器。

pack_valid=1但data_ready=0时，必须保持pack_valid及整个pack_buf稳定。不能因为想读取下一个beat而覆盖正在等待发送的数据。

### 6.3 尾项4 Byte与写反压

沿用单缓冲不能同沿清空/重装的保守方案。假设第一项在E17和E18遇到data_ready=0，在E19握手：

| 上升沿 | 请求/捕获 | 打包项 |
|---|---|---|
| E17～E18 | 不覆盖原pack_buf | 完整D0有效，等待data_ready |
| E19 | 与DMA握手D0 | 本项完成，沿后可准备下一项 |
| E20 | 发出b16读请求 | 尾项开始 |
| E21 | 捕获b16；发b17请求 | lane0←b16 |
| E22 | 捕获b17；发b18请求 | lane1←b17 |
| E23 | 捕获b18；发b19请求 | lane2←b18 |
| E24 | 捕获b19，不再发请求 | lane3←b19；pack_valid沿后为1 |
| E25 | 若DMA ready=1 | 尾项与DMA握手 |

该写DMA事先保存命令长度20，故发送第二项时自身产生WSTRB=16'h000F，只写低4字节；其data_last输入没有被源码使用。最后一个W握手后写DMA还要等B响应，接收最后B后才done；done/error仍不等于对外部系统任意持久化语义的承诺。

## 7. 请求、返回与容量：为什么要跟踪在途读请求

同步读有延迟。即便此刻发现打包缓冲快满，此前已经发出的读请求仍会在之后返回。简单设计为当前pack_buf预留所有已发出请求的位置，并保证：

~~~text
已占用位置 + 已发出但尚未捕获的返回项数
不超过当前打包缓冲能容纳的有效位置数
~~~

对于本讲16 Byte顺序连续读，E0～E15发出16个请求，E1～E16捕获16个返回；停止发请求不等于最后一个返回已经捕获，要在E16排空最后一个在途数据后才置有效。

扩展为更高吞吐时，可用两个128 bit缓冲：一边对DMA保持待发送项，另一边接收下一项；但只有本地SRAM确实能提供足够读带宽，才能真正提高吞吐。增加缓冲也不能让一个8 bit单端口长期超过1 Byte/cycle的供数上限。

## 8. 设计逻辑的实现顺序

这里不是项目现成源码，下面是设计时应建立的控制事件，而非已通过仿真的完整RTL。

1. 命令入口：锁存相同的总长度、本地基地址和外部DMA命令；协调双方共同接受，不让DMA启动而适配器漏接元信息。
2. 读向接收：只有data_valid && data_ready才锁存128 bit和该项有效字节数。
3. 本地写：只有本地写端口实际获得许可、在上升沿提交时才前进本地地址、lane索引和剩余量。
4. 读向完成：独立保存DMA done/error和最后本地写完成，二者满足且无错误才给出可消费tile。
5. 写向请求：保证SRAM有读权限、打包器及在途请求有容量时发请求，记录请求索引。
6. 写向返回：用延迟后的有效与索引捕获同步读返回；收到本项最后一个有效字节后沿后置pack_valid。
7. 写向发送：只在data_valid && data_ready握手后释放当前打包项；反压期间保持数据。
8. 逐项处理边界：20 Byte、16 Byte、1 Byte、0 Byte、端口冲突、AXI反压、错误响应及复位/中断由规格和用户实际实验验证。

示意伪代码：

~~~text
读向接收：
  若 dma_valid 且 adapter_ready：
      beat_buf ← dma_data
      bytes_this ← min(16, bytes_left)
      byte_index ← 0
      buf_valid ← 1

读向落存：
  若 buf_valid 且 sram_write_grant：
      SRAM[dst_addr] ← beat_buf中byte_index对应的Byte
      dst_addr ← dst_addr + 1
      bytes_left ← bytes_left - 1
      若这是当前beat的最后有效Byte：释放缓冲
      若这是本任务最后有效Byte：记录local_write_done

写向打包：
  若有容量，发出SRAM读请求并保存lane索引
  若上周期读请求返回：
      pack_buf[对应lane] ← sram_dout
      若这是本项最后一个有效字节：沿后标记pack_valid
  若pack_valid且dma_data_ready：释放当前打包项
~~~

上面使用“←”表达寄存器或存储状态变化，并没有给出完整可综合RTL；复位、握手优先级、总长度与错误记录需依据实际接口设计。用户要求动手实验时，应由用户分步编写并亲自运行。

## 9. 与Ping-Pong和系统性能的关系

假设装载下一tile：拆包器通过写端口将下一块写入预取Bank；当所有有效字节落存、本次DMA无错误、且Bank可以安全交接时，控制器可认为下一块ready。当前tile计算完成还需要单独的消费完成条件。两个条件满足后才允许切换Bank。

前面tile_buffer原模块中的next_tile_ready是占位行为，不自动验证此协议。本讲定义的done/ready管理是外围方案，不是已经接好的项目行为。

两个Bank可能允许计算与装载并行，但要核对端口、角色、写入带宽、状态和真实顶层接线，不能由“有两个Bank”直接推断一定实现了重叠或性能翻倍。

## 10. 验证范围、停点与下一讲

本讲只阅读固定版本源码并进行了独立时序推导，未改上游RTL、未运行仿真、未生成VCD。E0～E25表是所列假设下的示例；AXI/存储/仲裁实际等待会改变时长。用户尚未确认掌握，优先回答具体问题。

若用户要求继续主线，按原路线进入第08讲ISA/Fetch/Decode/Dispatch，先讲微码怎样控制DMA、GEMM及其他功能单元，核对真实top与仿真路径；不把开放作业的第三题进度混同为主线已学完。

## 来源

- [sram_dp.sv](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/rtl/mem/sram_dp.sv)
- [axi_dma_rd.sv](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/rtl/bus/axi_dma_rd.sv)
- [axi_dma_wr.sv](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/rtl/bus/axi_dma_wr.sv)
- [top.sv](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/rtl/top.sv)
- [onnx_sim_top.sv](https://github.com/harishsg993010/tiny-NPU/blob/8216c22b762011aa20c05fc2768423fd12dda59d/sim/verilator/onnx_sim_top.sv)
- [Arm AMBA AXI协议规范](https://developer.arm.com/-/media/Arm%20Developer%20Community/PDF/IHI0022H_amba_axi_protocol_spec.pdf)
