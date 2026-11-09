# 开放作业第一题第四篇：迁移到Verilog-2005并复验组合仲裁

日期：2026-11-09。

本阶段把第一题已有的SystemVerilog阶段代码迁移为课程要求的Verilog-2005，保持硬件结构、端口语义、地址映射和固定优先级规则不变。本阶段完成7组基础定向检查；这不是最终T1～T11 Testbench，也没有生成正式VCD波形。

讲解顺序为：硬件结构→变量含义与单位→数据/控制流→代码顺序与组合时序→Verilog迁移→实际验证。

## 1. 先确认迁移的硬件边界

`bank_access_router`位于多个NPU访问请求者与多个单端口SRAM Bank之间。它只处理当前输入，不包含SRAM存储阵列，也不包含读数据返回通道。

```text
4个请求者
valid/we/global_addr/wdata
        │
        ▼
+-------------------------------+
| 地址检查与低位交织地址拆分    |
| global_addr → bank + local    |
+-------------------------------+
        │
        ▼
+-------------------------------+
| 4×4请求-Bank候选矩阵          |
+-------------------------------+
        │
        ├────► Bank0独立仲裁与路由 ────► Bank0接口
        ├────► Bank1独立仲裁与路由 ────► Bank1接口
        ├────► Bank2独立仲裁与路由 ────► Bank2接口
        └────► Bank3独立仲裁与路由 ────► Bank3接口
                     │
                     └────► grant/stall/error/conflict
```

Verilog迁移后仍满足：

- 没有`clk`和`rst`；
- 没有跨拍保存的状态；
- 不同Bank可以同拍并行接收请求；
- 同一Bank内`req0 > req1 > req2 > req3`；
- 合法失败请求产生`stall`，越界请求产生`error`；
- 地址单位仍是word，不是byte偏移量。

所以这仍是一道组合电路题。迁移不是重新设计模块。

## 2. 一句话代码骨架

整个RTL可以概括成：

> 1个组合入口 + 3段组合引擎 + 2组扁平接口。

- 组合入口：唯一的`always @(*)`；
- 引擎1：拆包、地址范围检查和Bank/局部地址计算；
- 引擎2：建立请求到Bank的候选关系；
- 引擎3：每Bank固定优先级选择、数据路由和反馈；
- 输入接口：4个请求者打包在扁平总线上；
- 输出接口：4个Bank字段打包在扁平总线上。

三个引擎是依赖关系上的嵌套流水，不是三个并列入口，也不是三个时钟周期。它们全部在一次组合求值中稳定下来。

## 3. 变量含义、宽度和单位

默认配置为4个请求者、4个Bank、每Bank 16 word、每word 8 bit。

### 3.1 请求侧

| 信号 | 默认宽度 | 单位/含义 |
|---|---:|---|
| `req_valid` | 4bit | 每位对应一个请求者是否有效 |
| `req_we` | 4bit | 1为写，0为读 |
| `req_addr_flat` | 32bit | 4个8bit全局word地址 |
| `req_wdata_flat` | 32bit | 4个8bit写数据 |
| `req_grant` | 4bit | 当前组合仲裁中已获授权 |
| `req_stall` | 4bit | 地址合法但竞争失败，需要上游重试 |
| `req_error` | 4bit | 有效请求的地址超出0～63 |

请求0占扁平总线的最低切片。例如：

```verilog
req_addr[r] = req_addr_flat[r*GLOBAL_ADDR_W +: GLOBAL_ADDR_W];
```

`+:`是固定宽度导线切片，不是移位寄存器。

### 3.2 Bank侧

| 信号 | 默认宽度 | 单位/含义 |
|---|---:|---|
| `bank_en` | 4bit | 每Bank当前是否收到获胜请求 |
| `bank_we` | 4bit | 获胜请求的读写方向 |
| `bank_addr_flat` | 16bit | 每Bank 4bit局部word地址 |
| `bank_wdata_flat` | 32bit | 每Bank 8bit写数据 |
| `bank_owner_flat` | 8bit | 每Bank 2bit获胜请求者编号 |
| `bank_conflict` | 4bit | 每Bank是否存在至少2个合法候选 |

`owner`的单位是请求者编号，不是Bank编号。`bank_en=0`时其余字段保持0，此时`owner=0`不表示req0获胜。

### 3.3 中间量

| 名字 | 默认规模 | 含义 |
|---|---:|---|
| `req_addr[r]` | 4×8bit | 拆出的完整全局word地址 |
| `addr_ok[r]` | 4×1bit | 完整地址是否小于64 |
| `req_bank[r]` | 4×2bit | 地址低2bit得到的Bank号 |
| `req_local_addr[r]` | 4×4bit | 地址右移2位得到的Bank内word地址 |
| `match` | 16bit | 展平后的4×4候选矩阵 |
| `winner_found` | 1bit临时量 | 当前Bank是否已选出更高优先级请求 |
| `candidate_count` | integer临时量 | 当前Bank候选数，实际范围0～4 |

这些中间量全部在组合块内重新计算，不跨周期保存。

## 4. 数据流与控制流必须分开看

数据流负责“传什么”：

```text
req_we / req_wdata / local_addr
              │
              ▼
        获胜请求多选一
              │
              ▼
bank_we / bank_wdata / bank_addr
```

控制流负责“谁能传”：

```text
valid + addr_ok + bank相等
              │
              ▼
          match候选位
              │
              ▼
 req0→req1→req2→req3优先扫描
              │
              ├──► grant / bank_en / owner
              ├──► loser产生stall
              └──► 候选数>1产生conflict
```

调用关系和数据流并不相同：`match`只决定控制资格，不承载写数据；写数据只在对应请求获胜后被多路选择到Bank输出。

## 5. 为什么SystemVerilog不能直接改扩展名

原阶段代码包含课程要求之外的SystemVerilog写法：

| SystemVerilog阶段写法 | Verilog-2005写法 | 硬件含义是否变化 |
|---|---|---|
| `logic` | 按驱动方式改为`wire`或`reg` | 不变 |
| `always_comb` | `always @(*)` | 不变 |
| `parameter int` | `parameter integer` | 不变 |
| `for (int r=...)` | 模块级`integer r;`后使用`for` | 不变 |
| `match[r][b]`二维数组 | `match[r*N_BANKS+b]`一维位向量 | 不变 |
| `'0` | 明确宽度的`{WIDTH{1'b0}}` | 不变 |
| Testbench的`string` | 定宽ASCII打包向量 | 只影响仿真代码 |
| `$fatal` | `failed`计数与最终汇总 | 只影响仿真代码 |

### 5.1 `wire`和`reg`按谁驱动来区分

输入端口由模块外部驱动，所以声明为`input wire`。输出在`always @(*)`过程块中赋值，所以声明为`output reg`。

这里的`reg`是Verilog语言的过程赋值变量类型，不等于一定综合成触发器。是否产生触发器取决于：

- 是否有时钟沿控制；
- 是否需要记住之前的值；
- 组合块中是否存在未赋值路径。

当前代码没有时钟，并在过程块起点给全部输出默认值，所有条件路径都有确定结果，因此目标硬件仍是组合逻辑。

### 5.2 为什么把二维候选矩阵展平

SystemVerilog能自然写：

```systemverilog
match[r][b]
```

Verilog-2005对多维未打包数组支持有限，因此改成16bit向量：

```verilog
reg [N_REQ*N_BANKS-1:0] match;
match[r*N_BANKS+b]
```

默认4个Bank时：

| 请求 | 对应match位 |
|---|---|
| req0 | bit 0～3 |
| req1 | bit 4～7 |
| req2 | bit 8～11 |
| req3 | bit 12～15 |

位编号变化了，表达的16条候选导线没有变化。

## 6. 按硬件依赖顺序写RTL

### 6.1 第一步：声明参数和端口

先写规模参数，再写请求输入、请求反馈和Bank输出。`LOCAL_ADDR_W`与`OWNER_W`需要参与端口宽度，因此放在参数列表中。

现阶段只核验默认参数。若以后修改为非2次幂Bank数量或单请求者，需要重新审查地址拆分和`$clog2`宽度，不能把本次7组通过外推为任意参数均正确。

### 6.2 第二步：给所有组合结果默认值

```verilog
req_grant       = {N_REQ{1'b0}};
bank_en         = {N_BANKS{1'b0}};
bank_addr_flat  = {(N_BANKS*LOCAL_ADDR_W){1'b0}};
match           = {(N_REQ*N_BANKS){1'b0}};
```

默认值不是“复位”。它表示每次输入变化重新计算时先建立无请求、无授权、无冲突的组合基线。后续条件满足时再覆盖对应字段。

### 6.3 第三步：拆包并检查完整地址

```verilog
addr_ok[r]        = (req_addr[r] < TOTAL_WORDS);
req_bank[r]       = req_addr[r][BANK_SEL_W-1:0];
req_local_addr[r] = req_addr[r] >> BANK_SEL_W;
req_error[r]      = req_valid[r] && !addr_ok[r];
```

必须先用完整8bit地址判断是否小于64。地址64的低2bit也是0，如果只看低位，它会错误伪装成Bank0地址。

### 6.4 第四步：建立候选矩阵

```verilog
match[r*N_BANKS+b] =
    req_valid[r] && addr_ok[r] &&
    (req_bank[r] == b[BANK_SEL_W-1:0]);
```

一个合法请求只会匹配一个Bank；一个Bank可能收到多个请求。

### 6.5 第五步：每Bank独立仲裁和路由

外层循环是Bank，内层循环按req0到req3扫描：

```text
Bank0：独立寻找第一个候选
Bank1：独立寻找第一个候选
Bank2：独立寻找第一个候选
Bank3：独立寻找第一个候选
```

每进入一个新Bank，都必须把`winner_found`和`candidate_count`清零。否则Bank0的临时结果会污染Bank1。

第一次遇到候选时，当前请求获得`grant`，其操作、局部地址和数据被送到当前Bank；后续候选只增加冲突计数，不再覆盖获胜者。

### 6.6 第六步：最后生成stall

```verilog
req_stall[r] = req_valid[r] && addr_ok[r] && !req_grant[r];
```

必须等全部Bank仲裁结束后才能读取最终`req_grant`。同时保留`addr_ok`条件，避免把越界错误误报为“稍后重试”。

## 7. 跟随一次真实组合求值

使用基础检查S3：

| 请求 | 操作 | 全局地址 | Bank/局部地址 | 结果 |
|---|---|---:|---|---|
| req0 | 读 | 5 | Bank1/local1 | 赢得Bank1 |
| req1 | 写0xA1 | 9 | Bank1/local2 | 被req0阻塞 |
| req2 | 写0xB2 | 14 | Bank2/local3 | 赢得Bank2 |
| req3 | 读 | 16 | Bank0/local4 | 赢得Bank0 |

核心变量的生命周期为：

```text
req_addr_flat切片
    │
    ├─ req0地址5  ─► addr_ok=1, bank=1, local=1 ─► match[req0,B1]=1
    ├─ req1地址9  ─► addr_ok=1, bank=1, local=2 ─► match[req1,B1]=1
    ├─ req2地址14 ─► addr_ok=1, bank=2, local=3 ─► match[req2,B2]=1
    └─ req3地址16 ─► addr_ok=1, bank=0, local=4 ─► match[req3,B0]=1

Bank0扫描：req3获胜
Bank1扫描：req0先出现，req1只计入冲突
Bank2扫描：req2获胜
Bank3扫描：无候选
    │
    ▼
grant=1101, stall=0010, error=0000
```

三个请求可以同时通过，因为它们最终使用三个不同Bank。Bank1的局部冲突不会阻塞Bank0或Bank2。

## 8. Testbench也按Verilog-2005迁移

基础Testbench使用三个任务：

1. `clear_case`：清输入和全部期望值；
2. `drive_req`：按请求编号写入扁平输入切片；
3. `expect_bank`：明确填写某Bank的期望字段；
4. `check_case`：等待1ns组合稳定后，用`!==`比较全部输出。

前三个是并列的辅助任务，均由`initial`测试入口调用；它们不会彼此嵌套。`check_case`负责比较，不复刻DUT仲裁算法，避免DUT和参考模型犯同一种错误却互相“验证通过”。

`#1`只用于仿真调度，不代表硬件规定需要1ns，也不把组合模块变成时序模块。

7组基础检查覆盖：

| 编号 | 检查内容 |
|---|---|
| S0 | 无效请求即使地址越界也不报错 |
| S1 | 四个不同Bank可全部并行通过 |
| S2 | 四请求竞争Bank1，req0获胜 |
| S3 | 局部冲突与其他Bank并行 |
| S4 | 地址63合法、64越界 |
| S5 | 越界高优先级请求不能阻挡合法请求 |
| S6 | 活跃流量撤销后输出回到全零 |

## 9. 实际编译与运行结果

本机工具：Icarus Verilog 11.0 stable。

实际命令：

```bash
iverilog -g2005 -Wall -s tb_arbitration_smoke \
  -o /tmp/npu_assignment_verilog/smoke_v.vvp \
  assignments/assignment-01-bank-router/rtl/bank_access_router.v \
  assignments/assignment-01-bank-router/checks/tb_arbitration_smoke.v

vvp /tmp/npu_assignment_verilog/smoke_v.vvp
```

实际结果：

```text
PASS S0 inactive out-of-range request
PASS S1 four independent Banks
PASS S2 four candidates on Bank1
PASS S3 partial conflict and parallel routing
PASS S4 address 63 accepted and 64 rejected
PASS S5 invalid req0 cannot win; req1 beats req2
PASS S6 outputs clear after active traffic
PASS arbitration smoke: 7/7 vectors
```

Icarus对`@(*)`读取数组给出“敏感于数组全部4个元素”的提示。这是敏感列表展开信息，不是编译错误；它说明数组任一相关元素变化都会触发组合块重新求值。

## 10. 本阶段结论与验证边界

迁移后的RTL和基础Testbench均以`.v`保存，并通过`iverilog -g2005`编译与7/7运行。迁移没有加入寄存器、时钟或新协议。

仍未完成：

- 正式T1～T11 Testbench；
- VCD波形生成与GTKWave检查；
- 作业报告中的完整波形图和逐项说明；
- 综合、门级或时序分析；
- 默认值以外的参数组合验证。

因此准确表述是“默认配置下7组基础定向检查通过”，不能表述为“所有情况都已验证”。

## 11. 三个需要串起来记住的认识

1. `reg`描述的是过程赋值方式；没有时钟且组合路径完整赋值时，硬件仍是组合逻辑。
2. `match`决定哪个请求有资格竞争，优先仲裁决定谁获胜，数据多选器才把获胜者的地址和数据送到Bank；三者职责不同但首尾相连。
3. 代码中的循环会被展开为并行组合结构；代码顺序表达逻辑依赖，不代表依次消耗多个时钟周期。

下一阶段是在此Verilog-2005版本上编写正式T1～T11 Testbench、生成VCD，并按测试时段解释关键波形。
