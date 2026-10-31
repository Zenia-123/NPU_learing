# tiny-NPU学习交接摘要：GEMM / gemm_post讲解后

更新：2026-10-31。本摘要替代“第03讲后”的旧交接，供新对话直接续学。

## 1. 目标与讲解要求

- 用户为集成电路方向研究生，代码基础薄弱。通过tiny-NPU建立RTL、数据通路、控制与性能建模能力，后续衔接CIMFlow及MRAM/异构NPU+PIM研究；本对话只续接tiny-NPU，不混入其他研究写作任务。
- 中文、细致、单次内容可以较多；不要布置练习，不反复从头讲。
- **固定顺序：先画硬件结构和模块位置，讲数据存在哪里、怎样流动；再逐项解释变量的含义、单位、作用和生命周期；然后讲数据通路/控制流，最后按源码顺序解释实现与逐周期时序。** 不把buffer、归约、valid、计数器等词当成用户已经理解的前提。
- 用户要求每讲完整Markdown在当次同步到GitHub：`Zenia-123/NPU_learing`，分支`main`，目录`docs/`。沿用已连接的GitHub工具；不索要私钥，不以邮箱或指纹代替认证。同步成功要有真实commit。

## 2. 当前进度：讲过不等于已掌握

- 用户明确报告已看懂：`mac_int8.sv`、`pe.sv`、`systolic_array.sv`的主体。
- 此后已详细讲解：阵列边界与DRAIN_LATENCY、gemm_ctrl全部流程、buf_a/b位置、归约维度、FP16字节装配、转置地址、store行列推进、控制模块设计方法。
- 最新一讲：已按上述顺序完整讲解用户上传的193行`gemm_post.sv`，包括全部变量、6状态、时序和实现问题；**用户尚未确认已经掌握**，不要自行标记为精通。
- 没有在用户设备上部署环境；没有运行HDL仿真，没有生成VCD，没有修复或提交上游RTL。已经提交的都是教学Markdown。

## 3. 源码与可靠定位

上游：<https://github.com/harishsg993010/tiny-NPU>。

本轮核对固定版本：`8216c22b762011aa20c05fc2768423fd12dda59d`。继续分析应优先沿用该版本，若换版本需重新核对。

- GEMM：`rtl/gemm/{mac_int8,mac_fp16,pe,systolic_array,gemm_ctrl,gemm_post}.sv`。
- 辅助函数：`rtl/pkg/npu_pkg.sv`；flags：`rtl/pkg/isa_pkg.sv`；转换函数：`rtl/graph/fp16_utils.sv`。
- 实际Graph Mode连接证据：`sim/verilator/onnx_sim_top.sv`；不要把根目录top中的占位连接当成完整执行路径。
- 本对话附件：`gemm_ctrl.sv`、`gemm_post.sv`，核对时与上述版本对应文件一致。新对话不能假设旧scratch路径或工具缓存仍可访问；必要时从固定GitHub版本重新读取，不必先要求重新上传。

## 4. 继续任务必须保留的结论

### GEMM硬件与计时

- 统一数学记号：`A[M,K] × B[K,N] = C[M,N]`；物理阵列尺寸另行区分。
- A向东、B向南，每PE转发一拍；局部ACC保存当前输出部分和，从实际行为看是输出驻留，不应仅照抄“Weight-stationary”注释。
- 无额外边界寄存器时，边界A行i在t=i+k送入，B列j在t=j+k送入；两者在PE(i,j)的t=i+j+k匹配。
- INT8的product到ACC再晚一拍；同沿读取旧值。以首拍计入的槽数为口径：采样完乘积需`k+m+n−2`，完成INT8 ACC需`k+m+n−1`，当前控制器STREAM运行`k+m+n`拍。
- `stream_cnt`为当前拍号；`stream_total=k_eff+m_eff+n_eff−1`为末拍编号，包含0，所以状态拍数还要加1。
- 默认PIPE_STAGE=32，16×16不产生额外边界寄存器；减小参数会改变A/B对齐，不能只改延迟阈值。
- 阵列acc_valid不含K，默认连续第33个使能沿才拉高，也不能普遍表示结果完成；Graph封装中`.acc_valid()`悬空，gemm_ctrl用自己的计数控制写回。

### gemm_ctrl结构

- 内部buf_a[i][k]与buf_b[k][j]保存当前输入子块；默认INT8各256Byte，另有FP16各512Byte版本。逻辑归属在控制器内部，不能直接断言物理映射为SRAM宏。
- 归约维度K是每个输出要相加的乘积项数；k是项号，不是额外硬件。
- 数据SRAM接口默认8位：INT8元素1Byte、FP16元素2Byte。load_phase区分请求/捕获，load_byte区分低/高字节，lo_byte保存低字节；当前FP16装载每元素占4个状态周期。
- PE内部ACC与外部ACC SRAM不同。后者在阵列之外，Graph封装例化`256×32bit`、1KiB的sram_dp，保存当前输出tile跨K块部分和；不意味着片外存储。
- 转置标志表示B按Bᵀ[N,K]布局存储；逻辑缓冲仍为B[k][j]。FP16读地址普通布局为`base+load_row*2N+load_col*2+byte`，转置布局为`base+load_col*2K+load_row*2+byte`。base已包含tile偏移，跨度用整矩阵尺寸。
- `sa_acc[store_row[3:0]][store_col[3:0]]`截的是行列索引低4bit，选择完整32位结果；元素4Byte来自ACC_W=32。
- STORE组合逻辑选择当前数据和地址；写入沿SRAM采样当前信号，同时坐标寄存器推进。列先增，行末列清0、行增1；只有完整元素处理完才推进。
- 当前代码按16分块、多处硬编码，tile总数仅4位，不能声称任意规模参数化。FP16跨K部分和用普通位模式整数加法，不能当作正确浮点合并。

### gemm_post最新停点

- 独立后处理模块，不自动串在gemm_ctrl后；所核对的Graph GEMM执行路径中，控制器已有直接转换/写回。
- 状态：`IDLE→READ→WAIT→PROCESS→WRITE`，有下一项则回READ，最后去DONE再IDLE。WAIT支持等待acc_rd_valid，WRITE没有ready反馈。
- acc_val保存返回的32位输入，result保存默认8位输出；elem_cnt只在WRITE拍末加1。最快通常4拍一项，不是每拍一项流水。
- total_elems固定ARRAY_M×ARRAY_N；base_addr和dst_addr每条命令固定0；没有有效m/n或任意命令基址输入。
- flags第1/2/3位分别控制bias/requant/ReLU，锁存到bias_en/requant_en/relu_en；dtype锁存到r_dtype；scale/shift/bias_data直接取外部输入，外部需保证使用时匹配稳定。
- `biased = ...`为本次立即可用的中间值；`result <= ...`不会使下一行马上读到新result。原ReLU判断旧result，输入[5,−3,7]且仅启ReLU时推导输出[5,−3,0]，正确应为[5,0,7]。已给候选next_result再统一寄存的修正示意，**没有改源文件，也没验证RTL补丁**。
- FP16分支只把转换结果低8位写出，缺少高字节；并跳过INT8分支中的bias、量化、ReLU，不能称为完整FP16后处理。
- 另一个已发现问题：mac_fp16中的raw_exp为8位signed，`signed'(8'd255)`是−1，指数判定有明确静态问题；不要宣称该FP16实现完整正确或符合IEEE754。

## 5. 已保存教学文档

以下均位于 <https://github.com/Zenia-123/NPU_learing/tree/main/docs>：

| 文件 | 用途 | 已成功提交的commit短号 |
|---|---|---|
| lesson-04-systolic-array.md | 周期级阵列、延迟、源码与Python核验附录 | 24b48ed |
| lesson-05-gemm-code-walkthrough.md | GEMM各文件及变量完整精读 | 7d9f234 |
| lesson-05-gemm-controller-design-patterns.md | 从控制器提炼可复用设计方法 | e14984e |
| lesson-05-gemm-post.md | 最新gemm_post完整讲义 | 08c33b2 |

原第01～03讲笔记也在同仓库；无需重讲。文档的main版本可能后续变化，需要编辑时先读取当前内容与blob SHA，不覆盖其他笔记。

验证范围：第04讲独立Python状态模型核对2×2/3×3，并通过224组形状/物理尺寸检查；后续只做源码、变量覆盖和数值核算。不能把这224组检查当成整个控制器、FP16或gemm_post的HDL测试。

## 6. 建议下一步，不冒充用户已确认

当前没有新的明确模块指令。若用户继续追问gemm_post，围绕对应硬件/变量答疑，不从GEMM开头复习。

若用户说“下一讲/继续学习”且无其他指定，建议衔接原14讲计划中的第06讲：SRAM、Bank与Buffer，从`rtl/mem/sram_dp.sv`硬件端口、同步读写与时钟沿开始，再看banked_sram、tile_buffer以及顶层连接。明确独立tile_buffer模块与gemm_ctrl内部buf_a/b不是自动同一个东西。之后计划依次为DMA/AXI、ISA与派发、scoreboard/barrier、非矩阵算子、Transformer/KV、编译器、仿真验证与CIMFlow衔接。

不要因发现原码问题就擅自把续学变成修复工程；也不要强制先安装工具或做练习。需要实验时，先解释目的、环境和步骤，并准确区分源码推导与实际仿真。

**新对话接手指令：** 请以本摘要续接tiny-NPU学习。我目前讲到gemm_post结束，尚未确认全部掌握。先响应我新的具体问题；若我要求下一讲，按建议进入SRAM/Bank/Buffer。坚持“硬件结构→变量含义与单位→数据/控制流→代码顺序与时序”，不重复已完成课程；每讲完整Markdown当次同步到Zenia-123/NPU_learing，并给真实提交结果。
