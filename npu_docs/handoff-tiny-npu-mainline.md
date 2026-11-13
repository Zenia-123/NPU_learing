# tiny-NPU项目主线交接

更新：2026-11-11。

**长期教学规范：**继续项目主线前先读取 [硬件与代码讲解要求](TEACHING_GUIDELINES.md)。新模块先讲硬件/架构、结构、数据流/控制流及适用的指令流；源码按文件顺序逐段先讲逻辑再讲代码，解释变量含义、作用、位宽、单位和时序。用户当前具体问题优先，既有学习与作业进度不因此重置。

## 对话范围、目录与优先级

用户最新指令：“这个对话回到tiny-npu项目本身，按照之前的计划，继续开展学习。”

本文件记录项目主线，根目录HANDOFF.md是两条学习线的共同入口。用户已明确恢复tiny-NPU项目学习，并要求新建npu_docs专门保存tiny-NPU讲解；主线不等待作业支线结束。

- npu_docs/：tiny-NPU主线讲义、补充、复习、学习指南与历史交接。
- docs/assignment-*.md：课程作业讲义，保持原路径与内容。
- assignments/：作业RTL、Testbench、日志和波形同步副本，保持不动。
- docs/setup-vscode-verilog-environment.md：既有环境指南，保持不动。

本次把第01～06讲及相关资料迁入npu_docs，加入第07讲上半部分。用户已明确授权本次提交到main。后续主线讲义均写入npu_docs，不混入assignment材料。

## 已讲解范围

第01～06讲及Ping-Pong补充均已讲解；已讲解不等于用户确认完全掌握。不要重新从MAC、GEMM、SRAM或Ping-Pong入门开始。

2026-11-09已继续第07讲上半部分：
npu_docs/lesson-07-dma-axi-read.md。

本讲内容：DMA位置、AXI五通道、VALID/READY、byte/beat/burst单位、axi_dma_rd控制/数据通路、burst上限与4KiB拆分、默认128 bit配置、五状态FSM、真实末拍到done的额外CALC周期、反压与逐拍推导、128 bit输出到8 bit SRAM的接口边界。

## 必须保留的源码事实

- 固定参考版本：harishsg993010/tiny-NPU commit 8216c22b762011aa20c05fc2768423fd12dda59d。
- axi_types_pkg定义在rtl/bus/axi_types.sv。
- axi_dma_rd一次只允许一个burst未完成，内部无数据FIFO。
- data_out直接接RDATA，RREADY受data_ready控制，成功握手才推进地址与计数。
- RLAST指burst末拍，data_last指整个命令末项，done是控制完成状态。
- 正常最后一个beat沿前bytes_remaining尚非0，走RECV→CALC→DONE，不能画成沿后立即done。
- 读流没有data_keep，也没有本地目的地址或SRAM写口。
- rtl/top.sv的读流data_ready恒1仍是占位，写DMA数据valid为0；不能声称DDR↔SRAM完整接通。
- onnx_sim_top.sv使用DMA Shim向C++暴露命令，没有实例化两个AXI DMA。
- 有适配缓冲时，读DMA done可能早于最后字节真正落入SRAM，不能无条件等同next_tile_ready。
- 本讲未修改RTL、未运行HDL仿真、无VCD；逐拍表是源码推导。

## 当前基础补充停点

2026-11-10用户明确“没有学过AXI”，要求先快速介绍AXI及其具体内容。已补充：
npu_docs/lesson-07-supplement-axi-basics.md。

内容为AXI用途、AXI4/Lite/Stream区别、主从角色、五通道、VALID/READY、读写事务、byte/beat/burst及tiny-NPU信号对应。快速介绍不等于掌握，不能默认用户已理解握手、burst或各通道的独立性。优先回答AXI基础问题，再回到DMA源码；原计划后续仍为axi_dma_wr。未运行仿真，示例表为协议说明。

## 2026-11-10项目主线新停点

用户说“继续讲解”，按既定计划已讲第07讲下：npu_docs/lesson-07-dma-axi-write.md。按硬件、变量、数据/控制、源码顺序和逐拍时序解释axi_dma_wr、AW/W/B、WSTRB、WLAST、B响应、错误及顶层占位。用户尚未确认理解，优先答疑。未做仿真或修改上游RTL。

写DMA重要事实：最后W握手进入WAIT_BRESP，最后B握手后直接DONE；data_last输入未使用，WLAST由beat_cnt和burst_len产生；没有内部FIFO，等待时数据稳定依赖上游；非零写命令在固定版本top.sv中因data_valid恒0，AW后停在SEND_WDATA；BID未校验、error端口未接顶层。默认对齐20 Byte例尾拍WSTRB=16'h000F。

## 2026-11-10位宽适配课程停点

用户要求“继续学习”，按既定计划讲解npu_docs/lesson-07-sram-axi-width-adapter.md：8 bit SRAM与128 bit AXI的拆包/打包、20 Byte尾项、valid/ready反压、同步SRAM读请求与下一沿捕获、in-flight容量、DMA done和本地落存/ready的区别。适配器是教学设计方案，固定版本top并未完整实现；没有修改RTL或运行仿真。用户尚未确认掌握，优先答疑。

读向单缓冲示例E0接收首beat、E1～E16写16 Byte、E17接收尾beat、E18～E21写尾4 Byte；最后R握手后读DMA在E18沿后done，本地E21才写完，必须保存done/error并等待本地提交。写向E0发SRAM读、E1捕获首Byte、E16捕获第16个并沿后置valid，最早E17握手；尾4 Byte由写DMA生成WSTRB=000F。时序仅是明确假设下的推导，不能当作实测。

## 2026-11-10 当前用户要求：按源码精读axi_dma_rd

用户明确要求“按照程序顺序，先讲清楚逻辑再讲清楚代码”，并补充“说明变量的含义作用”。最新讲义：npu_docs/lesson-07-axi-dma-rd-code-walkthrough.md。分端口、内部寄存器和组合量逐项给出位宽、单位、作用、变化时机，按模块头→常数→状态→burst计算→下一状态→状态寄存器→数据通路→AR/R输出→状态输出逐段精读；贯穿对齐20 Byte、RLAST反压与4KiB边界算例。未运行仿真；用户尚未确认掌握，先回答该模块的后续问题。

注意beat_cnt、total_beats和beats_done虽然维护，但本源码未用它们判定状态或核验RLAST；RLAST/RID没有交叉检查。最终beat沿前剩余量非零，正常经CALC再DONE；data_last在ready=0时可为1但并未交付；尾部没有keep且可能多读；错误粘滞至下一命令；top读流仍是占位。

这次为用户主动要求回读第07讲，不删除已有第08讲fetch进度；若用户以后明确要求下一讲并且本模块疑问已解决，原有第08讲后续建议为Decode/Dispatch与Scoreboard。作业支线保持独立。

## 2026-11-11 当前用户问题：axi_dma_wr源码顺序精读

用户主动要求“讲解一下axi_dma_wr”，按照npu_docs/TEACHING_GUIDELINES.md讲解硬件、数据/控制与适用的指令路径，再按真实文件顺序每段先讲逻辑再讲代码和变量。最新讲义：npu_docs/lesson-07-axi-dma-wr-code-walkthrough.md。覆盖全部端口、内部组合/时序量的含义、位宽、单位与更新时机，按声明→常数→状态/寄存器→burst拆分→WSTRB→下一状态→寄存器→AW/W/B/状态输出顺序，采用20 Byte与4KiB边界具体例子。

时序是源码推导，未运行仿真。最后W握手进入WAIT_BRESP、最后B握手后直接DONE；20 Byte尾项WSTRB=000F；WLAST每burst一次；data_last未使用、BID未核验；上游必须在反压时保持valid和数据。固定版本top的写数据端为占位，模块error未接到顶层npu_error。用户尚未确认掌握，优先回答具体问题，保留已讲第08讲fetch和独立作业进度。

## 下一步

优先回答用户对Scoreboard、Barrier及之前模块的具体问题；已讲解不等于已掌握。用户要求下一讲时，依据当时理解与学习指南选择后续模块。课程作业支线保持独立。

每次完整讲义当次同步Zenia-123/NPU_learing的main/npu_docs，返回真实commit与文件链接。不额外布置练习题。需要实验时由用户亲自编写和运行，未经明确要求不代执行。保留用户代码，不修改上游RTL，除非用户随后明确要求。


## 2026-11-10 第08讲上半停点

用户要求下一步，已讲并同步 `npu_docs/lesson-08-ucode-fetch.md`：128 bit 微码字段、指令 SRAM 与按词计数的 pc/base/len、fetch 六状态、valid/ready 反压、同步 SRAM 沿后读数与下一沿捕获、源码逐段及正常/结束时序。用户尚未确认掌握，优先答疑；下一讲 Decode/Dispatch 与 Scoreboard。固定参考版本不变，未修改上游 RTL、未运行 HDL 仿真，时序为代码推导。

关键边界：OP_END 在 WAIT_DATA 直接去 DONE，不向 Decode 交接；DONE 状态下产生 done_d，下一沿返回 IDLE 时 done_q=1 且 busy=0；len=0 仍会先发读请求；stop 不屏蔽 FETCH 的 rd_en 或 DISPATCH 的 instr_valid，stop 与 ready 同拍可能仍握手；top 的 stop 固定 0、指令 SRAM 写端关闭、Fetch base 置 0；top 的 16 位 fetch 地址实际 SRAM 默认 1024 深度只用低 10 位。

## 2026-11-12 第08讲下半：Decode / Dispatch

用户要求下一讲，已讲并同步 `npu_docs/lesson-08-ucode-decode-dispatch.md`：硬件结构、128 bit 指令拆字段、端口/寄存器位宽、opcode目标映射、D_IDLE/D_DECODE/D_BARRIER、发射与busy登记时序、Scoreboard与Barrier、引擎命令输出路由，以及正常/阻塞/屏障逐沿表。用户尚未确认掌握，优先答疑；后续可深入Scoreboard及Barrier，或按用户新问题继续。固定源码8216c22，未修改上游RTL、未运行仿真，逐拍表为推导。独立作业线保持原状。

关键：Decode DMA长度输出由N字段取得，README表格提到M，与实际RTL有差异；Fetch拦截END导致Decode END分支在此路径通常不可达；固定top计算引擎为stub，barrier_stall未反馈Decode，屏障等待由D_BARRIER检查all_idle实现。正常指令E0握手沿后cmd_valid/issue有效，E1沿Scoreboard采样并置busy；scoreboard同引擎done与issue同拍时RTL最终清零优先。top仅管理6个引擎，6/7 can_issue补1但RMSNorm/RoPE输出未接；注意用户不可误认为完整系统已经实现。


## 2026-11-12 第09讲：Scoreboard 与 Barrier

用户要求下一讲，已讲并同步 `npu_docs/lesson-09-scoreboard-barrier.md`：以固定版本源码为准，先介绍引擎忙闲、跨引擎依赖、屏障数据/控制/指令流，再按 scoreboard.sv 与 barrier.sv 源码顺序解释变量、组合与寄存器、状态机、顶层接线和逐沿时序。用户尚未确认掌握，优先答疑；未修改上游RTL，未运行仿真，时序为静态推导。作业支线保持独立。

关键事实：每引擎1个busy位并不跟踪内存地址或自动检查数据依赖；6个bit对应GEMM、Softmax、LayerNorm、GELU、Vec及DMA读写合并；同bit issue和done同时出现时最终清零优先，接口没有自动补发；can_issue取busy_q取反，没有done组合旁路。Decode发射通知与引擎实际ready握手不能等同。独立barrier输出寄存stall/done，但固定top没有将barrier_stall接回Fetch/Decode，实际等待由Decode自己的D_BARRIER加all_idle完成。前五引擎是计时stub，不能声称当前top完整计算。完成沿观察旧all_idle，等待逻辑需后续沿才响应；6/7补1但对应输出未接、不受6位scoreboard管理。异常同拍与功能是否可达需明确假设，不视为实测。

## 2026-11-12 LLM 微码产生和加载答疑

用户追问微码从哪来、软件如何与硬件连接；已基于固定版 8216c22 深入解释并提交 `npu_docs/supplement-llm-microcode-generation-loading.md`。真实 GPT-2 block 测试采用 C++ 的 load_microcode→encode_instr→ucode_write→tick，写 gpt2_block_top 指令 SRAM B 口；不依赖 Python 汇编器生成的文件。例子 Q头 M=8 N=16 K=64，h0 hi=0901_0040_0010_0008、lo=0000_C400_C800_0403。Fetch SRAM A口读、Decode依ISA拆字段。gpt2顶层 program_end 等 fetch_done latch 和 all_idle，DMA由测试C++ shim处理，RTL top不同且微码写端关闭；CMake目标将SRAM0深度覆盖为65536。

Python ucode_asm.py parse_line 将 key lower 而字段字典 M/N/K 大写，因此文本 M/N/K被静默忽略默认0，gen-tiny也经assemble；其hex每条4行32-bit，不自动适配128-bit SRAM一行一词。均为静态源码分析，未运行仿真或修改上游。答疑不改变课程主线/作业进度；用户未确认掌握，优先解答相关问题。



## 2026-11-13 GPT-2 微码端到端路径专题

用户要求从零基础沿 tb_gpt2_block.cpp → gpt2_block_top.sv → ucode_fetch.sv 阅读，讲模型到指令、C++/Python 语法及独立汇编器，并统计相关代码规模。专题讲义 `npu_docs/supplement-gpt2-ucode-end-to-end-walkthrough.md`；不将专题记为第10讲，已讲不等于掌握，优先回答具体问题。C++ 手工展开并静态推得117条指令，随机数据，不是预训练模型图的自动编译，不调用 Python。该 GPT-2 专用仿真顶层有真实计算引擎 RTL 和由 C++ 服务的 DMA shim，不应套用另一顶层的 stub 判断。Python 汇编器实测 M/N/K 被静默清零，默认模板 59 条、944 字节；这只是 Python 验证，未运行 RTL 仿真，RTL 时序为静态推导。gpt2_block_sim CMake 显式列 34 个源文件共 10528 物理行，但实例化的 gemm_ctrl.sv（761 行）未在显式清单，是否经搜索路径找到尚未构建验证。开放作业支线保持不变。
