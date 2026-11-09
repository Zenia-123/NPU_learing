# 开放作业第一题第五篇：修正独立作业目录并完成T1～T11波形验证

日期：2026-11-09。

本阶段以用户指定的独立作业目录为准：

`/home/zenia/aiinfra/assignment`

完成三件事：

1. 在该目录实际编译用户重写的Verilog RTL与基础Testbench；
2. 根据真实编译错误逐项修正，而不是整体覆盖用户代码；
3. 新建正式T1～T11自检Testbench，生成VCD并检查关键时段。

本阶段使用Icarus Verilog 11.0、Verilog-2005模式。正式回归结果为11/11通过，但仍不等于穷举证明、综合验证或物理时序验证。

## 1. 当前目录结构

```text
/home/zenia/aiinfra/assignment/
├── bank_router/
│   ├── rtl/
│   │   └── bank_access_router.v
│   ├── tb/
│   │   ├── bank_access_router_tb.v
│   │   └── bank_access_router_t11_tb.v
│   ├── build/
│   │   ├── bank_router_sim.vvp
│   │   └── bank_router_t11_sim.vvp
│   └── waves/
│       └── bank_router_t11.vcd
└── docs/
    └── assignment-01-t11-testbench-waveform.md
```

`build`中的`.vvp`是Icarus生成的仿真可执行中间文件；`waves`中的`.vcd`记录信号随仿真时间的变化。

## 2. 在终端编译和运行

先进入作业根目录：

```bash
cd /home/zenia/aiinfra/assignment
mkdir -p bank_router/build bank_router/waves
```

### 2.1 编译和运行7组基础smoke测试

```bash
iverilog -g2005 -Wall -s bank_access_router_tb \
  -o bank_router/build/bank_router_sim.vvp \
  bank_router/rtl/bank_access_router.v \
  bank_router/tb/bank_access_router_tb.v

vvp bank_router/build/bank_router_sim.vvp
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

### 2.2 编译和运行正式T1～T11

```bash
iverilog -g2005 -Wall -s bank_access_router_t11_tb \
  -o bank_router/build/bank_router_t11_sim.vvp \
  bank_router/rtl/bank_access_router.v \
  bank_router/tb/bank_access_router_t11_tb.v

vvp bank_router/build/bank_router_t11_sim.vvp
```

实际结果：

```text
PASS T1 all requests invalid
PASS T2 single legal read
PASS T3 single legal write
PASS T4 four requests on different Banks
PASS T5 two requests on one Bank
PASS T6 four requests on one Bank
PASS T7 address 63 boundary
PASS T8 address 64 out of range
PASS T9 inactive out-of-range address
PASS T10 one invalid plus three legal requests
PASS T11 outputs clear after changing inputs
RESULT PASS T1-T11: 11/11 tests
```

### 2.3 打开波形

```bash
gtkwave bank_router/waves/bank_router_t11.vcd
```

GTKWave 3.3.104已安装。如果终端出现`Failed to load module "canberra-gtk-module"`，它是桌面声音主题模块提示，不影响VCD读取。

## 3. 第一次编译发现的真实错误

第一次执行`iverilog -g2005`时，编译器首先报告：

```text
bank_router/rtl/bank_access_router.v:1: Invalid `timescale unit scale
bank_router/rtl/bank_access_router.v:4: syntax error
I give up.
```

编译器在前两处语法错误后停止，但继续静态检查还发现了后续问题。

| 原写法 | 问题 | 修正 |
|---|---|---|
| ``timescale 1nm/1ps` | Verilog时间单位没有nm | 改为`1ns/1ps` |
| `parameter int` | `int`是SystemVerilog写法 | 改为`parameter integer` |
| 参数列表中的`localparam int` | 不符合本作业Verilog-2005约束 | 改为`parameter integer` |
| 端口`reg_error` | Testbench连接的是`req_error` | 统一为`req_error` |
| `reg_grant/reg_stall` | 未声明且与端口名不一致 | 改为`req_grant/req_stall` |
| `condidate_count` | 拼写错误 | 改为`candidate_count` |
| 候选计数声明成1bit `reg` | 无法正确表示0～4 | 改为`integer` |
| 一处中文全角`；` | 不是Verilog分号 | 改为英文`;` |
| `BANKSEL_W` | 漏掉下划线 | 改为`BANK_SEL_W` |
| `!addr_ok` | 数组缺少请求下标 | 改为`!addr_ok[r]` |
| Testbench末尾两个`endmodule` | 模块结束符重复 | 删除多余项 |

这些错误可以分为三类：

- 词法/语法错误：时间单位、全角分号、多余`endmodule`；
- 名称错误：`reg_`与`req_`、`BANKSEL_W`、`condidate_count`；
- 硬件语义错误：候选计数只有1bit、地址合法数组缺少索引。

最后一类最需要重视：有些代码即使能编译，位宽或索引错误仍可能让硬件功能不正确。

## 4. 编译警告是否表示失败

修正后，Icarus只给出如下类型的提示：

```text
warning: @* is sensitive to all 4 words in array 'req_addr'.
warning: @* is sensitive to all 4 words in array 'addr_ok'.
```

这表示`always @(*)`自动把数组中所有相关元素加入组合敏感列表。它是Icarus的展开提示，不是语法错误，也不是锁存器警告。

当前结论：

- 编译错误：0；
- 仿真失败：0；
- 说明性数组敏感列表警告：9条；
- smoke测试：7/7；
- 正式测试：11/11。

## 5. Testbench在硬件验证中的位置

DUT是需要检查的组合硬件；Testbench只存在于仿真器中。

```text
                   Testbench
  ┌─────────────────────────────────────────┐
  │ initial：按T1→T11安排测试               │
  │      │                                  │
  │      ├─ clear_case：清输入和期望值      │
  │      ├─ drive_req：向DUT输入施加请求    │
  │      ├─ expect_bank：填写人工期望输出   │
  │      └─ check_case：比较实际值与期望值  │
  │                         │               │
  │                         └─ $dumpvars    │
  │                              │          │
  └──────────────────────────────┼──────────┘
                                 ▼
                         bank_router_t11.vcd
```

`clear_case`、`drive_req`、`expect_bank`和`check_case`是并列的仿真辅助任务，都由`initial`入口调用。它们不会被综合进`bank_access_router`硬件。

“谁调用谁”和“谁传什么”需要分开看：

- 调用关系：`initial`调用四类task；
- 激励数据流：`drive_req`写输入，DUT计算输出；
- 参考数据流：`expect_bank`写期望值；
- 判定数据流：`check_case`把DUT输出与期望值送入不等比较。

## 6. T1～T11覆盖内容

| 测试 | 场景 | 关键检查 |
|---|---|---|
| T1 | 所有请求无效 | 所有输出为0 |
| T2 | 单个合法读 | Bank号、局部地址、owner、读数据总线归零 |
| T3 | 单个合法写 | Bank写使能、地址和写数据 |
| T4 | 四请求访问不同Bank | 四请求全部授权，无冲突 |
| T5 | 两请求访问同Bank | req1胜req3，req3阻塞 |
| T6 | 四请求访问同Bank | req0唯一获胜，其他三个阻塞 |
| T7 | 地址63 | Bank3、local15，仍为合法 |
| T8 | 地址64 | error置位，不能使能Bank |
| T9 | valid=0且地址255 | 不产生error |
| T10 | 一个越界加三个合法请求 | 越界请求不参与仲裁，其他Bank仍并行 |
| T11 | 活跃输入后立即全部撤销 | 输出清零，不保留上一组状态 |

期望输出是按测试场景显式填写的，没有复制一份DUT仲裁算法。这样可降低DUT和参考模型犯同一种错误而仍然“通过”的风险。

## 7. VCD波形时间安排

`timescale 1ns/1ps`表示Testbench延迟以ns书写，VCD内部以1ps为最小时间刻度保存。

| VCD时间 | 对应阶段 |
|---:|---|
| 0～1ns | T1 |
| 1～2ns | T2 |
| 2～3ns | T3 |
| 3～4ns | T4 |
| 4～5ns | T5 |
| 5～6ns | T6 |
| 6～7ns | T7 |
| 7～8ns | T8 |
| 8～9ns | T9 |
| 9～10ns | T10 |
| 10～11ns | T11活跃冲突输入 |
| 11～12ns | T11撤销输入后输出清零 |

建议在GTKWave加入：

```text
current_test
req_valid
req_we
req_addr_flat
req_grant
req_stall
req_error
bank_en
bank_we
bank_addr_flat
bank_wdata_flat
bank_owner_flat
bank_conflict
```

### 7.1 重点观察T5

T5中req1与req3访问Bank2：

```text
req_valid      = 1010
req_grant      = 0010
req_stall      = 1000
bank_en        = 0100
bank_conflict  = 0100
Bank2 owner    = 01（req1）
```

这同时证明固定优先级、失败请求阻塞和局部冲突标志。

### 7.2 重点观察T8

T8中req1访问地址64：

```text
req_error = 0010
req_grant = 0000
req_stall = 0000
bank_en   = 0000
```

越界是错误，不是“Bank暂时忙”，所以不能同时产生stall。

### 7.3 重点观察T11

10～11ns先施加四个访问Bank0的请求；11ns时不使用复位，直接把输入清零。随后：

```text
req_grant      → 0000
req_stall      → 0000
req_error      → 0000
bank_en        → 0000
bank_conflict  → 0000
```

这说明输出只由当前输入决定，没有保存上一组仲裁结果。

## 8. 三个需要串起来理解的结论

1. Testbench task负责组织仿真，不属于DUT硬件；DUT仍然只有组合地址逻辑、候选矩阵、优先选择和多路器。
2. `#1`是给仿真器安排检查时刻，不代表硬件需要一个时钟周期，也不等于真实门延迟恰好1ns。
3. 控制输出`grant/stall/error/conflict`与数据输出`addr/wdata/owner`必须在同一测试中一起检查，否则可能只验证“选中了Bank”，却没有验证“送过去的数据来自正确请求者”。

## 9. 当前验证边界和下一步

当前已经完成RTL编译、7组基础测试、正式T1～T11和VCD生成。尚未完成：

- 在GTKWave GUI中整理最终报告用信号布局并截图；
- 把题目、解题思路、RTL、Testbench、波形图和结论排入学校Word模板；
- 综合资源和组合路径检查。

下一步应打开VCD，按T5、T8、T11三个重点窗口整理正式波形截图和说明，然后开始第一题作业成稿。
