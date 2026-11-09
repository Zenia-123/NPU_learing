# tiny-NPU开放作业与学习交接文档

更新日期：2026-11-09。

本文件用于让新的Codex对话直接从GitHub接手。接手后无需翻阅旧对话，但必须完整读取本文件，并严格遵守“用户亲自编写和执行、Codex分步教学”的协作方式。

## 1. 总目标

用户希望以tiny-NPU真实RTL为学习主线，完成三道相互独立的开放作业：

1. 组合电路：多Bank SRAM访问路由与冲突仲裁器；
2. 时序电路：双Bank乒乓Tile Buffer；
3. 有限状态机：NPU微码指令读取控制器。

每题都需要完成“题目设计→解题思路→硬件结构与工作原理→Verilog RTL→Testbench→用户亲自运行仿真→GTKWave波形→报告说明”的完整流程。三道作业完成后，再根据用户届时的掌握情况继续tiny-NPU课程，不回到GEMM重复学习。

作业工作根目录：

`/home/zenia/aiinfra/assignment`

tiny-NPU参考源码：

`/home/zenia/aiinfra/npu/tiny-NPU`

阶段讲义和GitHub同步仓库：

`/home/zenia/aiinfra/npu/NPU_learing`

远端仓库为`Zenia-123/NPU_learing`的`main`分支。

## 2. 具体对话场景

### 2.1 当前任务已经切换到第二个实验

用户最新明确要求：暂停第一题后续截图和成稿，**直接进入第二个实验“双Bank乒乓Tile Buffer”**。

第二题参考tiny-NPU固定版本`8216c22b762011aa20c05fc2768423fd12dda59d`中的：

`rtl/mem/tile_buffer.sv`

原模块包含两个存储Bank、`active_bank`角色位、DMA向预取Bank写入、计算侧从活动Bank同步读取，以及`swap`切换。但原代码中的握手逻辑只是占位：

- `next_tile_ready`在每次`swap`时翻转，不能真实表示预取Bank已经装满；
- `tile_done`被固定为0，不能真实表示当前Tile已经读完；
- `swap`没有检查“当前计算完成”和“下一Tile准备完成”，可能过早交换Bank角色。

第二实验要把这些占位行为改造成可解释、可验证的时序协议，同时保持题目聚焦于时序电路，而不是扩展成复杂FSM题。

### 2.2 固定讲解顺序

每个阶段必须按以下顺序讲解：

1. 硬件知识与模块在NPU中的位置；
2. 整体硬件结构；
3. 变量含义、位宽、单位和有效周期；
4. 数据流与控制流；
5. 同拍/跨拍逻辑与时序推导；
6. 用户按顺序亲自写代码；
7. 用户亲自执行编译、仿真和波形操作；
8. Codex根据用户贴出的终端输出或波形现象继续排错。

不能一开始贴完整RTL，也不能把语法逐行翻译代替硬件解释。

### 2.3 最新协作方式：必须由用户执行

用户指出此前Codex代写、代编译和代运行过多。后续必须遵守：

- Codex说明当前步骤的目的；
- Codex给出这一小步需要写的代码结构或终端命令；
- 用户在VS Code中亲自编写、保存并执行；
- 用户把代码片段、终端输出或波形现象发回；
- Codex检查后才进入下一步；
- 未经用户明确要求，Codex不得代替用户运行实验、直接完成整份RTL/Testbench或宣称用户已经掌握；
- 可以读取项目源码、解释硬件、审查用户代码和维护交接/阶段Markdown；
- 每次只推进一个可验证的小步骤，不提前跑完后续实验。

第二实验的第一轮回复应先完整讲硬件结构和逐拍行为，不要立即创建文件或执行命令。讲完并确认理解后，再让用户亲自执行目录创建命令。

### 2.4 作业语言与同步要求

- 作业RTL使用Verilog-2005，文件后缀为`.v`；
- 编译使用`iverilog -g2005`；
- Testbench和RTL都由用户亲自运行；
- 每个完整讲解阶段保存为Markdown并同步到`Zenia-123/NPU_learing`，报告真实commit；
- `/home/zenia/aiinfra/assignment`是本机工作版；
- `NPU_learing/assignments`只保存完成阶段的GitHub同步副本；
- 不修改或提交上游`tiny-NPU`中的用户GEMM改动。

## 3. 用户信息

- 用户是集成电路方向研究生，希望通过tiny-NPU建立RTL、数据通路、控制通路和性能建模能力，后续衔接CIMFlow以及MRAM/异构NPU与PIM研究。
- 代码基础相对薄弱，偏好中文、细致、从硬件实体和逐拍行为出发的讲解。
- 不要默认用户已理解valid/ready、Bank角色、同步读延迟、完成标志、握手或非阻塞赋值。
- 用户希望“带着独立写”，不是接收一份已经完成的答案。
- 用户不希望重复已完成的GEMM、SRAM、Bank、Buffer和Ping-Pong基础课程；第二题应在这些基础上进入具体硬件设计。
- 用户要求讲解顺序始终是“硬件结构→变量含义与单位→数据/控制流→代码顺序与时序”。
- 用户要求知道RTL和Testbench写完之后每一步做什么，因此必须解释保存、编译、运行、VCD生成、GTKWave观察、截图和报告整理的完整流程。
- 用户接受先暂停第一题成稿，当前优先进入第二实验。

## 4. 已完成部分

### 4.1 已完成的tiny-NPU学习内容

- [x] 整体架构：`docs/lesson-01-overview.md`
- [x] RTL与INT8 MAC：`docs/lesson-02-rtl-mac.md`
- [x] PE微结构：`docs/lesson-03-pe-microarchitecture.md`
- [x] 脉动阵列：`docs/lesson-04-systolic-array.md`
- [x] GEMM与`gemm_post`：`docs/lesson-05-*`
- [x] SRAM、Bank与Buffer：`docs/lesson-06-sram-bank-buffer.md`
- [x] Ping-Pong补充：`docs/lesson-06-supplement-ping-pong-pipeline.md`

以上课程不应从头重讲。第二题只在需要时引用关键结论。

### 4.2 第一实验已有资产

第一题模块为`bank_access_router`。仓库中已经存在：

- [x] 设计规格与T1～T11计划；
- [x] Verilog-2005 RTL；
- [x] 基础smoke Testbench；
- [x] T1～T11 Testbench；
- [x] VCD波形；
- [x] 相关讲义和运行记录。

关键文件：

- `docs/assignment-01-bank-router-part-01-spec.md`
- `docs/assignment-01-bank-router-part-04-verilog-migration.md`
- `docs/assignment-01-bank-router-part-05-t11-waveform.md`
- `assignments/assignment-01-bank-router/rtl/bank_access_router.v`
- `assignments/assignment-01-bank-router/tb/bank_access_router_t11_tb.v`
- `assignments/assignment-01-bank-router/waves/bank_router_t11.vcd`

必须准确描述第一题状态：

- 这些文件和11/11结果主要由此前Codex代写、代运行形成；
- 用户随后明确表示实验应由自己执行；
- 因此不能把这些资产表述为用户已经亲自完成或已经完全掌握；
- 用户本轮选择暂不继续第一题GTKWave截图和Word成稿，直接进入第二实验；
- 第一题文件保留，未来如用户要求再按“用户亲自操作”的方式补完。

### 4.3 已完成的环境准备

本机已经确认存在：

- Icarus Verilog 11.0；
- `vvp`；
- GTKWave 3.3.104；
- VS Code；
- Verilog HDL扩展。

第一题工作版位于`/home/zenia/aiinfra/assignment/bank_router`。不要删除其RTL、Testbench、build或waves文件。

### 4.4 第二实验尚未完成

截至本交接文档：

- [ ] 尚未创建`/home/zenia/aiinfra/assignment/tile_buffer`实验目录；
- [ ] 尚未由用户定义第二题最终端口和安全交换协议；
- [ ] 尚未由用户编写Verilog RTL；
- [ ] 尚未由用户编写Testbench；
- [ ] 尚未由用户执行编译、仿真或GTKWave；
- [x] 第二题硬件第一讲已完成并保存为`docs/assignment-02-tile-buffer-part-01-hardware.md`，覆盖结构、变量、数据/控制流、逐沿读返回、安全交换与启动边界。
- [ ] 用户尚未反馈目录创建输出，参数、端口与最终协议尚未共同确认。

不要声称用户已开始第二实验编码或验证。助手在本执行环境曾进行参考实现/检查，但它们未作为用户实验资产发布，也不计入用户进度；不得以此跳过用户的亲自编写和执行。

## 5. 当前进度

第二题第一讲“硬件结构与逐沿时序”已完成，讲义：

`docs/assignment-02-tile-buffer-part-01-hardware.md`

当前等待用户在自己的终端创建目录并反馈输出，不能代执行或提前给出完整RTL。

```bash
cd /home/zenia/aiinfra/assignment
mkdir -p tile_buffer/rtl tile_buffer/tb tile_buffer/build tile_buffer/waves
pwd
find tile_buffer -maxdepth 2 -type d
```

收到输出后，下一步只共同确定参数、端口和访问/交换协议：

- 每Bank深度、数据宽度、tile是否固定大小；
- 是否要求按顺序写/读一次，还是支持乱序/重复访问；
- 写满如何证明：计数、外部完成或地址覆盖记录；
- 最后读请求与最后返回接收如何对齐；
- 是否增加读返回valid、请求ready、当前tile有效状态；
- 首次启动无当前tile时怎样允许第一次交换；
- 过早swap如何处理，成功交换沿是否接受读写；
- 交换后准备/完成标志如何清除。

本篇用E0/E1明确同步读：E0采样请求，E0沿后输出寄存器更新，下游时序逻辑在E1捕获，避免“再额外加一拍”的歧义。最终tile_done的置位依据仍需共同选定。

下一步用户还没写任何第二题RTL，不默认已经理解全部内容。第三题、DMA/AXI与第一题成稿都不自动提前启动。

## 6. 用到的资源文件

以下路径相对于`/home/zenia/aiinfra/npu/NPU_learing`。

### 6.1 已创建或已修改

- `HANDOFF.md`：本交接文档；
- `docs/assignment-02-tile-buffer-part-01-hardware.md`：第二题硬件第一讲；
- `docs/assignment-01-bank-router-part-01-spec.md`：第一题规格；
- `docs/assignment-01-bank-router-part-02-rtl-foundation.md`：第一题地址前端；
- `docs/assignment-01-bank-router-part-03-arbitration.md`：第一题仲裁；
- `docs/assignment-01-bank-router-part-04-verilog-migration.md`：Verilog迁移；
- `docs/assignment-01-bank-router-part-05-t11-waveform.md`：第一题命令、错误和波形；
- `docs/setup-vscode-verilog-environment.md`：环境指南；
- `assignments/assignment-01-bank-router/`：第一题GitHub同步资产。

### 6.2 外部参考文件

以下文件不在`NPU_learing`仓库中：

- tiny-NPU参考：`/home/zenia/aiinfra/npu/tiny-NPU/rtl/mem/tile_buffer.sv`；
- tiny-NPU SRAM参考：`/home/zenia/aiinfra/npu/tiny-NPU/rtl/mem/sram_dp.sv`；
- 用户作业根目录：`/home/zenia/aiinfra/assignment`；
- 第一题工作目录：`/home/zenia/aiinfra/assignment/bank_router`；
- 正式Word模板：`/home/zenia/Downloads/数字大规模集成电路-开放作业-学号-姓名.docx`；
- Word锁文件`/home/zenia/Downloads/.~大规模集成电路-开放作业-学号-姓名.docx`只有162字节，不能当模板正文。

### 6.3 第二题需由用户继续创建

相对于`/home/zenia/aiinfra/assignment`：

- `tile_buffer/rtl/tile_buffer.v`：尚未创建，用户分阶段编写；
- `tile_buffer/tb/tile_buffer_tb.v`：尚未创建，用户在RTL之后编写；
- `tile_buffer/build/`：保存用户编译出的`.vvp`；
- `tile_buffer/waves/`：保存用户运行生成的VCD；
- `docs/assignment-02-*.md`：完整阶段后由Codex整理并同步GitHub。

## 7. 需要交接的计划

1. **第二题硬件第一讲（已完成）**：见`docs/assignment-02-tile-buffer-part-01-hardware.md`；用户尚未确认全部理解。
2. **用户创建目录（当前等待）**：命令已给出，等用户贴出pwd与find结果；Codex不代执行。
3. **共同定义需求**：逐项确定默认Bank深度、数据宽度、端口、完成条件、早到swap如何处理、交换后标志如何清除。
4. **画周期表**：至少推导“DMA写满→下一Tile就绪”“最后一次计算读请求→数据返回→tile_done”“双方完成→安全交换”三个时间序列。
5. **用户写RTL骨架**：先参数和端口，再存储Bank与状态寄存器；用户每写完一段，Codex只审查当前段。
6. **用户写时序逻辑**：依次完成复位、DMA写、同步读、完成标志和安全交换，不一次给整份代码。
7. **用户亲自编译**：Codex给出`iverilog -g2005`命令，等待用户贴输出后再排错。
8. **用户写Testbench**：先时钟/复位，再写入、读取、一拍延迟、早到swap、安全swap和连续两轮Tile测试。
9. **用户亲自仿真和看波形**：给出`vvp`、VCD与GTKWave操作，由用户执行并描述结果。
10. **第二题成稿**：整理题目、思路、硬件结构、RTL、Testbench和用户实际得到的波形。
11. **第三题**：第二题由用户完成后再进入`ucode_fetch` FSM。
12. **恢复tiny-NPU学习**：三道作业全部完成后再决定下一讲。

新对话只需执行这条接手指令：

**“读取GitHub仓库`Zenia-123/NPU_learing`的`HANDOFF.md`继续第二实验；硬件第一讲已讲，当前等待我反馈目录创建结果，再一起定义规格和端口，由我亲自写代码和运行。”**
