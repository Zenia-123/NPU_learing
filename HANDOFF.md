# tiny-NPU 学习与开放作业交接文档

更新日期：2026-11-10。

**后续教学统一要求：**开始新模块时先讲相关硬件与架构知识、结构、数据流/控制流及适用的指令流，再按源码顺序逐段“先逻辑、后代码”，解释变量含义、位宽、单位及变化时机。完整规范见 [tiny-NPU 硬件与代码讲解要求](npu_docs/TEACHING_GUIDELINES.md)；用户当前具体问题优先。

## 1. 总目标

用户以 tiny-NPU 的真实 RTL 为主线，建立 RTL、数据通路、控制通路与性能建模能力，并完成三道开放作业：多 Bank SRAM 路由、双 Bank Tile Buffer、微码指令读取控制器；后续衔接 CIMFlow、MRAM-CIM 与异构 NPU/PIM 研究。

## 2. 具体对话场景

本节记录开放作业支线；tiny-NPU项目主线独立记录在 `npu_docs/`。用户已明确暂停第一题成稿，并在第二题 Tile Buffer 完成一次本地编译、生成 VCD 后，要求直接开始第三题：**NPU 微码指令读取控制器（`ucode_fetch`）**。

协作方式必须保持：

- 用户亲自写 Verilog-2005、保存文件、执行编译、仿真和 GTKWave；
- Codex 先讲硬件结构、变量/位宽、数据与控制流、逐拍时序；
- 每次只推进一个可验证的小步骤，用户贴出代码或终端输出后再继续；
- 未经用户再次明确要求，Codex 不代替用户运行仿真，也不把参考代码/参考检查说成用户已掌握。

tiny-NPU 项目主线独立保留在 `npu_docs/`：第09讲 Scoreboard 与 Barrier 已讲，随后讨论 GPT-2 微码生成和取指；2026-11-13 用户要求从 C++、Python 零基础逐个学习七个相关文件，已整理代码树及七文件阅读资料，入口 `npu_docs/supplement-gpt2-seven-files-00-code-tree.md`。这是专题答疑，不是第10讲；生成讲义和讲过均不等于用户已掌握。优先逐段回答问题，不默认用户已看完。RTL 时序为源码推导，未运行 RTL 仿真；先前仅 Python 汇编器单独运行检查。详见 `npu_docs/handoff-tiny-npu-mainline.md`；本说明不改变开放作业支线。

## 3. 用户信息

- 集成电路方向研究生；希望从硬件实体和时钟沿行为理解 NPU，而非只记 RTL 语法；
- 偏好中文、细致、按“硬件结构 → 信号语义/位宽 → 数据/控制流 → 时序 → 代码”讲解；
- 代码基础仍在建立中，不能默认已理解 valid/ready、同步 SRAM 延迟、非阻塞赋值、状态保持与握手；
- 希望由自己录入和运行，Codex 负责拆步骤、解释、审查和排错；
- 不要从头重复已学的 GEMM、SRAM、Bank、Buffer 和 Ping-Pong 基础。

## 4. 已完成部分

- [x] tiny-NPU 第 01～06 讲、Ping-Pong 补充，以及第 07 讲上半部分 DMA/AXI 读通路；路径见 `npu_docs/`。
- [x] 第一题 `bank_access_router` 已有规格、RTL、T1～T11 Testbench 和 VCD 资产；这些主要由此前 Codex 代写/代运行形成，不能表述为用户已经亲自完成。
- [x] 第二题完成硬件第一讲和基线协议讲义：
  - `docs/assignment-02-tile-buffer-part-01-hardware.md`
  - `docs/assignment-02-tile-buffer-part-02-rtl-protocol.md`
- [x] 第三题硬件第一讲已完成并保存为 `docs/assignment-03-ucode-fetch-part-01-architecture-flow.md`，覆盖整体硬件框架、两组握手、数据流、控制流、六状态 FSM、反压和结束条件。
- [x] 第二题的 GitHub 参考基线已同步：
  - `assignments/assignment-02-tile-buffer/rtl/tile_buffer.v`
  - `assignments/assignment-02-tile-buffer/tb/tile_buffer_tb.v`
- [x] 用户本地已创建 `assignment/tile_buffer/` 目录、亲自录入 RTL/TB，并将本地 RTL 修正为：复位期间禁止 DMA 写、Bank1 读选择正确、交换清零正确、DMA 完成与 Compute 完成可同拍置位。
- [x] 用户本地已执行完整 `iverilog` 编译；唯一反馈是 `tile_buffer.v` 缺失 ``timescale`` 的警告，之后本地 RTL 已加入 ``timescale 1ns/1ps``。本地存在 `build/tile_buffer_tb.vvp` 与 `waves/tile_buffer_tb.vcd`。

第二题仍**未正式闭环**：用户尚未贴出 `vvp` 的 PASS/FAIL 输出，也未描述 GTKWave 观察结果。因此只能称为“已编译并已生成 VCD，波形结论待确认”；用户本轮主动选择先进入第三题。

## 5. 当前进度

第三题硬件第一讲已完成，讲义为 `docs/assignment-03-ucode-fetch-part-01-architecture-flow.md`。`ucode_fetch` 从 128-bit 微码 SRAM 顺序读取指令，通过 `instr_valid/instr_ready` 向 decode 交付，并用六状态 FSM 处理同步读延迟、下游反压、`OP_END`、`stop` 与程序长度结束。

下一步应先让用户亲自创建 `assignment/ucode_fetch/{rtl,tb,build,waves}` 目录并贴出结果；然后共同固定简化 Verilog-2005 接口和边界，再开始写代码。

第二题的 VCD/结果保留，未来用户要求时从 `vvp` 输出和 GTKWave 信号观察继续，不需要重写代码。

## 6. 用到的资源文件

相对于 `NPU_learing/`：

- 已创建/已修改：
  - `HANDOFF.md`
  - `docs/assignment-02-tile-buffer-part-01-hardware.md`
  - `docs/assignment-02-tile-buffer-part-02-rtl-protocol.md`
  - `docs/assignment-03-ucode-fetch-part-01-architecture-flow.md`
  - `assignments/assignment-02-tile-buffer/rtl/tile_buffer.v`（GitHub 参考基线）
  - `assignments/assignment-02-tile-buffer/tb/tile_buffer_tb.v`（GitHub 参考基线）
  - `npu_docs/README.md`、`npu_docs/lesson-01-*` 至 `lesson-07-dma-axi-read.md`、`npu_docs/handoff-tiny-npu-mainline.md`
- 本地用户工作版（不在该仓库中，且与参考基线存在格式及用户修正差异）：
  - `/home/zenia/aiinfra/assignment/tile_buffer/rtl/tile_buffer.v`
  - `/home/zenia/aiinfra/assignment/tile_buffer/tb/tile_buffer_tb.v`
  - `/home/zenia/aiinfra/assignment/tile_buffer/build/tile_buffer_tb.vvp`
  - `/home/zenia/aiinfra/assignment/tile_buffer/waves/tile_buffer_tb.vcd`
- 第三题参考源（不修改）：
  - `/home/zenia/aiinfra/npu/tiny-NPU/rtl/ctrl/ucode_fetch.sv`
  - `/home/zenia/aiinfra/npu/tiny-NPU/rtl/ctrl/ucode_decode.sv`
  - `/home/zenia/aiinfra/npu/tiny-NPU/rtl/mem/sram_dp.sv`
  - `/home/zenia/aiinfra/npu/tiny-NPU/rtl/top.sv`
  - `/home/zenia/aiinfra/npu/tiny-NPU/rtl/pkg/isa_pkg.sv`
- 待由用户创建：
  - `/home/zenia/aiinfra/assignment/ucode_fetch/rtl/ucode_fetch.v`
  - `/home/zenia/aiinfra/assignment/ucode_fetch/tb/ucode_fetch_tb.v`

## 7. 需要交接的计划

1. 用户亲自创建 `ucode_fetch/{rtl,tb,build,waves}` 目录并贴出目录结果。
2. 共同固定简化版实验规格：指令宽度、指令存储深度、启动/停止、同步读延迟、valid/ready、程序结束和早到 `stop` 的处理。
3. 先画四类周期表，再让用户分段写 Verilog-2005：端口与状态编码、寄存器、组合下一状态、时序寄存器更新。
4. 用户再分段写 Testbench：复位、正常三条指令、Decode 反压、`OP_END`、`stop` 和长度到达。
5. 用户亲自执行 `iverilog -g2005`、`vvp`、GTKWave；Codex 根据真实输出与波形排错。
6. 第三题闭环后，整理报告与 GitHub 同步；若用户要求，回到第二题依据现有 VCD 完成 PASS/FAIL 与波形确认。

新对话只需说明：

> 读取 `Zenia-123/NPU_learing` 的 `HANDOFF.md`，继续第三实验 `ucode_fetch`；先讲硬件结构和逐拍时序，由我亲自写代码和运行命令。


