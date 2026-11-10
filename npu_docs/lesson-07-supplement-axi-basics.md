# 第07讲补充：AXI零基础快速介绍

日期：2026-11-10。

用户明确尚未学习过AXI，因此先补接口协议基础，再继续DMA源码。先前讲过axi_dma_rd不等于已掌握AXI。本文不修改RTL，不运行实验；时序示例是协议说明。

## 1. AXI是什么

AXI全称Advanced eXtensible Interface，是Arm AMBA体系中的一种片上接口协议。它约定芯片内部两个模块怎样发送读写请求、传输数据、等待与返回结果。

在RTL层面，AXI接口由地址线、数据线、控制线以及时钟/复位等信号组成，并受时序规则约束。CPU、DMA、存储控制器等模块按相同规则连接，就能互相访问。

- AXI协议规定“如何通信”；DMA硬件执行“搬多少、从哪里搬、何时继续”。
- AXI并非只能给Arm CPU使用，自研NPU、RISC-V系统与FPGA也可以采用。
- 外部DDR芯片通常通过DDR控制器接入系统；DMA看到AXI接口，DDR控制器处理外部存储器时序。

## 2. 三种常见接口，各自做什么

| 接口 | 核心特点 | 常见用途 |
|---|---|---|
| AXI4 | 按地址读写，支持burst等能力 | DMA访问存储系统、批量搬运权重和激活 |
| AXI4-Lite | 简化的按地址读写，每事务一份数据，无多拍burst | CPU配置启动、地址、长度和状态寄存器 |
| AXI4-Stream | 按顺序传送数据项，无内存地址通道 | 计算模块、DMA流口、图像/音频模块之间传流 |

AXI4-Lite仍有五个通道，数据宽度为32或64 bit；“Lite”不意味着只保留数据线。AXI4-Stream常见TDATA、TVALID、TREADY及按需使用的TLAST/TKEEP等信号；仅看到valid/ready并不能认定某接口完整符合AXI4-Stream。

在tiny-NPU中，top.sv的s_axil_*是控制接口，m_axi_*是DMA访问外部存储系统的接口。axi_dma_rd的内部data_valid/data_ready是简化内部流接口，不直接称为完整AXI4-Stream。

## 3. 谁发起访问：主设备与从设备

主设备（Master，较新术语Manager）发起读写事务，例如CPU或DMA。被访问的从设备（Slave，较新术语Subordinate）接收请求并响应，例如存储控制器或寄存器模块。

这里的角色按接口和事务确定：

- DMA向存储系统读数据时，DMA是主设备。
- 数据从存储系统返回DMA，DMA仍然是主设备。
- 同一个NPU可以同时有供CPU配置的从接口和主动访问存储系统的主接口。

不要把“主设备”等同于“每条线的发送端”。

## 4. AXI4的五个通道

“通道”是承载一类信息的一组信号，不只是单根导线。下表方向指主要信息方向，每条通道还存在反方向的READY反馈。

| 通道 | 名称 | 主要信息方向 | 负责什么 |
|---|---|---|---|
| AR | Read Address，读地址 | 主→从 | 从哪里读、读多少项、每项多大 |
| R | Read Data，读数据 | 从→主 | 返回数据、读响应和burst末项标志 |
| AW | Write Address，写地址 | 主→从 | 写到哪里、写多少项、每项多大 |
| W | Write Data，写数据 | 主→从 | 发送写数据、字节使能和burst末项标志 |
| B | Write Response，写响应 | 从→主 | 反馈写事务响应 |

读使用AR+R；写使用AW+W+B。读状态随R数据返回，因此没有另设“读B通道”。

这些通道有各自的握手，可以在规则允许下独立推进。例如AXI4允许AW地址和W数据在不同周期被接收，没有规定AW必须先于W握手；写B响应必须等写地址和全部写数据都被接收。具体DMA可以主动选择更简单的“先AW再W再等B”实现。

## 5. VALID/READY：一条通道怎样完成一次传输

- 发送端驱动VALID：当前信息有效。
- 接收端驱动READY：当前能够接收。
- 上升沿前VALID和READY同时为1，该上升沿完成一次传输。

$$fire=VALID\land READY.$$

| VALID | READY | 本沿发生什么 |
|---:|---:|---|
| 0 | 0 | 无有效项，无传输 |
| 0 | 1 | 接收端可用，但无有效项 |
| 1 | 0 | 有效项等待，不能算已经传输 |
| 1 | 1 | 完成一次传输 |

遇到VALID=1、READY=0，发送端必须保持VALID以及对应地址/数据/控制信息，直到握手。发送端不能等待READY才肯声明VALID；接收端可以先READY，也可以在看到VALID后再READY。

示例：下表观察每个时钟上升沿前的信号。

| 上升沿 | VALID | READY | 数据 | 本沿结果 |
|---|---:|---:|---|---|
| E0 | 1 | 0 | D0 | D0等待 |
| E1 | 1 | 0 | D0 | 继续等待，内容保持 |
| E2 | 1 | 1 | D0 | 接收D0 |
| E3 | 1 | 1 | D1 | 接收D1 |
| E4 | 0 | 1 | 无有效项 | 无传输 |

五个时钟沿中只有两次成功传输。等待不增加数据项计数；READY低使上游等待，称为反压。

AR通道中主设备发送ARVALID，从设备发送ARREADY。R通道中从设备发送RVALID，主设备发送RREADY。

## 6. 一次读怎样完成

假设主设备希望读取从0x1000开始的数据：

1. 主设备提供ARADDR及其他读控制信息，置ARVALID。
2. ARVALID与ARREADY握手后，从设备接受这次读地址请求。
3. 数据准备好后，从设备提供RDATA、RRESP和RVALID。
4. RVALID与RREADY握手后，主设备接收一项数据。
5. burst有多项时重复数据握手，最后一项带RLAST。

AR握手只说明请求被接受，不代表数据已经返回。AR到R之间没有固定必须隔几拍的要求，访问延迟由系统实现和运行情况决定。

## 7. 一次写怎样完成

按一个便于入门的实现顺序说明：

1. 通过AW通道发送写地址请求。
2. 通过W通道发送写数据；一项数据一次WVALID/WREADY握手。
3. 最后一项带WLAST。
4. 从设备通过B通道提供BRESP和BVALID。
5. BVALID与BREADY握手，主设备接收写响应。

这个顺序便于理解，不能把它误记为AXI强制要求AW先于W。地址和数据独立握手，B响应才需要等待两者满足完成依赖。

“最后一项写数据已被接收”和“写响应已返回”是两件事。BRESP用于表示该写事务的响应，不应被扩展理解为对任意系统的物理持久化保证。

## 8. beat、burst和字节单位

beat表示一份数据的成功传输；burst表示一个地址请求对应的一组数据传输。一个beat可以因等待占用多个时钟周期。

以tiny-NPU默认128 bit AXI数据宽度为例，采用对齐的满宽传输：

$$128\ bit=16\ Byte/beat.$$

从0x1000读取64 Byte，需要4个beat：

| 数据项 | 对应起始字节地址 | 数据量 |
|---|---|---:|
| D0 | 0x1000 | 16 Byte |
| D1 | 0x1010 | 16 Byte |
| D2 | 0x1020 | 16 Byte |
| D3 | 0x1030 | 16 Byte |

INCR burst只通过AR给首地址和控制信息，后续项地址由递增规则确定，不是每个beat都再发一条AR。

相应控制值：

- ARADDR=0x1000：起始字节地址。
- ARLEN=3：拍数减1，所以表示4个beat。
- ARSIZE=4：每beat字节数的log2，即2^4=16 Byte。
- ARBURST=INCR：递增地址。
- 最后一项D3带RLAST=1。

AXI4的INCR burst可支持1～256个beat，但具体硬件可配置更小的上限；tiny-NPU当前默认MAX_BURST_LEN=16。单个burst不能跨4KiB地址边界，跨界DMA任务需要拆分。

RLAST/WLAST表示本次burst最后一项；若一个DMA命令拆成多个burst，它们不直接表示整个DMA命令结束。

## 9. 常见信号速查

| 信号 | 意义 |
|---|---|
| ACLK、ARESETn | 接口时钟、低有效复位 |
| ARADDR/AWADDR | 读/写起始字节地址 |
| ARLEN/AWLEN | 当前burst拍数减1 |
| ARSIZE/AWSIZE | 每拍最大字节数的log2编码 |
| ARBURST/AWBURST | 地址推进类型，如INCR |
| RDATA/WDATA | 读返回数据/待写数据 |
| RLAST/WLAST | 当前burst最后一项数据标志 |
| RRESP/BRESP | 读响应/写响应 |
| WSTRB | 写字节使能，每bit对应一个8 bit字节通道 |
| ARID/AWID、RID/BID | 事务标识，用于关联请求与响应 |
| 各通道VALID/READY | 该通道独立的有效与接收能力握手 |

例如32 bit WDATA有4个字节通道，对应4 bit WSTRB。WSTRB=4'b0011允许写低两个字节，不是只写低两个bit。

## 10. 回到tiny-NPU

在实际文件名和信号名前：

- axi_dma_rd：使用AR、R，负责发起外部读取。
- axi_dma_wr：使用AW、W、B，负责发起外部写入。
- axi_lite_regs：提供CPU配置NPU的寄存器接口。
- m_axi_：从本模块的AXI主接口角度命名。
- s_axil_：从本模块的AXI4-Lite从接口角度命名。

当前应先理解五通道、VALID/READY、读写流程、字节/beat/burst这四组概念。ID、多个未完成事务和更复杂的排序能力可等源码涉及后再展开；不能因为协议支持就认定当前DMA实现了全部能力。

本次停点：AXI快速基础已讲解，尚未由用户确认掌握。优先解答AXI问题，再结合第07讲读DMA讲义复看信号；原计划后续内容仍是axi_dma_wr。没有运行仿真，没有把上表当成实际波形。

## 参考资料

- [Arm：Introduction to AMBA AXI4](https://developer.arm.com/-/media/Arm%20Developer%20Community/PDF/Learn%20the%20Architecture/102202_0100_01_Introduction_to_AMBA_AXI.pdf)：角色、通道、握手、读写事务。
- [Arm：AXI协议规范IHI0022H](https://developer.arm.com/-/media/Arm%20Developer%20Community/PDF/IHI0022H_amba_axi_protocol_spec.pdf)：A3.2握手、A3.4事务结构、B1 AXI4-Lite。
- [Arm：AMBA 4](https://www.arm.com/architecture/system-architectures/amba/amba-4)：AXI4、AXI4-Lite与AXI-Stream。
- [tiny-NPU固定源码版本](https://github.com/harishsg993010/tiny-NPU/tree/8216c22b762011aa20c05fc2768423fd12dda59d)。

教学文档位置：npu_docs/lesson-07-supplement-axi-basics.md。主线交接：[handoff-tiny-npu-mainline.md](handoff-tiny-npu-mainline.md)。
