// Late kills of the multi-cycle M unit (muldiv-multicycle).
// Tests 1-4: an older vector load parked in MEM (mem_stall, 2 cycles
// per element) faults on element 8, about 16 cycles after it reaches
// MEM, while the M op behind it runs in EX. A long divide (1, 4) is
// killed mid-computation (ITER). A multiply / divide by zero (2, 3)
// finishes first and holds its result through the stall; it is acked
// in the cycle the stall ends with the fault and then flushed from
// EX/MEM by the trap. Test 5: a divide by zero right behind a
// misaligned scalar load is killed in its done state (the trap fires
// in the done cycle, when ack is never given). The handler skips the
// faulting load (and clears vstart); every M op re-executes from
// scratch and must produce the right result.
// The faulting element is the first whose physical address has a
// bit above PA bit 55 set (load access fault, cause 5).
// Convention: t0 = test number, exit store 0 = pass.
// s8 = access-fault count (handler touches only t4/t5/s8).
    .option arch, +v
    .option norvc
    .text
    .globl _start
_start:
    la t1, handler
    csrw mtvec, t1
    li t1, (1 << 9)               // VS=Initial
    csrs mstatus, t1
    li s8, 0
    li t1, 16
    vsetvli t1, t1, e64, m2, ta, ma   // VLEN 512: 16 elements
    li a0, 0x00ffffffffffffc0     // elements 0..7 below 2^56, 8 faults
    li a1, -1
    li a2, 3

    // ---- 1: long divide killed mid-computation (35 EX cycles).
    li t0, 1
    vle64.v v2, (a0)
    divu a3, a1, a2
    li t2, 0x5555555555555555
    bne a3, t2, fail
    li t2, 1
    bne s8, t2, fail

    // ---- 2: multiply killed while its result is held (done after 2
    //      cycles, no ack while the load stalls MEM).
    li t0, 2
    vle64.v v2, (a0)
    mul a4, a1, a2
    li t2, -3
    bne a4, t2, fail

    // ---- 3: divide by zero (done after 1 cycle) killed while held.
    li t0, 3
    vle64.v v2, (a0)
    div a5, a2, zero
    li t2, -1
    bne a5, t2, fail

    // ---- 4: killed divide with a dependent multiply behind it.
    li t0, 4
    vle64.v v2, (a0)
    remu a6, a1, a2               // 0
    addi a6, a6, 7
    mulhu a7, a1, a6              // 6
    li t2, 6
    bne a7, t2, fail
    csrr t2, vstart
    bnez t2, fail

    // ---- 5: divide by zero (done in its first unit cycle) right
    //      behind a misaligned load: the load's trap fires in the
    //      cycle the result is done, so the unit is killed in its
    //      done state (ack is never given under trap_take).
    li t0, 5
    la t6, misaligned
    ld t3, 1(t6)
    div a5, a1, zero
    li t2, -1
    bne a5, t2, fail
    ld t3, 1(t6)
    rem a5, a2, zero              // 3
    li t2, 3
    bne a5, t2, fail

    // ---- 6: every M op is re-executed exactly once per fault.
    li t0, 6
    li t2, 6
    bne s8, t2, fail

pass:
    li t1, 0x10000000
    sd x0, 0(t1)
1:  j 1b
fail:
    li t1, 0x10000000
    sd t0, 0(t1)
1:  j 1b

    .balign 4
handler:
    csrr t4, mcause
    li t5, 4                      // load address misaligned (test 5)
    beq t4, t5, 1f
    li t5, 5                      // load access fault (vector, 1-4)
    bne t4, t5, fail
1:  csrw vstart, zero
    csrr t5, mepc
    addi t5, t5, 4
    csrw mepc, t5
    addi s8, s8, 1
    mret

    .data
    .balign 8
misaligned: .dword 0x1122334455667788, 0
