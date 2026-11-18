# RISC-V INT8 点积加速与缓存微架构实验 (`riscv-int8-cache-lab`)

本项目围绕 **RV32 架构下的有符号 INT8 矩阵向量乘法（GEMV）软硬件协同加速** 与 **独立直接映射指令/数据缓存（ICache / DCache）微架构设计** 展开。

软件侧从标准 C11 参考实现出发，对照演示了 RV32IM 标量汇编与基于 `custom-0`（`0x0B`）扩展操作码空间的自定义四路打包点积指令 `MAC4`；硬件 RTL 侧提供了 32 位有符号 Radix-2 Booth 乘法器、四路并行 INT8 点积单元，以及支持整行重填（Line Refill）、写穿（Write-Through）、写不分配（No-Write-Allocate）、字节写掩码合并、总线反压握手与 `0xFFFF_xxxx` 外设地址空间 MMIO 旁路的 1 KiB 直接映射 ICache 与 DCache。

---

## 核心特性与架构指标

| 子系统 | 模块 / 文件 | 关键架构参数与设计特性 |
| :--- | :--- | :--- |
| **GEMV 算子实现** | [`sw/`](sw/) | 有符号 `int8_t` 矩阵 $A_{D \times N}$ 乘向量 $B_{N \times 1} \to \text{int32\_t } C_{D \times 1}$，遵循 RV32 低 32 位二补数截断语义；涵盖 C11 参考、RARS 汇编、RV32IM 标量内联汇编及 `MAC4` 自定义指令内联汇编 |
| **自定义指令 `MAC4`** | [`sw/gemv_mac4.c`](sw/gemv_mac4.c) | R-Type 格式，占用 `custom-0`（`opcode = 7'b0001011` / `0x0B`，`funct3 = 0x0`，`funct7 = 0x00`），单指令完成 `rs1`、`rs2` 中 4 对有符号 INT8 解包相乘与四路求和累加 |
| **有符号 Booth 乘法器** | [`rtl/multiplier.v`](rtl/multiplier.v) | 32 位有符号输入 $\to$ 64 位乘积输出；采用 33 位符号扩展累加器防 `-2^31` 取反溢出；Radix-2 Booth 移位加减架构，固定 **32 个时钟上升沿**完成计算，支持 `start` / `busy` 握手 |
| **四路 INT8 点积单元** | [`rtl/mac.v`](rtl/mac.v) | 并行例化 4 个 `multiplier` 核，对两路 32 位输入按字节切片并符号扩展至 32 位，输出四路乘积之和（范围 $[-65024, +65536]$），固定 **33 个时钟上升沿**完成计算 |
| **指令缓存 (ICache)** | [`rtl/ICache.v`](rtl/ICache.v) | 1 KiB 直接映射（64 行 × 16 B/行，每行 4 个 32 位字）；缓存 `0x0000_0000`–`0x0000_7FFF`（32 KiB 空间）；4 状态机驱动 128 位整行对齐重填与单周期字选返回 |
| **数据缓存 (DCache)** | [`rtl/DCache.v`](rtl/DCache.v) | 1 KiB 直接映射（64 行 × 16 B/行）；读写双状态机共享单端口同步写优先行 RAM（[`rtl/cache_line_ram.v`](rtl/cache_line_ram.v)）；**Write-Through + No-Write-Allocate** 策略；支持 4 位字节掩码（`data_wen`）、CPU 停顿同地址重读抑制及 `0xFFFF_xxxx` MMIO 旁路 |

---

## 仓库目录结构与文档导航

```text
riscv-int8-cache-lab/
├── docs/
│   ├── gemv.md            # GEMV 算法定义、标量与 MAC4 内联汇编对照、指令编码细节
│   ├── arithmetic.md      # 32 位 Radix-2 Booth 乘法器与四路并行点积单元时序及接口说明
│   ├── cache.md           # ICache / DCache 地址划分、行存储格式、状态机与写策略说明
│   └── results.md         # Minisys 开发板 Llama 2 推理吞吐率与 SoC 仿真实验记录
├── rtl/
│   ├── multiplier.v       # 32 位有符号 Radix-2 Booth 乘法器 (32 周期)
│   ├── mac.v              # 四路有符号 INT8 解包并行点积单元 (33 周期)
│   ├── cache_line_ram.v   # 64×134-bit 单端口同步写优先缓存行 RAM (支持异步全局清有效位)
│   ├── ICache.v           # 直接映射指令缓存控制器
│   └── DCache.v           # 直接映射数据缓存控制器 (含写穿、写不分配与 MMIO 旁路)
├── sw/
│   ├── gemv.h             # matmul_int8 统一函数接口声明
│   ├── demo.c             # 4×8 INT8 矩阵点积自检入口与期望值校验
│   ├── gemv_ref.c         # 可移植 C11 参考实现 (显式低 32 位二补数回绕)
│   ├── gemv_rars.asm      # RARS 1.6 独立可运行 RV32IM 汇编实现
│   ├── gemv_scalar.c      # GCC RV32IM 标量内联汇编实现 (lb + mul + add)
│   └── gemv_mac4.c        # GCC RV32 自定义 MAC4 指令内联汇编实现 (.insn r 0x0B)
├── tests/
│   ├── tb_arithmetic.sv   # Booth 乘法器极值边界与 MAC4 点积 SystemVerilog 自检平台
│   ├── tb_icache.sv       # ICache 缺失重填、字偏移命中、冲突替换与复位自检平台
│   └── tb_dcache.sv       # DCache 读写命中/缺失、字节掩码写穿、反压与 MMIO 自检平台
└── tools/
    └── check.py           # 自动化编译与 RTL 仿真验证脚本 (支持波形导出)
```

| 专题文档 | 关注重点 | 对应源码与测试 |
| :--- | :--- | :--- |
| [GEMV 与 MAC4 指令](docs/gemv.md) | 一行 INT8 数据如何通过标量或单指令四路点积生成 INT32 结果 | [`sw/gemv_rars.asm`](sw/gemv_rars.asm)、[`sw/gemv_scalar.c`](sw/gemv_scalar.c)、[`sw/gemv_mac4.c`](sw/gemv_mac4.c) |
| [Booth 乘法器与 MAC4](docs/arithmetic.md) | 33 位扩展 Booth 移位加减原理、四路并行乘法器组织与握手时序 | [`rtl/multiplier.v`](rtl/multiplier.v)、[`rtl/mac.v`](rtl/mac.v)、[`tests/tb_arithmetic.sv`](tests/tb_arithmetic.sv) |
| [缓存结构和接口](docs/cache.md) | 1 KiB 直接映射地址映射、缺失重填、部分字节写入、总线反压与外设旁路 | [`rtl/ICache.v`](rtl/ICache.v)、[`rtl/DCache.v`](rtl/DCache.v)、[`rtl/cache_line_ram.v`](rtl/cache_line_ram.v)、[`tests/tb_icache.sv`](tests/tb_icache.sv)、[`tests/tb_dcache.sv`](tests/tb_dcache.sv) |
| [性能记录](docs/results.md) | 量化模型上板实测吞吐率、SoC 下 MAC4 加速比与缓存命中率数据 | 实验测试结果汇总 |

---

## 实验原理与关键技术细节

### 1. 有符号 INT8 GEMV 与 `MAC4` 自定义指令扩展

#### 算子语义
给定按行主序存储的有符号矩阵 $A \in [-128, 127]^{D \times N}$ 与有符号列向量 $B \in [-128, 127]^{N}$，输出向量 $C \in \mathbb{Z}_{32}^{D}$ 的第 $i$ 行元素定义为：

$$C[i] = \sum_{j=0}^{N-1} \operatorname{sext}_{32}\!\big(A[i \cdot N + j]\big) \times \operatorname{sext}_{32}\!\big(B[j]\big) \pmod{2^{32}}$$

- **C11 参考实现（[`sw/gemv_ref.c`](sw/gemv_ref.c)）**：为避免 C 语言有符号整数溢出未定义行为（UB），在 `uint32_t` 域中完成乘加累积，最后按二补数语义转换为 `int32_t`，与 32 位 RISC-V 通用寄存器的截断行为严格一致。
- **RV32IM 标量实现（[`sw/gemv_rars.asm`](sw/gemv_rars.asm) / [`sw/gemv_scalar.c`](sw/gemv_scalar.c)）**：内层循环每次通过 `lb` 加载 1 字节并自动符号扩展至 32 位，执行 `mul` 与 `add`，列指针步进 1 字节。
- **`MAC4` 打包向量化实现（[`sw/gemv_mac4.c`](sw/gemv_mac4.c)）**：当输入缓冲区按 4 字节对齐（如 [`sw/demo.c`](sw/demo.c) 中的 `_Alignas(4)`）且列数 `dimN` 为 4 的倍数时，内层循环通过两条 `lw` 一次性加载 $A$、$B$ 的连续 4 个 `int8_t` 元素至 `t5 (x30)` 与 `t6 (x31)`，列索引步进 4，将内存加载次数与循环分支开销降低 75%。

#### `MAC4` 指令编码（R-Type `custom-0`）
在 [`sw/gemv_mac4.c`](sw/gemv_mac4.c) 中通过 GNU 汇编器 `.insn` 伪指令编码：

```c
.insn r 0x0B, 0x0, 0x00, t2, t5, t6   // 对应机器码: 0x01ff038b
```

| 位域 `[31:25]` | 位域 `[24:20]` | 位域 `[19:15]` | 位域 `[14:12]` | 位域 `[11:7]` | 位域 `[6:0]` |
| :---: | :---: | :---: | :---: | :---: | :---: |
| `funct7` | `rs2` | `rs1` | `funct3` | `rd` | `opcode` |
| `7'b0000000` (`0x00`) | `x31` (`t6`) | `x30` (`t5`) | `3'b000` (`0x0`) | `x7` (`t2`) | `7'b0001011` (`0x0B`, `custom-0`) |

**指令级语义**：

$$\text{rd} \leftarrow \text{rd} + \sum_{k=0}^{3} \operatorname{sext}_{32}\!\big(\text{rs1}[8k+7 : 8k]\big) \times \operatorname{sext}_{32}\!\big(\text{rs2}[8k+7 : 8k]\big)$$

> **硬件分工说明**：仓库中的 [`rtl/mac.v`](rtl/mac.v) 模块负责计算四路字节乘积之和 `z[31:0]`；当集成至支持 `MAC4` 的 RV32 处理器核时，由处理器写回通路将 `z` 与目标寄存器 `rd` 原值相加写回。

---

### 2. 32 位 Booth 乘法器与四路并行点积单元 (`rtl/multiplier.v`, `rtl/mac.v`)

#### 32 位有符号 Radix-2 Booth 乘法器（[`rtl/multiplier.v`](rtl/multiplier.v)）
- **防溢出位宽设计**：内部累加器 `a[32:0]` 与被乘数寄存器 `m[32:0] = {x[31], x}` 均扩展为 **33 位有符号数**。当被乘数取极值 $x = -2^{31}$（`32'h8000_0000`）时，32 位二补数取反会溢出回自身，而 33 位扩展表示（`33'h1_8000_0000`）可保证 `a - m` 加减运算符号绝对正确。
- **单步迭代逻辑**：每个时钟周期检查 `{q[0], q_1}`：
  - `2'b01`：`a_calc = a + m`
  - `2'b10`：`a_calc = a - m`
  - `2'b00` / `2'b11`：`a_calc = a`
  随后对 66 位拼接向量 `{a_calc, q, q_1}` 执行 1 位算术右移（最高位填充 `a_calc[32]`）。
- **时序与握手**：空闲状态下（`!busy`）收到 `start` 高电平时锁存操作数并将 `busy` 置 1（计算期间忽略后续 `start` 脉冲）；计数器 `count` 从 `0` 计至 `31`，共经历 **32 个时钟上升沿**后输出 64 位乘积 `z <= {a_shift[31:0], q_shift}` 并将 `busy` 清零。

#### 四路并行点积单元（[`rtl/mac.v`](rtl/mac.v)）
- **通道解包与并行度**：将 32 位打包输入 `x`、`y` 按字节切分为 4 个通道（`[7:0]`、`[15:8]`、`[23:16]`、`[31:24]`），各自通过 `{{24{byte[7]}}, byte}` 符号扩展为 32 位后，同时驱动 4 个并行的 `multiplier` 实例（`U_mul0`–`U_mul3`）。
- **求和与动态范围**：单路有符号 INT8 乘积范围为 $[-128 \times 127, -128 \times -128] = [-16256, +16384]$，四路求和范围为 $[-65024, +65536]$，远小于 `int32_t` 表示上限，因此直接截取四路 64 位乘积的低 32 位相加（`p0[31:0] + p1[31:0] + p2[31:0] + p3[31:0]`）不会发生截断溢出。
- **时序**：4 个乘法器同拍启动、同拍结束（32 个上升沿），第 **33 个时钟上升沿**锁存求和结果至 `z[31:0]` 并拉低 `busy`。

---

### 3. 直接映射 ICache 与 DCache 微架构 (`rtl/cache_line_ram.v`, `rtl/ICache.v`, `rtl/DCache.v`)

#### 几何参数与物理地址划分
`ICache` 与 `DCache` 均采用 **1 KiB 直接映射（Direct-Mapped）** 结构，包含 64 个缓存行（Lines），每行大小 16 字节（128 bits = 4 × 32-bit Words），覆盖低 32 KiB 可缓存内存区间（`0x0000_0000`–`0x0000_7FFF`）：

```text
 31                15 14       10 9         4 3           2 1         0
+--------------------+-----------+-----------+-------------+-----------+
|   Upper Address    |    Tag    |   Index   | Word Offset |Byte Offset|
|  (0xFFFF => MMIO)  |  (5 bits) |  (6 bits) |   (2 bits)  |  (2 bits) |
+--------------------+-----------+-----------+-------------+-----------+
```

- **行存储格式（[`rtl/cache_line_ram.v`](rtl/cache_line_ram.v)，134 bits/行）**：`{valid (1b), tag (5b), data (128b)}`。块内 4 个 32 位字按小端序存放：`data[31:0]` 对应块内偏移 `2'b00`，`data[127:96]` 对应块内偏移 `2'b11`。
- **快速复位与写优先转发**：`cache_line_ram` 将有效位独立为 `reg [63:0] valid`，异步高电平 `rst` 仅需单拍即可将全部 64 行置为无效；同拍写使能 `we` 有效时直接将新写入的 `{1'b1, d[132:0]}` 转发至输出寄存器 `q`（Write-First）。

#### ICache 控制流（[`rtl/ICache.v`](rtl/ICache.v)）
采用 4 状态有限状态机（`IDLE` $\to$ `LOOKUP` $\to$ `WAIT_RRDY` $\to$ `WAIT_RDATA`）：
1. **命中路径**：`IDLE` 接收 `inst_rreq` 并触发 `U_isram` 同步读；下一拍在 `LOOKUP` 比较 `cache_valid && (cache_tag == req_tag)`。若命中，当拍根据 `req_word_off` 选出 32 位指令并拉高 1 周期 `inst_valid`。
2. **缺失与整行重填路径**：若未命中，将访存地址按 16 字节边界对齐（`{req_addr[31:4], 4'b0000}`）并置 `cpu_ren = 4'hF`。若此时 `dev_rrdy` 已就绪则直接进入 `WAIT_RDATA`，否则在 `WAIT_RRDY` 等待总线就绪；待下游返回 `dev_rvalid` 与 128 位缓存行数据后，写入 `U_isram` 并同时将所请求的 32 位字输出至 `inst_out`。

#### DCache 读写双状态机、写策略与外设旁路（[`rtl/DCache.v`](rtl/DCache.v)）
1. **读写双状态机**：内部维护独立的读 FSM（`R_IDLE`, `R_LOOKUP`, `R_WAIT_RRDY`, `R_WAIT_RDATA`）与写 FSM（`W_IDLE`, `W_LOOKUP`, `W_WAIT_WRDY`, `W_WAIT_RESP`），按状态优先级共享单端口 `U_dsram`。
2. **Write-Through（写穿）+ No-Write-Allocate（写不分配）**：
   - **写命中（Write Hit）**：在 `W_LOOKUP` 中将 `w_req_wdata` 按 4 位字节写使能 `w_req_wen` 合并进当前缓存行的对应字，写回 `U_dsram` 的同时驱动 `cpu_wen` / `cpu_waddr` / `cpu_wdata` 写入下游存储。
   - **写缺失（Write Miss）**：仅向后端总线发起写请求，**不替换、不分配** `U_dsram` 中当前 Index 位置的原有缓存行，保证已有读热点数据不被流式写冲刷。
   - **写完成响应**：写请求发出后进入 `W_WAIT_RESP`，待下游设备处理完毕并重新拉高 `dev_wrdy` 时产生单周期 `data_wresp` 脉冲。
3. **MMIO 外设访问旁路（Uncached Bypass）**：
   - 当 `data_addr[31:16] == 16'hFFFF` 时识别为外设访问（`uncached`）：读写均跳过 `U_dsram` 查询与更新；读操作直接向总线发出未对齐的原始地址与字节掩码 `req_ren`，并在 `dev_rvalid` 时从 `dev_rdata[31:0]` 返回数据。
4. **CPU 停顿期间连续读抑制（`r_done_hold`）**：
   - 当 CPU 因外部原因停顿并在 `data_valid` 返回后继续保持相同的 `data_ren` 和 `data_addr` 时，`r_done_hold` 与 `r_done_addr` 锁存机制会抑制重复启动读事务，直至 `data_ren` 撤除或地址改变。

---

## 快速开始与验证指南

### 1. 环境依赖
- **Python 3**（运行自动化测试脚本 [`tools/check.py`](tools/check.py)）
- **C 编译器**：`gcc` 或 `clang`（支持 C11 标准）
- **Verilog 仿真器**：[Icarus Verilog](https://steveicarus.github.io/iverilog/)（提供 `iverilog` 与 `vvp`，支持 IEEE 1800-2012 SystemVerilog）

在 Debian / Ubuntu 环境中可通过以下命令一键安装：
```bash
sudo apt update && sudo apt install -y python3 gcc iverilog
```

### 2. 运行一键全量自检
在仓库根目录下执行（Windows 环境可将 `python3` 替换为 `python`）：

```bash
python3 tools/check.py
```

脚本会依次编译运行 C11 GEMV 参考程序（计算 4×8 有符号 INT8 矩阵点积），并调用 `iverilog` + `vvp` 执行三组 RTL 模块级测试平台。全部通过时的标准输出如下：

```text
-72 9 -1662 -37
PASS signed Booth multiplier and packed INT8 dot product
PASS ICache miss, refill, word select, conflict, and reset
PASS DCache refill, write-through, no-write-allocate, backpressure, and MMIO
```

### 3. 分项测试与波形调试命令

| 验证目标 | 执行命令 | 产物与说明 |
| :--- | :--- | :--- |
| **仅运行 C11 GEMV 参考测试** | `python3 tools/check.py gemv` | 编译 [`sw/demo.c`](sw/demo.c) + [`sw/gemv_ref.c`](sw/gemv_ref.c) 至 `build/gemv` 并校验输出 `-72 9 -1662 -37` |
| **切换 Clang 编译器运行** | `python3 tools/check.py gemv --cc clang` | 使用 `clang -std=c11 -O2 -Wall -Wextra -Werror` 编译校验 |
| **仅运行 RTL 仿真自检** | `python3 tools/check.py rtl` | 依次编译并运行 `tb_arithmetic`、`tb_icache`、`tb_dcache` |
| **导出 VCD 仿真波形** | `python3 tools/check.py rtl --waves` | 在 `build/` 目录下生成 `tb_arithmetic.vcd`、`tb_icache.vcd`、`tb_dcache.vcd`，可用 GTKWave 查看 |
| **RARS 模拟器运行 RV32IM 汇编** | `java -jar rars1_6.jar nc me ae1 se2 sm sw/gemv_rars.asm` | 需准备 RARS 1.6 JAR 包，直接运行 [`sw/gemv_rars.asm`](sw/gemv_rars.asm) 并输出 `-72 9 -1662 -37` |
| **交叉编译与反汇编检查 `MAC4`** | `riscv32-unknown-elf-gcc -march=rv32im -mabi=ilp32 -O2 -c sw/gemv_mac4.c -o build/gemv_mac4.o && riscv32-unknown-elf-objdump -d build/gemv_mac4.o` | 验证内联汇编生成的自定义指令字 `0x01ff038b` |

### 4. 测试用例覆盖矩阵

| 测试套件 | 源码路径 | 核心验证场景与边界条件 |
| :--- | :--- | :--- |
| **GEMV 基准测试** | [`sw/demo.c`](sw/demo.c) | 4×8 矩阵乘 8 维向量：覆盖正负交替行、`[-128, 127]` 极值饱和行及稀疏含零行，校验四行点积结果 `[-72, 9, -1662, -37]` |
| **算术单元 Testbench** | [`tests/tb_arithmetic.sv`](tests/tb_arithmetic.sv) | ① 7 组 32 位有符号 Booth 乘法（含零、正负混合、`-2^31 * -1`、`-2^31 * -2^31`、`-2^31 * (2^31-1)`、`max * max`）及 `busy` 期间额外 `start` 脉冲忽略检查；<br>② 四路 INT8 点积上界 `+65536`（4 组 `-128 * -128`）与下界 `-65024`（4 组 `-128 * 127`）；<br>③ 连续两次调用 `mac` 复现 `demo.c` 第 0 行前 4 项（`-3`）与后 4 项（`-69`）累加得 `-72` |
| **ICache Testbench** | [`tests/tb_icache.sv`](tests/tb_icache.sv) | ① 模拟 6 周期 `dev_rrdy` 延迟下的冷启动缺失与 16 B 对齐重填（访问 `0x128` 触发 `0x120` 整行加载）；<br>② 同行其它字偏移（`0x120`、`0x12c`）单周期零总线访问命中；<br>③ 同 Index 不同 Tag 地址（`0x528` vs `0x128`）冲突缺失替换；<br>④ `rst` 复位清空有效位后重新触发重填 |
| **DCache Testbench** | [`tests/tb_dcache.sv`](tests/tb_dcache.sv) | ① 读缺失整行重填、同行命中，以及保持 `data_ren` 不变时的重复读抑制；<br>② 写命中下的字节写掩码合并（`data_wen = 4'b0101` 将 `0x11223344` 与 `0xaabbccdd` 合并为 `0x11bb33dd`）与 `dev_wrdy` 反压等待；<br>③ 冲突地址（`0x434` vs `0x034`）写缺失时的 No-Write-Allocate 行为，确认原缓存行 `0x034` 未被驱逐；<br>④ `0xFFFF_0034` MMIO 外设读写旁路与反压握手，确认不污染缓存 |

---

## 实验性能评估记录

以下数据记录自本实验配套的 SoC 仿真环境与 Minisys FPGA 开发板实测（详见 [`docs/results.md`](docs/results.md)）：

### 1. SoC 仿真：GEMV 算子加速效果（Block Memory）
| 实现方案 | 仿真起始–结束时间 | 算子耗时 | 相对标量耗时比 | 加速比 |
| :--- | :---: | :---: | :---: | :---: |
| **RV32IM 标量内联汇编**（[`sw/gemv_scalar.c`](sw/gemv_scalar.c)） | `0.55 μs` – `222.93 μs` | `222.38 μs` | `100.0%` | `1.00×` |
| **`MAC4` 自定义指令内联汇编**（[`sw/gemv_mac4.c`](sw/gemv_mac4.c)） | `0.55 μs` – `83.92 μs` | **`83.37 μs`** | **`37.5%`** | **`2.67×`** |

### 2. SoC 仿真：ICache + DCache 开启前后对比
测试负载包含 **1,967 次指令读取** 与 **26 次数据读取**：

| 缓存配置 | 仿真总运行时间 | ICache 命中率 | 加速比 |
| :--- | :---: | :---: | :---: |
| 关闭 ICache 与 DCache | `4965.740 μs` | — | `1.00×` |
| **开启 ICache 与 DCache** | **`1257.040 μs`** | **`79.004%`** | **`3.95×`** |

### 3. Minisys 开发板实测：量化 Llama 2 端到端推理吞吐率
| 软件实现版本 | 实测推理速度 (`token/s`) | 相对上一阶段提升 | 相对纯 C 基准总提升 |
| :--- | :---: | :---: | :---: |
| 原始 C 语言实现 | `1.324899` | — | 基准 |
| RV32IM 标量内联汇编优化 | `1.533335` | `+15.73%` | `+15.73%` |
| **`MAC4` 自定义指令内联汇编优化** | **`1.730889`** | **`+12.88%`** | **`+30.64%`** |

> **复现范围说明**：本仓库包含独立的算术单元、缓存 RTL 及仿真存储器模型，可直接通过 `python3 tools/check.py` 完整复现算法与 RTL 仿真自检。要在处理器上实际执行 [`sw/gemv_mac4.c`](sw/gemv_mac4.c) 机器码或复现上述 SoC/上板数据，需配合集成 `MAC4` 译码写回通路的 RV32 处理器核与板级外设环境。
