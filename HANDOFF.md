# tiny-NPU学习与开放作业交接文档

更新日期：2026-11-09。

本文件用于让新的Codex对话直接从GitHub接手，不需要读取旧聊天记录。接手后应先完整读取本文件，再读取“当前进度”指定的讲义，不要重新选题或从GEMM开头复习。

## 1. 总目标

用户希望以tiny-NPU真实RTL为学习主线，完成《数字大规模集成电路：设计与实践》开放作业的三道独立题目，分别对应组合电路、时序电路和有限状态机。每道题都要完成“题目设计→解题思路→硬件结构与工作原理→RTL代码→Testbench→实际仿真→波形解释”的完整流程，同时借此继续理解NPU的存储系统、数据通路和控制通路。

最终作业要符合学校模板的电路类型、代码工作量、边界条件、注释、状态图和波形说明要求；学习过程中的每次完整讲解继续保存为Markdown，并在当次推送到`Zenia-123/NPU_learing`仓库`main`分支，报告真实commit。

## 2. 具体对话场景

此前用户已经系统学习tiny-NPU的INT8 MAC、PE、脉动阵列、GEMM控制器、`gemm_post`、SRAM、Bank、Buffer和Ping-Pong双缓冲。现在的任务不是继续精读GEMM，而是把NPU模块改造成三道课程作业，并由Codex带着用户逐步完成设计、代码和验证。

### 2.1 后续讲解的固定顺序

用户最新明确要求，后续每个模块必须按照以下顺序推进：

1. **硬件知识与模块位置**：先说明该模块解决什么硬件问题，在NPU中的位置，以及它与上游、下游、存储体和控制器的关系。
2. **整体硬件结构**：画出或文字说明实际需要哪些组合逻辑、寄存器、存储体、仲裁器、多路器和接口。
3. **变量含义与单位**：逐项说明信号宽度、物理意义、地址单位、数据单位、有效周期和生命周期。
4. **数据流与控制流**：分别讲数据从哪里来、到哪里去，以及控制条件如何决定路由、等待、授权或状态转移。
5. **逻辑分析**：推导地址映射、边界条件、优先级、握手或状态跳转，明确同拍和跨拍行为。
6. **带着用户写代码**：按模块声明、参数、端口、中间信号、核心逻辑的顺序逐段写，不要一开始只扔出完整答案。
7. **给出可运行代码并验证**：形成完整RTL和Testbench，实际运行Icarus Verilog，生成VCD，用GTKWave或等效方式检查波形，并写波形解释。

讲解需坚持“硬件结构→变量含义与单位→数据/控制流→代码顺序与时序”。不能只做语法翻译，也不能在没有解释硬件的情况下直接贴代码。

### 2.2 三道题最终选型

已经确定选题，不要重新比较或改回GEMM：

| 作业类型 | 题目 | tiny-NPU来源 | 主要学习内容 |
|---|---|---|---|
| 组合电路 | 多Bank SRAM访问路由与冲突仲裁器 | `rtl/mem/banked_sram.sv`的Bank选择思想 | 地址交织、Bank匹配、并行路由、固定优先级、冲突与阻塞 |
| 时序电路 | 双Bank乒乓Tile Buffer | `rtl/mem/tile_buffer.sv` | 存储阵列、同步读写、一拍读延迟、Bank角色寄存器、安全切换 |
| 有限状态机 | NPU微码指令读取控制器 | `rtl/ctrl/ucode_fetch.sv` | 指令SRAM读取、PC、读延迟、valid/ready反压、六状态FSM |

用户明确要求先不写GEMM部分，因为GEMM已经学习过。不要把`gemm_ctrl`、`gemm_post`、PE或脉动阵列选为这三道作业。

### 2.3 学校模板的硬要求

正式附件是`数字大规模集成电路-开放作业-学号-姓名.docx`；名称以`.~`开头的162字节文件只是Word临时锁文件，不能作为模板正文。

三题共同要求：

- 每题独立完成题目描述、解题思路、RTL、Testbench和仿真波形；
- RTL与Testbench核心代码需要注释；
- 波形图必须有文字解释；
- 推荐ModelSim或Icarus Verilog；
- 用户已说明不用让“禁止抄袭”条款影响选题，可以直接以项目模块为主线。

组合电路题：

- 必须有实际应用场景；
- 不能只是简单算术、4位及以上编码/译码、数值比较器、多路选择/分配器或简单布尔函数；
- RTL不少于60行；
- 至少2个中间逻辑信号；
- 必须考虑边界条件。

时序电路题：

- 核心是存储或时序控制；
- 不能只是寄存器、计数器或锁存器；
- RTL不少于80行；
- 包含时钟边沿、复位和至少一个控制信号；
- 需要考虑时序稳定性。

有限状态机题：

- Moore或Mealy均可；
- 状态不少于4个；
- RTL不少于120行；
- 必须有多输入条件状态转移，避免冗余和死锁；
- 解题思路中必须画状态转移图。

## 3. 用户信息

- 用户是集成电路方向研究生，希望通过tiny-NPU建立RTL、数据通路、控制和性能建模能力，后续衔接CIMFlow及MRAM/异构NPU与PIM研究。
- 代码基础相对薄弱，需要中文、细致、从硬件实体和逐拍行为出发讲解，不要默认已经理解buffer、Bank、valid、归约、计数器或握手等术语。
- 用户接受单次较多内容，但不希望反复从头讲，也不需要额外布置练习题。
- 用户希望“带着独立写”：先理解并逐段构建，最后仍要给出完整、可运行、经过验证的代码。
- 用户要求每次完整课程或作业阶段的Markdown当次同步到GitHub，并给出真实commit，不接受只声称已经上传。
- 用户本轮明确补充：后续先讲硬件知识、整体硬件结构、数据流和控制流，再分析逻辑、带写并给出代码。

## 4. 已完成部分

### 4.1 已完成的tiny-NPU课程

- [x] 第01讲：整体架构，`docs/lesson-01-overview.md`。
- [x] 第02讲：RTL与INT8 MAC，`docs/lesson-02-rtl-mac.md`。
- [x] 第03讲：PE微结构，`docs/lesson-03-pe-microarchitecture.md`。
- [x] 第04讲：脉动阵列与周期级数据流，`docs/lesson-04-systolic-array.md`。
- [x] 第05讲：GEMM源码、控制器设计方法和后处理，见三个`lesson-05-*`文件。
- [x] 第06讲：SRAM、Bank与Buffer，`docs/lesson-06-sram-bank-buffer.md`。
- [x] Ping-Pong补充：`docs/lesson-06-supplement-ping-pong-pipeline.md`。

不要重复上述课程。尤其不要重新讲SRAM的基本同步读写、Bank概念或Ping-Pong入门；作业讲解应引用这些基础后进入新设计。

### 4.2 已完成的作业准备

- [x] 已读取并核对9页正式Word作业模板。
- [x] 已比较tiny-NPU中的组合、时序和FSM候选模块。
- [x] 已确定三道题为Bank路由仲裁器、Tile Buffer和`ucode_fetch`。
- [x] 已确认本机安装`Icarus Verilog 11.0`、`vvp`和`GTKWave`。
- [x] 已完成第一题的需求、硬件结构、端口、中间信号、仲裁规则、边界条件和11项Testbench验证计划：`docs/assignment-01-bank-router-part-01-spec.md`。
- [x] 第一题RTL基础讲义、94行阶段RTL与真实编译记录已完成；本次同步提交一并更新本交接文档。
- [x] 第一题规格讲义已提交并推送，commit为`fe623b1d9f877856af5e50b6f9ab88d2bd6e5167`，远端`main`已核验指向该提交。

### 4.3 第一题已经固定的设计决定

- 作业模块名：`bank_access_router`。
- 纯组合电路，不含`clk`、复位、寄存器、锁存器和真正的SRAM数组。
- 4个请求者、4个单端口Bank、每Bank深度16 word、每word 8 bit。
- 全局地址宽度8 bit，但合法全局word地址只有0～63，地址64是首个越界值。
- 低位交织：`bank_id = global_addr[1:0]`，`local_addr = global_addr >> 2`。
- 每Bank独立固定优先级：`req0 > req1 > req2 > req3`。
- 地址合法且获胜输出`grant`；合法但同Bank竞争失败输出`stall`；越界输出`error`。
- 计划使用扁平打包端口，如`req_addr_flat`和`bank_addr_flat`，在模块内部切片。
- 每Bank输出`en/we/local_addr/wdata/owner/conflict`。
- 这是受`banked_sram`启发的教学扩展，不是把原`banked_sram`原样复制为组合题。

第一题RTL基础阶段已完成：新增模块框架、接口、默认赋值、输入拆包、完整地址检查、地址拆分与错误反馈。当前`match`和仲裁临时量仅清零，`req_grant/req_stall`及所有Bank输出仍为0，不能作为完整路由器使用。

已使用Icarus Verilog 12.0执行`iverilog -g2012 -Wall -s bank_access_router`语法与默认参数展开检查，退出码0；有4条`always_comb`常量取位敏感范围提示，详见编译记录。尚未创建Testbench或VCD，尚未运行功能仿真、综合或时序分析。不要把编译通过误报为仲裁功能验证通过。

## 5. 当前进度

当前已完成第一题第二篇“RTL基础与地址前端”，下一步是第一题仲裁核心，不要重写已完成的接口和地址前端，也不要直接进入第二题。

接手时先读：

1. `docs/assignment-01-bank-router-part-01-spec.md`。
2. `docs/assignment-01-bank-router-part-02-rtl-foundation.md`。
3. `assignments/assignment-01-bank-router/rtl/bank_access_router.sv`。
4. `assignments/assignment-01-bank-router/checks/rtl-foundation-compile.txt`。

本阶段源码共94行，已实现参数、扁平端口、派生常量、内部拆包数组、完整组合默认赋值、地址合法性比较、地址拆分与`req_error`。仅编译核验默认4请求/4Bank/每Bank16word/8bit数据/8bit全局地址配置。

特别注意：地址64右移2位数学结果为16，但截成4bit局部信号后变为0。因此不能用截断后局部地址代替完整8bit地址的合法性判断。

下一阶段必须按硬件到代码的顺序：

1. 先讲16个匹配条件如何构成4×4候选矩阵。
2. 写`match[r][b] = req_valid[r] && addr_ok[r] && (req_bank[r] == b)`。
3. 讲每个Bank独立的优先选择链，按req0→req3选择首个候选。
4. 在每个Bank的组合处理起点重置`winner_found`和`candidate_count`，不能把前一个Bank的临时结果带进下一个Bank。
5. 接出获胜者的en/we/local_addr/wdata/owner，读请求wdata按既定规则置0。
6. 接出grant、stall和conflict，并保留完整默认赋值与越界错误处理。
7. 实际编译；再做与该阶段范围一致的基础组合检查。
8. 保存本阶段完整Markdown并提交推送到main，报告真实commit。

完整T1～T11自检Testbench与VCD仍在后续阶段。当前无Testbench、无波形，不能声称功能已验证。

## 6. 用到的资源文件

### 6.1 `NPU_learing`仓库根目录

已创建：

- `HANDOFF.md`：本交接文档。
- `docs/assignment-01-bank-router-part-01-spec.md`：第一题完整设计规格。
- `docs/assignment-01-bank-router-part-02-rtl-foundation.md`：RTL基础完整讲义与阶段源码。
- `assignments/assignment-01-bank-router/rtl/bank_access_router.sv`：尚未实现仲裁的阶段RTL。
- `assignments/assignment-01-bank-router/checks/rtl-foundation-compile.txt`：实际编译命令、退出码与提示。

已存在并已读取：

- `docs/handoff-after-gemm-post-2026-10-31.md`：GEMM后课程边界。
- `docs/lesson-01-overview.md`。
- `docs/lesson-02-rtl-mac.md`。
- `docs/lesson-03-pe-microarchitecture.md`。
- `docs/lesson-04-systolic-array.md`。
- `docs/lesson-05-gemm-code-walkthrough.md`。
- `docs/lesson-05-gemm-controller-design-patterns.md`。
- `docs/lesson-05-gemm-post.md`。
- `docs/lesson-06-sram-bank-buffer.md`。
- `docs/lesson-06-supplement-ping-pong-pipeline.md`。
- `docs/review-gemm-before-memory-2026-11-06.md`。

已修改：

- `HANDOFF.md`：同步RTL基础阶段完成情况与下一步仲裁核心。

需继续创建：

- 仲裁核心的下一阶段讲义。
- 后续的Testbench、仿真脚本或命令记录、VCD和波形解释文档。

### 6.2 tiny-NPU源码根目录

源码根目录：`/home/zenia/aiinfra/npu/tiny-NPU`。固定参考版本：`8216c22b762011aa20c05fc2768423fd12dda59d`。

已读取并用于选题或核对：

- `README.md`。
- `rtl/top.sv`。
- `rtl/mem/sram_dp.sv`。
- `rtl/mem/banked_sram.sv`。
- `rtl/mem/tile_buffer.sv`。
- `rtl/ctrl/addr_gen.sv`。
- `rtl/ctrl/scoreboard.sv`。
- `rtl/ctrl/barrier.sv`。
- `rtl/ctrl/ucode_fetch.sv`。
- `rtl/ctrl/kv_ctrl.sv`。
- `rtl/bus/axi_dma_rd.sv`。
- `rtl/bus/axi_dma_wr.sv`。
- `rtl/gemm/gemm_post.sv`仅用于排除GEMM候选，不作为作业继续方向。

tiny-NPU工作树中已有用户的GEMM与仿真文件改动，以及`rtl/gemm/gemm_post copy.sv`未跟踪文件。它们不是本作业产生的改动，必须保留，不要重置、覆盖或顺手提交。当前作业代码应写入`NPU_learing`仓库，而不是修改上游tiny-NPU RTL。

### 6.3 外部附件

- 正式作业模板：`/home/zenia/Downloads/数字大规模集成电路-开放作业-学号-姓名.docx`。
- Word临时锁文件：`/home/zenia/Downloads/.~大规模集成电路-开放作业-学号-姓名.docx`，只有162字节，不要使用。
- 初始交接附件：`/home/zenia/Downloads/handoff-after-gemm-post-2026-10-31(1).md`；仓库中已有对应交接内容，后续优先读本文件与仓库版本。

## 7. 需要交接的计划

1. **第一题RTL基础（已完成）**：模块框架、参数、端口、内部信号、默认赋值、地址检查和拆分已写入阶段RTL；Icarus Verilog 12.0编译退出0，有已记录的敏感范围提示。本轮提交阶段讲义与编译记录。
2. **第一题仲裁核心**：讲匹配矩阵与每Bank优先选择链的硬件实现，写默认赋值、候选统计、winner选择、Bank输出和`grant/stall/error/conflict`，防止锁存器；编译并做基础组合测试。
3. **第一题Testbench**：先讲组合电路Testbench结构和自检思想，再实现规格中的T1～T11；运行`iverilog`与`vvp`，生成VCD，核对全部断言和关键波形。
4. **第一题作业成稿**：把题目描述、解题思路、硬件结构、RTL、Testbench、波形截图和文字解释整理进学校模板需要的结构。不能伪造波形，截图必须来自实际仿真。
5. **第二题Tile Buffer**：完成第一题后再开始。先复用已学的Ping-Pong基础，再重点分析原`tile_buffer.sv`中`tile_done`固定0、`next_tile_ready`仅翻转等占位行为，重新定义完整的安全切换协议，然后写时序RTL和验证。
6. **第三题ucode_fetch FSM**：完成第二题后再开始。先讲指令存储、PC、同步读延迟和反压硬件，再画六状态图，最后逐段写状态寄存器、转移逻辑、输出逻辑和Testbench。
7. **持续同步**：每个完整阶段都在同一轮提交并推送到`Zenia-123/NPU_learing/main`，在答复中同时给短commit、完整commit、文件路径和实际验证范围。

新对话的用户只需说：**“读取GitHub仓库`Zenia-123/NPU_learing`的`HANDOFF.md`继续，按当前进度开始第一题仲裁核心。”**

