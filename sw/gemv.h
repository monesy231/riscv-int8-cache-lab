#ifndef GEMV_H
#define GEMV_H

#include <stdint.h>

/* A is a row-major dimD × dimN matrix. C holds dimD signed 32-bit results. */
void matmul_int8(int32_t *C, const int8_t *A, const int8_t *B, int dimD, int dimN);

#endif
