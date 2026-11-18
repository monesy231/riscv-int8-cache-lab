#include "gemv.h"

void matmul_int8(int32_t *C, const int8_t *A, const int8_t *B,
                 int dimD, int dimN)
{
    asm volatile(

        "addi  x10, %[C], 0\n\t"       /* x10 = C */
        "addi  x11, %[A], 0\n\t"       /* x11 = A */
        "addi  x12, %[B], 0\n\t"       /* x12 = B */
        "addi  x13, %[dimD], 0\n\t"    /* x13 = dimD */
        "addi  x14, %[dimN], 0\n\t"    /* x14 = dimN */

        /*
         * x5  = i
         * x6  = j
         * x7  = sum
         * x28 = offset / temp
         * x29 = address temp
         * x30 = A[i][j] / product
         * x31 = B[j]
         */

        "addi  x5, x0, 0\n\t"          /* i = 0 */

        "ROW_LOOP_%=:\n\t"
        "blt   x5, x13, ROW_BODY_%=\n\t"
        "jal   x0, MATMUL_DONE_%=\n\t"

        "ROW_BODY_%=:\n\t"
        "addi  x6, x0, 0\n\t"          /* j = 0 */
        "addi  x7, x0, 0\n\t"          /* sum = 0 */

        "COL_LOOP_%=:\n\t"
        "blt   x6, x14, COL_BODY_%=\n\t"
        "jal   x0, STORE_RESULT_%=\n\t"

        "COL_BODY_%=:\n\t"

        /* offset = i * dimN + j */
        "mul   x28, x5, x14\n\t"
        "add   x28, x28, x6\n\t"

        /* load A[i][j] */
        "add   x29, x11, x28\n\t"
        "lb    x30, 0(x29)\n\t"

        /* load B[j] */
        "add   x29, x12, x6\n\t"
        "lb    x31, 0(x29)\n\t"

        /* sum += A[i][j] * B[j] */
        "mul   x30, x30, x31\n\t"
        "add   x7, x7, x30\n\t"

        "addi  x6, x6, 1\n\t"          /* j++ */
        "jal   x0, COL_LOOP_%=\n\t"

        "STORE_RESULT_%=:\n\t"
        "slli  x28, x5, 2\n\t"         /* offset = i * 4 */
        "add   x29, x10, x28\n\t"
        "sw    x7, 0(x29)\n\t"         /* C[i] = sum */

        "addi  x5, x5, 1\n\t"          /* i++ */
        "jal   x0, ROW_LOOP_%=\n\t"

        "MATMUL_DONE_%=:\n\t"

        :
        : [C] "r" (C),
          [A] "r" (A),
          [B] "r" (B),
          [dimD] "r" (dimD),
          [dimN] "r" (dimN)
        : "x10", "x11", "x12", "x13", "x14",
          "x5", "x6", "x7", "x28", "x29", "x30", "x31",
          "memory"
    );
}
