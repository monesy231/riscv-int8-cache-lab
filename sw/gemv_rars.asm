.data
    .align 2
    result: .space 16
    matrix: .byte 1, -2, 3, -4, 5, -6, 7, -8
            .byte -8, 7, -6, 5, -4, 3, -2, 1
            .byte -128, 127, -128, 127, 127, -128, 127, -128
            .byte 0, 0, 0, 0, 5, -2, 6, 1
    vector: .byte 2, -1, 3, 4, -2, 5, -3, 1

.text
.globl main
main:
    la    a0, result
    la    a1, matrix
    la    a2, vector
    addi  a3, zero, 4
    addi  a4, zero, 8
    jal   ra, matmul_int8

    la    t0, result
    addi  t1, t0, 16
print_word:
    lw    a0, 0(t0)
    addi  a7, zero, 1
    ecall
    addi  t0, t0, 4
    beq   t0, t1, print_newline
    addi  a0, zero, 32
    addi  a7, zero, 11
    ecall
    jal   zero, print_word
print_newline:
    addi  a0, zero, 10
    addi  a7, zero, 11
    ecall
    addi  a7, zero, 10
    ecall

# a0 = C, a1 = A, a2 = B, a3 = rows, a4 = columns.
matmul_int8:
    addi  sp, sp, -16
    sw    ra, 12(sp)
    addi  t0, zero, 0
row_loop:
    bge   t0, a3, done
    addi  t1, zero, 0
    addi  t2, zero, 0
column_loop:
    bge   t1, a4, store_result
    mul   t3, t0, a4
    add   t3, t3, t1
    add   t4, a1, t3
    lb    t5, 0(t4)
    add   t4, a2, t1
    lb    t6, 0(t4)
    mul   t5, t5, t6
    add   t2, t2, t5
    addi  t1, t1, 1
    jal   zero, column_loop
store_result:
    slli  t3, t0, 2
    add   t4, a0, t3
    sw    t2, 0(t4)
    addi  t0, t0, 1
    jal   zero, row_loop
done:
    lw    ra, 12(sp)
    addi  sp, sp, 16
    jalr  zero, 0(ra)
