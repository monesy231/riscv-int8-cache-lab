#include "gemv.h"

#include <inttypes.h>
#include <stdio.h>

enum { ROWS = 4, COLS = 8 };

_Alignas(4) static const int8_t matrix[ROWS * COLS] = {
       1,  -2,    3,  -4,   5,   -6,   7,   -8,
      -8,   7,   -6,   5,  -4,    3,  -2,    1,
    -128, 127, -128, 127, 127, -128, 127, -128,
       0,   0,    0,   0,   5,   -2,   6,    1,
};
_Alignas(4) static const int8_t vector[COLS] = {2, -1, 3, 4, -2, 5, -3, 1};

int main(void)
{
    int32_t result[ROWS];
    const int32_t expected[ROWS] = {-72, 9, -1662, -37};
    matmul_int8(result, matrix, vector, ROWS, COLS);

    for (int i = 0; i < ROWS; ++i) {
        if (result[i] != expected[i]) {
            fprintf(stderr, "row %d: expected %" PRId32 ", got %" PRId32 "\n",
                    i, expected[i], result[i]);
            return 1;
        }
        printf("%" PRId32 "%c", result[i], i == ROWS - 1 ? '\n' : ' ');
    }

    return 0;
}
