#include "gemv.h"

void matmul_int8(int32_t *C, const int8_t *A, const int8_t *B,
                 int dimD, int dimN)
{
    __asm__ __volatile__(
        "addi  a0, %[C], 0\n\t"
        "addi  a1, %[A], 0\n\t"
        "addi  a2, %[B], 0\n\t"
        "addi  a3, %[dimD], 0\n\t"
        "addi  a4, %[dimN], 0\n\t"

        "ori   t0, x0, 0\n\t"

        "ROW_LOOP_%=:\n\t"
        "blt   t0, a3, ROW_BODY_%=\n\t"
        "jal   x0, MATMUL_DONE_%=\n\t"

        "ROW_BODY_%=:\n\t"
        "ori   t1, x0, 0\n\t"
        "ori   t2, x0, 0\n\t"

        "COL_LOOP_%=:\n\t"
        "blt   t1, a4, COL_BODY_%=\n\t"
        "jal   x0, STORE_RESULT_%=\n\t"

        "COL_BODY_%=:\n\t"
        "mul   t3, t0, a4\n\t"
        "add   t3, t3, t1\n\t"

        "add   t4, a1, t3\n\t"
        "lw    t5, 0(t4)\n\t"

        "add   t4, a2, t1\n\t"
        "lw    t6, 0(t4)\n\t"

        /* MAC4 reads and updates the accumulator in t2. */
        ".insn r 0x0B, 0x0, 0x00, t2, t5, t6\n\t"

        "addi  t1, t1, 4\n\t"
        "jal   x0, COL_LOOP_%=\n\t"

        "STORE_RESULT_%=:\n\t"
        "slli  t3, t0, 2\n\t"
        "add   t4, a0, t3\n\t"
        "sw    t2, 0(t4)\n\t"

        "addi  t0, t0, 1\n\t"
        "jal   x0, ROW_LOOP_%=\n\t"

        "MATMUL_DONE_%=:\n\t"

        :
        : [C] "r" (C),
          [A] "r" (A),
          [B] "r" (B),
          [dimD] "r" (dimD),
          [dimN] "r" (dimN)
        : "a0", "a1", "a2", "a3", "a4",
          "t0", "t1", "t2", "t3", "t4", "t5", "t6",
          "memory"
    );
}
