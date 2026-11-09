# 实验二：双 Bank 乒乓 Tile Buffer（二）——RTL 协议、结构与逐拍时序

## 1. 本阶段目标

本篇承接第一讲 `assignment-02-tile-buffer-part-01-hardware.md`。用户随后要求先获得一版完整 RTL 并理解设计原因，因此本篇固定了用于第一版仿真的启动装载、最后传输标记和安全交换协议；用户尚未亲自保存、编译或仿真该 RTL。

本实验实现一个位于 DMA 与计算阵列之间的双 Bank Tile Buffer。目标不是单纯存数据，而是在不覆盖当前计算数据的前提下，让 DMA 装载下一块 Tile 与计算侧读取当前 Tile 并行进行。

本阶段定义并解释以下安全协议：

```text
swap_fire = swap_req && tile_done && next_tile_ready
```

只有当前 Tile 的最后一个读数据已经返回、下一 Tile 已经装满、且控制器提出交换请求时，两个 Bank 才交换角色。

## 2. 模块在 NPU 中的位置

```text
外部 DDR / SRAM
      |
      | DMA：每拍写一个 word
      v
+---------------------------------+
|       Double Tile Buffer        |
|       Bank0          Bank1      |
+---------------------------------+
      |
      | Compute：提出读地址，下一拍返回数据
      v
计算阵列 / GEMM Engine
```

单 Bank 结构中，DMA 若装载下一 Tile，会覆盖计算侧仍在读取的数据；若禁止覆盖，DMA 又只能等待计算结束。双 Bank 将两个行为放到不同的物理存储体，因此可并行。

## 3. Bank 角色

硬件中存在两组存储阵列：

```text
bank0[0 : BANK_DEPTH-1]
bank1[0 : BANK_DEPTH-1]
```

`DATA_W` 是每个 word 的位宽，`BANK_DEPTH` 是每个 Bank 可容纳的 word 数，地址宽度为 `ADDR_W = ceil(log2(BANK_DEPTH))`。

一位寄存器 `active_bank` 指出**当前计算侧使用的 Bank**：

| `active_bank` | Compute 读取 | DMA 正常写入 |
|---:|---|---|
| 0 | Bank0 | Bank1 |
| 1 | Bank1 | Bank0 |

因此，稳定运行时读写始终落在不同 Bank。

## 4. 启动阶段

复位不能清空或初始化实际 SRAM 内容；复位只会清空控制寄存器。因而复位后不能直接让计算侧读 Bank0。

本实验引入 `dma_bootstrap`：

1. 复位后 `active_bank=0`、`compute_tile_valid=0`；
2. `dma_bootstrap=1` 时，DMA 改为写当前计算 Bank，即 Bank0；
3. DMA 在最后一次有效写同时给出 `dma_wr_last=1`；
4. `compute_tile_valid` 置 1，表示第一块 Tile 已可计算；
5. 后续 `dma_bootstrap=0`，DMA 恢复写对侧预取 Bank。

`compute_tile_valid` 防止计算侧从尚未装载、内容不确定的 Bank 读取数据。

## 5. 数据路径与状态路径

```text
dma_wr_en/dma_wr_addr/dma_wr_data
             |
             v
       [ DMA 写路径 ] -----> bank0 / bank1
                                   |
compute_rd_en/compute_rd_addr      v
             |               [ 同步读路径 ] --> compute_rd_data
             |
dma_wr_last, compute_rd_last, swap_req
             |
             v
       [ 控制状态路径 ] --> active_bank
                            compute_tile_valid
                            tile_done
                            next_tile_ready
```

三个时序块是并列硬件，不是软件中的先后调用关系。在同一个上升沿，它们都基于沿到来前的旧寄存器值做判断；非阻塞赋值在沿后统一更新状态。

## 6. DMA 写满时序

`dma_wr_last` 与 `dma_wr_en` 同时有效，表示本次 DMA 写是该 Tile 的最后一项。它是协议语义，不依赖“地址一定等于 `BANK_DEPTH-1`”，因而可扩展到起始地址变化、稀疏或分段访问的 Tile。

正常运行且 `active_bank=0` 时，DMA 向 Bank1 写入：

| 周期 | DMA 操作 | Bank1 状态 | `next_tile_ready` |
|---|---|---|---:|
| C0 | 写入一项 | 部分有效 | 0 |
| ... | 连续写入 | 部分有效 | 0 |
| Cn | 最后一项，`dma_wr_last=1` | Tile 完整 | 1 |
| Cn+1 | 等待交换 | Tile 完整 | 1 |

`next_tile_ready` 必须由最后一次真实 DMA 写产生。tiny-NPU 原始参考代码在 `swap` 时翻转该标志，不能说明 DMA 是否真的写满数据。

## 7. Compute 同步读与 `tile_done`

计算侧给出 `compute_rd_en` 和 `compute_rd_addr`。在一个上升沿采样请求地址后，存储器数据写入 `compute_rd_data` 寄存器；对发起请求的控制器而言，数据在下一周期有效。

若最后一次读请求在 C11 提出：

| 周期 | Compute 请求 | `compute_rd_data` | `tile_done` |
|---|---|---|---:|
| C10 | 读地址 2 | 返回地址 1 的数据 | 0 |
| C11 | 读地址 3，`compute_rd_last=1` | 返回地址 2 的数据 | 0 |
| C12 | 不再读本 Tile | 返回地址 3 的数据 | 1 |

所以 `tile_done` 的语义是“最后一个读数据已经返回”，而不是“最后一个地址刚被提出”。代码在检测到最后读请求的同一上升沿更新数据寄存器与 `tile_done`；沿后进入的新周期里，两者同时有效。

## 8. 安全交换时序

安全交换逻辑为：

```verilog
assign swap_fire = swap_req && tile_done && next_tile_ready;
```

| 周期 | 条件 | 结果 |
|---|---|---|
| C20 | `tile_done=1`，`next_tile_ready=1`，`swap_req=0` | 等待请求，不交换 |
| C21 | 三个条件均为 1 | `swap_fire=1` |
| C22 | 交换后的新周期 | `active_bank` 翻转，两个完成标志清零 |

交换边沿屏蔽 DMA 写和计算读，使其成为无数据传输的干净边界。下一拍起，新 Compute Bank 可读，新 Prefetch Bank 可被 DMA 装载。

若 `swap_req` 在任一完成标志为 0 时出现，它不会触发交换。本实验采用脉冲被忽略的规则，因此控制器应在两个标志已经为 1 后才发送请求。

## 9. RTL 接口与实现

用户在本机作业目录中保存的 RTL 文件为：

```text
/home/zenia/aiinfra/assignment/tile_buffer/rtl/tile_buffer.v
```

核心接口含义如下：

| 信号 | 方向 | 含义 |
|---|---|---|
| `dma_wr_en/addr/data` | 输入 | DMA 的一次写请求 |
| `dma_wr_last` | 输入 | 本次 DMA 写是本 Tile 最后一项 |
| `dma_bootstrap` | 输入 | 启动时写当前 Compute Bank |
| `compute_rd_en/addr` | 输入 | 计算侧同步读请求 |
| `compute_rd_last` | 输入 | 本次读是当前 Tile 最后一次读请求 |
| `compute_rd_data` | 输出 | 下一周期返回的读数据 |
| `compute_tile_valid` | 输出 | 当前 Compute Bank 可安全读取 |
| `tile_done` | 输出 | 当前 Tile 的最后读数据已经返回 |
| `next_tile_ready` | 输出 | 对侧预取 Bank 已完整装入 |
| `swap_req` | 输入 | 控制器请求交换 Bank |

实现中应包含两个存储阵列、DMA 写时序块、Compute 同步读时序块和控制状态时序块。存储阵列不复位；由三个有效/完成状态防止未初始化数据被使用。

## 10. 参考实现的三个占位问题

tiny-NPU 的原始 `tile_buffer.sv` 已展示了 Bank 选择与同步读方向，但握手逻辑是占位实现：

1. `next_tile_ready` 在每次 `swap` 翻转，不能表示 DMA 是否写满；
2. `tile_done` 恒为 0，不能表示计算完成；
3. `swap` 不检查任何完成条件，可能过早交换角色。

本实验的目标就是用 `dma_wr_last`、`compute_rd_last`、`tile_done`、`next_tile_ready` 和 `swap_fire` 替代这三个占位行为。

## 11. 下一步：Testbench 验证目标

Testbench 将按顺序验证：

1. 复位后 `compute_tile_valid=0`；
2. 启动 DMA 装填 Bank0 后，`compute_tile_valid=1`；
3. 计算读的输出确实晚一拍；
4. DMA 可同时装填 Bank1，最后一项后 `next_tile_ready=1`；
5. 早到 `swap_req` 不改变角色；
6. 两个完成标志均有效时，`swap_req` 才切换角色；
7. 交换后从原 Bank1 读取下一块 Tile，并继续装填原 Bank0。
