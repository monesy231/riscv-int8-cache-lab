#include "gemv.h"

#include <stddef.h>

void matmul_int8(int32_t *C, const int8_t *A, const int8_t *B, int dimD, int dimN)
{
    for (int i = 0; i < dimD; ++i) {
        uint32_t sum = 0;
        for (int j = 0; j < dimN; ++j) {
            int32_t product = (int32_t)A[(size_t)i * dimN + j] * B[j];
            sum += (uint32_t)product;
        }

        /* Match the low 32 bits of the RV32 accumulator. */
        C[i] = sum <= INT32_MAX
            ? (int32_t)sum : (int32_t)((int64_t)sum - INT64_C(0x100000000));
    }
}
