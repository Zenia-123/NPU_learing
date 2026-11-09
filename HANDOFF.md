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
- [x] 第一题仲裁核心已完成：133行组合RTL、7组定向基础自检、实际Icarus Verilog 12.0编译与vvp运行全部退出0；完整T1～T11及VCD仍待后续。
- [x] 第一题规格讲义已提交并推送，commit为`fe623b1d9f877856af5e50b6f9ab88d2bd6e5167`，远端`main`已核验指向该提交。

### 4.3 第一题已经固定的设计决定

- 模块名：`bank_access_router`。
- 纯组合电路，无clk/rst、状态寄存器、锁存器或真正SRAM。
- 默认4请求、4个单端口Bank、每Bank16word、每word8bit。
- 全局word地址8bit，合法0～63；64为首个越界地址。
- 低位交织：`bank_id=global_addr[1:0]`，`local_addr=global_addr>>2`。
- 每Bank独立固定优先级：req0 > req1 > req2 > req3。
- 合法获胜grant，合法失败stall，有效越界error；无效请求三者均0。
- 读请求的Bank写数据输出固定0，禁用Bank所有字段默认0。
- 扁平打包端口按请求号r拆包、按Bank号b打包，编号0占最低位段。
- 每Bank输出en/we/local_addr/wdata/owner/conflict。
- 教学扩展受banked_sram启发，不是原模块的原样复制。

RTL基础阶段94行仅完成地址前端与error，未实现仲裁。该历史阶段编译记录保留在`rtl-foundation-compile.txt`，不代表当前源码仍不完整。

当前仲裁阶段源码133行，新增4×4候选矩阵、逐Bank重置临时量、候选统计、首候选优先、Bank输出选择、grant/stall/conflict。沿用原接口与地址前端，保留完整地址范围检查。

本轮实际编译并运行了`checks/tb_arbitration_smoke.sv`，7组基础向量全部通过。单独RTL编译有6条Icarus常量取位敏感范围提示，测试编译还记录了timescale继承提示；所有命令退出0。完整日志在`checks/arbitration-smoke-results.txt`。

没有运行完整T1～T11回归、没有生成VCD或波形截图，没有运行综合、锁存器形式证明或STA。不要把7组基础仿真升级表述为完整验证。


## 5. 当前进度

**第一题仲裁核心已完成，下一阶段是第一题正式Testbench与波形。** 不重写接口和地址前端，不再次讲解完整仲裁核心，也不跳到第二题或DMA/AXI。

接手时先读：

1. `docs/assignment-01-bank-router-part-01-spec.md`：完整规格与T1～T11。
2. `docs/assignment-01-bank-router-part-03-arbitration.md`：最新阶段讲义。
3. `assignments/assignment-01-bank-router/rtl/bank_access_router.sv`：133行当前RTL。
4. `assignments/assignment-01-bank-router/checks/tb_arbitration_smoke.sv`。
5. `assignments/assignment-01-bank-router/checks/arbitration-smoke-results.txt`。

需要补基础语法时再读part-02，不从头重复。

下一阶段按以下顺序：

1. 先讲组合电路Testbench的硬件/验证位置：DUT输入驱动、输出观察、无功能时钟、刺激与稳定等待。
2. 解释测试变量、扁平总线打包、期望输出、比较与失败信息。
3. 从现有7组smoke检查出发，建立完整T1～T11自检，明确每项覆盖点。
4. 测试期望不要简单复制一份DUT算法；覆盖边界63/64、所有请求者优先位置、独立Bank、不同冲突组合、读写路由与输入撤销。
5. 实际运行iverilog和vvp，生成VCD；用GTKWave或等效方式读取实际波形，截图或导出并解释。
6. 区分Testbench的#1稳定等待与硬件物理传播延迟。
7. 保存完整Markdown、测试代码、真实日志与波形产物，提交main并报告真实commit。
8. 第一题验证与成稿完成后，才进入第二题。

当前7组基础检查已覆盖无效越界、四Bank并行、四请求同Bank、部分冲突、63/64边界、非法高优先级不能获胜、req1胜req2与撤销输出；它们不等于已逐项完成正式T1～T11。

临时Icarus 12.0工具本轮实际存在于`/tmp/npu-iverilog/usr/bin/`，编译使用`-B /tmp/npu-iverilog/usr/lib/x86_64-linux-gnu/ivl`；新会话仍须检查可用性，不能假设该临时目录永久保留。


## 6. 用到的资源文件

### 6.1 `NPU_learing`仓库根目录

最新文件：

- `HANDOFF.md`：当前进度与下一步。
- `docs/assignment-01-bank-router-part-01-spec.md`：规格。
- `docs/assignment-01-bank-router-part-02-rtl-foundation.md`：地址前端历史阶段讲义。
- `docs/assignment-01-bank-router-part-03-arbitration.md`：仲裁核心最新完整讲义。
- `assignments/assignment-01-bank-router/rtl/bank_access_router.sv`：当前133行RTL。
- `assignments/assignment-01-bank-router/checks/rtl-foundation-compile.txt`：历史基础阶段编译记录。
- `assignments/assignment-01-bank-router/checks/tb_arbitration_smoke.sv`：167行基础自检代码。
- `assignments/assignment-01-bank-router/checks/arbitration-smoke-results.txt`：实际编译及7/7结果。

既有第01～06讲、GEMM后交接、Ping-Pong补充与复习文档继续保留，无需重讲。完整课程清单见4.1。

后续需创建正式T1～T11 Testbench、VCD、实际波形说明和第一题作业成稿。


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

1. **第一题规格（已完成）**：part-01。
2. **第一题RTL基础（已完成）**：part-02与历史编译记录。
3. **第一题仲裁核心（已完成）**：part-03、133行RTL、7/7基础自检，实际编译及vvp退出0；未生成VCD。
4. **第一题正式Testbench与波形（下一步）**：补全T1～T11，实际仿真、生成VCD、观察并解释波形。
5. **第一题作业成稿**：题目、思路、硬件结构、RTL、Testbench、真实波形和说明，满足学校模板要求。
6. **第二题Tile Buffer**：完成第一题后再开始。复用已学基础，重点补齐原码next_tile_ready/tile_done占位行为所缺的安全切换协议，再写时序RTL和验证。
7. **第三题ucode_fetch FSM**：完成第二题后开始。先硬件/PC/同步读/反压，画六状态图，再写代码与验证。
8. **持续同步**：每个完整阶段在当次提交main，给短commit、完整commit、文件路径和真实验证范围。不要伪造波形或把有限用例通过表述为所有情况正确。

新对话接手指令：**“读取GitHub仓库`Zenia-123/NPU_learing`的`HANDOFF.md`继续，按当前进度开始第一题正式Testbench与波形。”**
