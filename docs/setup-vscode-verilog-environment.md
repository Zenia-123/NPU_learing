# VS Code Verilog作业环境搭建指南

日期：2026-11-09。

本指南用于三道数字电路开放作业。RTL语言统一采用Verilog-2005，不使用SystemVerilog。编辑器使用VS Code，编译与仿真使用Icarus Verilog，波形查看使用GTKWave。

## 1. 工具分别负责什么

```text
VS Code：编辑.v文件、显示语法高亮和静态检查结果
    ↓
iverilog：编译RTL与Testbench，检查语法并生成.vvp仿真程序
    ↓
vvp：运行仿真程序，执行Testbench并生成VCD
    ↓
GTKWave：打开VCD，观察信号随仿真时间的变化
```

VS Code本身不是Verilog仿真器。扩展给出的红线也不能代替完整编译和仿真；最终结果必须以命令行实际执行为准。

## 2. 当前电脑已经具备的环境

已核对当前Ubuntu环境：

| 项目 | 当前状态 |
|---|---|
| 操作系统 | Ubuntu 22.04.5 LTS |
| VS Code | 已安装，命令为`code` |
| Icarus Verilog | 已安装，版本11.0 stable |
| 仿真运行器 | `vvp`已安装 |
| GTKWave | 已安装，版本3.3.104 |
| Make | 已安装 |
| VS Code HDL扩展 | `mshr-h.veriloghdl` 1.29.0已安装 |

因此当前电脑不需要重新安装核心软件。

如果以后换到另一台Ubuntu电脑，可安装：

```bash
sudo apt update
sudo apt install iverilog gtkwave make
```

安装后检查：

```bash
iverilog -V
vvp -V
gtkwave --version
```

## 3. Verilog语言边界

作业文件统一使用`.v`，编译标准统一为Verilog-2005：

```bash
iverilog -g2005 ...
```

后续代码使用：

- `wire`表示由连续赋值、模块输出等驱动的连线；
- `reg`表示在`always`或`initial`过程块中赋值的变量；
- 组合逻辑使用`always @(*)`；
- 时序逻辑使用`always @(posedge clk)`或带异步复位的敏感表；
- 状态编码使用`localparam`；
- 时序寄存器使用非阻塞赋值`<=`；
- 组合过程块通常使用阻塞赋值`=`。

不使用以下SystemVerilog写法：

```text
logic
always_comb
always_ff
typedef enum
interface
class
```

tiny-NPU原项目大量使用`.sv`和SystemVerilog语法。作业会学习其硬件思想，但独立代码要改写为Verilog-2005形式。

## 4. VS Code扩展

当前已经安装`mshr-h.veriloghdl`，它支持Verilog语法高亮，并可调用Icarus Verilog进行保存时检查。无需再安装另一套Verilog运行扩展。

当前还装有其他Verilog扩展。如果出现重复高亮、重复报错或多个运行按钮，建议在VS Code扩展面板中只为本工作区启用`Verilog-HDL/SystemVerilog`，把其他功能重叠的Verilog扩展设置为“禁用（工作区）”。这不会卸载它们。

打开命令面板后可运行：

```text
Verilog: Doctor
```

它用于检查Icarus、格式化器、Ctags和其他可选工具是否能被扩展找到。

格式化器和Ctags目前不是完成作业的必需项。即使它们没有安装，也不影响编辑、编译、仿真与波形查看。

## 5. 工作区settings.json

在`NPU_learing/.vscode/settings.json`使用以下配置：

```json
{
    "files.associations": {
        "*.v": "verilog"
    },
    "[verilog]": {
        "editor.tabSize": 4,
        "editor.insertSpaces": true
    },
    "verilog.linting.linter": "iverilog",
    "verilog.linting.iverilog.arguments": "-Wall",
    "verilog.linting.iverilog.includePath": [
        "assignments/assignment-01-bank-router/rtl"
    ],
    "verilog.linting.iverilog.verilogHDL.standard": "Verilog-2005",
    "verilog.linting.iverilog.runAtFileLocation": false
}
```

含义：

- 把`.v`识别成Verilog；
- 使用4空格缩进；
- 保存或打开Verilog文件时调用Icarus做单文件检查；
- 使用Verilog-2005规则；
- `-Wall`开启常见警告；
- 告诉检查器到RTL目录查找被例化的模块。

扩展的单文件检查只能提供快速反馈。包含RTL与Testbench的完整工程仍需使用下面的编译命令。

## 6. 作业目录结构

第一题建议采用：

```text
NPU_learing/
├── .vscode/
│   ├── settings.json
│   └── tasks.json
├── assignments/
│   └── assignment-01-bank-router/
│       ├── rtl/
│       │   └── bank_access_router.v
│       ├── tb/
│       │   └── bank_access_router_tb.v
│       ├── build/
│       └── waves/
└── docs/
```

各目录作用：

- `rtl/`：可综合的设计代码；
- `tb/`：只用于仿真的Testbench；
- `build/`：Icarus生成的`.vvp`文件；
- `waves/`：Testbench生成的`.vcd`波形；
- `docs/`：硬件原理、代码讲解与波形说明。

## 7. Testbench怎样生成波形

在Testbench中加入：

```verilog
`timescale 1ns/1ps

module bank_access_router_tb;

    initial begin
        $dumpfile("waves/bank_access_router.vcd");
        $dumpvars(0, bank_access_router_tb);
    end

    // 激励、自检和DUT例化后续逐步加入

endmodule
```

- `$dumpfile`指定VCD文件路径；
- `$dumpvars(0, bank_access_router_tb)`从Testbench顶层开始记录信号；
- 组合电路题不需要产生时钟；
- 时序电路和FSM题才需要在Testbench中生成`clk`与复位。

## 8. 手动编译、运行与看波形

在VS Code中打开`NPU_learing`目录，然后打开集成终端：

```bash
cd assignments/assignment-01-bank-router
mkdir -p build waves
```

编译：

```bash
iverilog -g2005 -Wall \
    -s bank_access_router_tb \
    -o build/bank_access_router.vvp \
    rtl/bank_access_router.v \
    tb/bank_access_router_tb.v
```

参数含义：

- `-g2005`：按Verilog-2005解析；
- `-Wall`：打开常见警告；
- `-s bank_access_router_tb`：指定Testbench为仿真顶层；
- `-o`：指定输出仿真程序；
- 最后列出RTL和Testbench源文件。

运行：

```bash
vvp build/bank_access_router.vvp
```

查看波形：

```bash
gtkwave waves/bank_access_router.vcd
```

Icarus的标准工作流就是“`iverilog`编译→`vvp`运行”。GTKWave可以直接打开VCD。

## 9. VS Code一键任务

在`NPU_learing/.vscode/tasks.json`写入：

```json
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "Verilog: build assignment 1",
            "type": "shell",
            "command": "iverilog",
            "args": [
                "-g2005",
                "-Wall",
                "-s", "bank_access_router_tb",
                "-o", "assignments/assignment-01-bank-router/build/bank_access_router.vvp",
                "assignments/assignment-01-bank-router/rtl/bank_access_router.v",
                "assignments/assignment-01-bank-router/tb/bank_access_router_tb.v"
            ],
            "options": {
                "cwd": "${workspaceFolder}"
            },
            "problemMatcher": ["$gcc"],
            "group": {
                "kind": "build",
                "isDefault": true
            }
        },
        {
            "label": "Verilog: simulate assignment 1",
            "type": "shell",
            "command": "vvp",
            "args": [
                "build/bank_access_router.vvp"
            ],
            "options": {
                "cwd": "${workspaceFolder}/assignments/assignment-01-bank-router"
            },
            "dependsOn": "Verilog: build assignment 1",
            "problemMatcher": []
        },
        {
            "label": "Verilog: open assignment 1 waveform",
            "type": "shell",
            "command": "gtkwave",
            "args": [
                "waves/bank_access_router.vcd"
            ],
            "options": {
                "cwd": "${workspaceFolder}/assignments/assignment-01-bank-router"
            },
            "dependsOn": "Verilog: simulate assignment 1",
            "problemMatcher": []
        }
    ]
}
```

使用方法：

- `Ctrl+Shift+B`：执行默认编译任务；
- 命令面板选择`Tasks: Run Task`；
- 选择仿真任务，自动先编译再运行；
- 选择波形任务，自动编译、仿真并打开GTKWave。

首次运行任务前需要确保`build/`和`waves/`目录已经创建。

## 10. 如何判断环境真正可用

不能只看VS Code里有语法颜色。完整验证标准是：

1. `iverilog`退出码为0，没有语法错误；
2. `vvp`实际运行Testbench；
3. 自检Testbench打印通过结果；
4. `waves/*.vcd`真实生成且文件非空；
5. GTKWave能打开VCD并显示预期信号；
6. 波形与Testbench断言结论一致。

VS Code红线消失只说明快速检查没有发现当前文件的问题，不代表整个模块功能正确。

## 11. 常见问题

### 11.1 报错找不到模块

完整编译命令必须同时列出被测RTL和Testbench，或者使用文件列表。只编译Testbench无法找到DUT。

### 11.2 使用了logic或always_comb后报错

这些是SystemVerilog语法。本作业使用Verilog，应改为`reg/wire`和`always @(*)`，而不是把编译参数偷偷改成`-g2012`。

### 11.3 没有生成VCD

检查Testbench是否执行了`$dumpfile`和`$dumpvars`，仿真是否真正运行，以及`waves/`目录是否存在。

### 11.4 GTKWave打开后没有信号

先在左侧层级树选择Testbench或DUT，再把需要的信号加入波形窗口。VCD存在不代表GTKWave会自动把所有信号放到显示区。

### 11.5 VS Code出现重复报错

可能是多个Verilog扩展同时启用了lint。为当前工作区只保留一个主扩展负责Icarus检查。

## 12. 下一步

环境层面已经具备条件。下一阶段应先从硬件角度讲第一题的4请求、4Bank路由结构和组合关键路径，然后创建`.vscode/settings.json`、作业目录与第一版`bank_access_router.v`模块框架，执行第一次`iverilog -g2005`语法检查。

## 13. 官方参考

- [Icarus Verilog入门](https://steveicarus.github.io/iverilog/usage/getting_started.html)：说明`iverilog`编译、`vvp`运行、多个源文件和`-s`顶层选择。
- [Icarus Verilog命令行文档](https://steveicarus.github.io/iverilog/usage/command_line_flags.html)：编译选项与语言标准参数。
- [GTKWave文档](https://gtkwave.github.io/gtkwave/man/gtkwave.1.html)：VCD等波形格式和启动方式。
- [VS Code Verilog-HDL扩展](https://marketplace.visualstudio.com/items?itemName=mshr-h.veriloghdl)：Icarus lint、Verilog-2005设置、Doctor命令和波形查看功能。
