# RISC-V INT8 点积与缓存实验

从一个有符号 INT8 矩阵向量乘法（GEMV）出发，对照 C、RV32IM 汇编和自定义 MAC4 指令的实现。RTL 部分包含 32 位 Booth 乘法器、由四个乘法器组成的点积单元，以及独立的直接映射指令缓存和数据缓存。

| 想了解 | 从这里开始 | 关键实现 |
| --- | --- | --- |
| 一行 INT8 数据如何生成一个 INT32 结果 | [GEMV 与 MAC4 指令](docs/gemv.md) | [RARS 汇编](sw/gemv_rars.asm)、[标量内联汇编](sw/gemv_scalar.c)、[MAC4 内联汇编](sw/gemv_mac4.c) |
| 有符号乘法与四路点积的时序 | [Booth 乘法器与 MAC4](docs/arithmetic.md) | [乘法器](rtl/multiplier.v)、[四路点积](rtl/mac.v) |
| 缓存如何处理缺失、部分写入和外设访问 | [缓存结构和接口](docs/cache.md) | [ICache](rtl/ICache.v)、[DCache](rtl/DCache.v)、[行 RAM](rtl/cache_line_ram.v) |

## 运行自检

从仓库根目录运行。准备 Python 3、GCC 或 Clang，以及提供 `iverilog` 和 `vvp` 的 Icarus Verilog。在 Debian 或 Ubuntu 上可用 `sudo apt install python3 gcc iverilog` 安装。 [Icarus Verilog 文档](https://steveicarus.github.io/iverilog/)

```bash
python3 tools/check.py
```

程序会先计算同一组 4×8 矩阵的四行点积，随后运行三组 RTL 自检。预期输出包括下面四行。

```text
-72 9 -1662 -37
PASS signed Booth multiplier and packed INT8 dot product
PASS ICache miss, refill, word select, conflict, and reset
PASS DCache refill, write-through, no-write-allocate, backpressure, and MMIO
```

可以使用 `python3 tools/check.py gemv` 单独运行 C 参考程序，或用 `python3 tools/check.py rtl --waves` 运行 RTL 自检并将 VCD 波形写到 `build/`。使用 Clang 时传入 `--cc clang`。Windows 上可以用 `python` 调用同一脚本。

## 实验记录

Block Memory 的 SoC 仿真中，GEMV 使用 MAC4 后的运行时间约为标量版本的 37.5%。另一组测试在开启 ICache 与 DCache 后，运行时间从 4965.740 μs 降到 1257.040 μs。测试环境、计算口径和上板推理测量见 [性能记录](docs/results.md)。

仓库里的缓存 RTL 配有同步行 RAM 和测试用存储设备，可独立跑仿真。执行 MAC4 版程序需要实现该指令的 RV32 处理器或模拟器。
