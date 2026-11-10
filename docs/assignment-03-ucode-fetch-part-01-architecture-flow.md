# 实验三：微码指令读取控制器（一）——整体硬件框架、控制流与数据流

## 1. 实验目标

本实验以 tiny-NPU 的 `rtl/ctrl/ucode_fetch.sv` 为参考，设计一个微码指令读取控制器。它从 128-bit UCODE SRAM 顺序读取指令，通过 `valid/ready` 握手交给 Decode，并能处理同步读延迟、下游反压、`OP_END`、程序长度结束和 `stop`。

本篇只讲硬件结构、控制流和数据流；用户尚未开始第三题 RTL、Testbench 或仿真。

## 2. 模块在 NPU 中的位置
**ucode_fetch 用 FSM 控制 SRAM 读请求，用 PC 产生地址，用指令缓冲寄存器保存返回数据，并以 valid/ready 协议把指令安全交给 Decode。**
```text
控制寄存器                           指令消费者
start / base / len                      ucode_decode
       |                                      ^
       v                                      |
+----------------+     rd_en / rd_addr        | instr_valid / instr_data
|  ucode_fetch   | -----------------> UCODE SRAM -------------------------->
|                | <-----------------           |
| FSM + PC +     |       rd_data / rd_valid     |
| 指令缓冲寄存器 |                               |
+----------------+ <---------- instr_ready -----+
       |
       +-- busy / done
```

`ucode_fetch` 是一个小型取指单元：从 SRAM 取出一条 128-bit 指令，只有 Decode 接收它之后，才会前进到下一条。

## 3. 硬件框架

```text
控制寄存器：state_q、base_q、len_q、pc_q、done_q
数据寄存器：instr_buf_q

组合数据通路：
  rd_addr  = base_q + pc_q
  pc_plus1 = pc_q + 1
  pc_plus1 与 len_q 比较

组合控制通路：
  根据 state_q、start、stop、rd_valid、instr_ready、
  OP_END 和长度比较结果，生成下一状态与寄存器下一值。
```

`pc_q` 的单位是“指令 word 偏移”，不是字节地址。例如：

```text
base_q = 100
pc_q = 0  -> rd_addr = 100
pc_q = 1  -> rd_addr = 101
```

## 4. 信号语义与两组握手

| 信号 | 方向（相对 Fetch） | 含义 |
|---|---|---|
| `start` | 输入 | 开始一次程序取指 |
| `stop` | 输入 | 中止当前程序 |
| `ucode_base_addr` | 输入 | 程序在 SRAM 的起始指令地址 |
| `ucode_len` | 输入 | 程序长度，单位为 128-bit 指令条数 |
| `rd_en`, `rd_addr` | 输出 | 请求 SRAM 读取一条指令 |
| `rd_data`, `rd_valid` | 输入 | SRAM 返回的 128-bit 数据及其有效标志 |
| `instr_valid`, `instr_data` | 输出 | 向 Decode 交付一条指令 |
| `instr_ready` | 输入 | Decode 已接收当前指令 |
| `pc` | 输出 | 当前指令相对起始地址的偏移 |
| `done`, `busy` | 输出 | 执行完成脉冲与运行状态 |

不能混淆两组握手：

```text
Fetch <-> SRAM： rd_en 请求读；rd_valid 说明读返回
Fetch <-> Decode： instr_valid 提供指令；instr_ready 说明已接收
```

## 5. 数据流

微码不是激活值或权重，但在 Fetch 模块中仍是一条真实的 128-bit 数据流：

```text
UCODE SRAM[base + pc]
          |
          | rd_data
          v
     instr_buf_q
          |
          | instr_data
          v
     ucode_decode
```

`instr_buf_q` 是指令缓冲寄存器。它把 SRAM 返回的数据保存住，因此 Decode 忙时，Fetch 可以稳定地保持同一条指令，而不会被下一次 SRAM 读覆盖。

## 6. 控制流与六状态 FSM

```text
S_IDLE --start--> S_FETCH --> S_WAIT_DATA --> S_DISPATCH --> S_INCREMENT
                         |          |                |               |
                         |          |                |               +-- 未结束 --> S_FETCH
                         |          |                |               +-- 到长度 --> S_DONE
                         |          |                +-- ready=0：保持 S_DISPATCH
                         |          +-- OP_END/stop --> S_DONE
                         +-- 发出 SRAM 读请求

S_DONE --> S_IDLE
```

| 状态 | 数据动作 | 控制条件 |
|---|---|---|
| `S_IDLE` | 无 | 等待 `start`，锁存 base/len，令 PC 为 0 |
| `S_FETCH` | `rd_en=1`，`rd_addr=base+pc` | 发起一次 SRAM 读 |
| `S_WAIT_DATA` | 将有效 `rd_data` 写入 `instr_buf_q` | 等 `rd_valid`，检查 `stop` 与 `OP_END` |
| `S_DISPATCH` | `instr_valid=1`，输出 `instr_buf_q` | 等 `instr_ready` |
| `S_INCREMENT` | `pc=pc+1` | 判断新 PC 是否达到 `len` |
| `S_DONE` | 无新数据 | `done=1` 一个周期，随后返回空闲 |

## 7. 正常读取一条指令的逐拍过程

设 `base=100`、`pc=0`，且 Decode 始终 `instr_ready=1`。

| 周期 | 状态 | 关键行为 |
|---|---|---|
| C0 | `S_IDLE` | 采样 `start`，锁存 `base/len`，PC 清零 |
| C1 | `S_FETCH` | `rd_en=1`、`rd_addr=100` |
| C2 | `S_WAIT_DATA` | 等待并接收 `rd_valid=1` 与 128-bit `rd_data` |
| C3 | `S_DISPATCH` | `instr_valid=1`，指令来自 `instr_buf_q` |
| C4 | `S_INCREMENT` | 采样 `instr_ready` 后 PC 从 0 增至 1 |
| C5 | `S_FETCH` | 发起地址 101 的下一次读请求 |

`S_WAIT_DATA` 的存在专门吸收同步 SRAM 的读延迟：Fetch 发出读请求的周期，不能假设 `rd_data` 已有效。

## 8. Decode 反压

若在 `S_DISPATCH` 中出现：

```text
instr_valid = 1
instr_ready = 0
```

Fetch 必须保持：

```text
instr_buf_q 不变
instr_data 不变
pc_q 不变
instr_valid 保持为 1
不发起下一次 SRAM 读
```

直到 Decode 把 `instr_ready` 拉高，当前指令才真正交付，FSM 才可进入 `S_INCREMENT`。

## 9. 结束条件

### `OP_END`

参考模块在 `S_WAIT_DATA` 检查 `rd_data[7:0] == OP_END`。若成立，它不将该指令走普通 Dispatch，而是转向 `S_DONE`。

### 程序长度

普通指令被接收后，Fetch 判断：

```text
pc_plus1 >= len_q
```

若 `len=4`，则 PC 为 `0,1,2,3` 的四条指令可被交付；第四条交付后，PC 加一为 4，随后结束。

## 10. 三个关键认识

1. `rd_valid` 表示 SRAM 返回完成，`instr_ready` 表示 Decode 消费完成；二者属于不同握手链路。
2. 数据流是“SRAM → 指令缓冲 → Decode”，控制流是 FSM 决定何时读、何时等待、何时前进和结束。
3. `S_FETCH`、`S_WAIT_DATA`、`S_DISPATCH` 分别等待 SRAM 请求、SRAM 返回和 Decode 接收，不能合并成一个模糊状态。

## 参考

- tiny-NPU：`rtl/ctrl/ucode_fetch.sv`
- tiny-NPU：`rtl/ctrl/ucode_decode.sv`
- tiny-NPU：`rtl/mem/sram_dp.sv`
