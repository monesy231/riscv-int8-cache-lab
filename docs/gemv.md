# GEMV 与 MAC4 指令

矩阵 `A` 按行存放，向量 `B` 的长度等于矩阵列数。每个输出 `C[i]` 是 `A` 的第 `i` 行与 `B` 的点积。输入以有符号字节解释，结果取累加和的低 32 位。RARS 例程与 C 演示程序使用同一组输入，其中第一行 `[1, -2, 3, -4, 5, -6, 7, -8]` 与 `[2, -1, 3, 4, -2, 5, -3, 1]` 的点积为 `-72`。

## C 参考与标量汇编

[C 参考实现](../sw/gemv_ref.c) 用无符号 32 位变量累加乘积，再按有符号 32 位值解释结果，与 RV32 的寄存器回绕一致。生成预处理源码、汇编、目标文件和反汇编的命令如下。

```bash
mkdir -p build
gcc -std=c11 -E sw/gemv_ref.c -o build/gemv_ref.i
gcc -std=c11 -O0 -S build/gemv_ref.i -o build/gemv_ref.s
gcc -c build/gemv_ref.s -o build/gemv_ref.o
objdump -dr build/gemv_ref.o
```

[RARS 例程](../sw/gemv_rars.asm) 用 `a0` 至 `a4` 传入结果、矩阵、向量的基地址和行列数，用 `jal` 调用计算子程序。内层循环把 `i × cols + j` 加到矩阵基址，用 `lb` 读取并符号扩展两个字节，然后用 `mul` 和 `add` 更新和。写回前用 `slli` 把结果索引乘以 4。可在 `matmul_int8` 和 `store_result` 设断点，观察 `ra`、`sp`、`t2` 和结果数组。

使用 [RARS 1.6](https://github.com/TheThirdOne/rars/releases/tag/v1.6) 运行。

```bash
java -jar rars1_6.jar nc me ae1 se2 sm sw/gemv_rars.asm
```

[标量内联汇编](../sw/gemv_scalar.c) 把同一计算过程包进 C 函数。`%=` 为汇编中的跳转标签生成唯一后缀。寄存器 clobber 列出汇编改写的寄存器，`memory` 声明从指针取数和写结果所涉及的内存副作用。

## MAC4 编码与数据布局

[MAC4 内联汇编](../sw/gemv_mac4.c) 每次用两条 `lw` 各读取四个连续字节，将四对有符号 INT8 的乘积加到 `t2`，列索引每步加 4。矩阵和向量指针均需 4 字节对齐，列数为 4 的倍数，因此矩阵每行的起始地址也对齐。

```asm
.insn r 0x0b, 0x0, 0x00, t2, t5, t6
```

这条 R 型指令编码为 `0x01ff038b`。低 7 位 `0x0b` 对应 `custom-0`，`funct3` 和 `funct7` 为零，`rd`、`rs1`、`rs2` 分别为 `x7`、`x30`、`x31`。每组的第一个字节在小端字的最低 8 位。指令将四路点积与旧目的寄存器相加，再把结果写回。 [RISC-V 指令编码表](https://docs.riscv.org/reference/isa/unpriv/rv-32-64g.html)

下面用带 RV32IM 支持的 GNU 工具链生成对象。工具链前缀通过 `RV` 指定。

```bash
mkdir -p build
RV=riscv32-unknown-elf
"${RV}-gcc" -std=gnu11 -O2 -march=rv32im -mabi=ilp32 -c sw/gemv_scalar.c -o build/gemv_scalar.o
"${RV}-gcc" -std=gnu11 -O2 -march=rv32im -mabi=ilp32 -c sw/gemv_mac4.c -o build/gemv_mac4.o
"${RV}-objdump" -dr build/gemv_mac4.o
```

使用提供 C 运行库的交叉工具链时，可将任一对象与 `sw/demo.c` 一起链接，再在支持相应指令集的运行环境中执行。对照硬件时，[算术单元自检](../tests/tb_arithmetic.sv) 将第一行拆成两组，验证 Verilog 分别输出 `-3` 和 `-69`，由调用方累加得到 `-72`。
