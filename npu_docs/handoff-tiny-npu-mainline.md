# tiny-NPU项目主线交接

更新：2026-11-10。

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

## 下一步

优先回答用户对本讲的具体问题。若用户要求“下一讲/继续”，进入第07讲下半部分rtl/bus/axi_dma_wr.sv，按硬件结构→变量宽度与单位→数据/控制流→源码顺序与逐拍时序讲解AW/W/B、WSTRB、WLAST、WAIT_BRESP。

然后讲128 bit到8 bit存储适配与安全完成协议，再进入第08讲ISA/Fetch/Decode/Dispatch。不要自动接回课程作业或跳去CIMFlow。

每次完整讲义当次同步Zenia-123/NPU_learing的main/npu_docs，返回真实commit与文件链接。不额外布置练习题。需要实验时由用户亲自编写和运行，未经明确要求不代执行。保留用户代码，不修改上游RTL，除非用户随后明确要求。

