// vstart != 0 on the instructions RVV 1.0 requires to raise an
// illegal-instruction exception then (issue #8 viota.m review):
// viota.m (sec. 15.8), vcpop.m, vfirst.m, vmsbf.m, vmsif.m, vmsof.m
// (15.2-15.7), vcompress.vm (16.5) and the reductions (14: vredsum,
// vwredsum, vfredosum, vfredusum, vfwredusum). Each case sets
// vstart = 1 with vl = 16, runs the instruction and expects exactly
// one illegal-instruction trap with the destination unchanged.
// Exit value: bit i set = case i failed (0 = pass). Spike passes
// (-DSPIKE_HTIF); not in the directed suite: Sigil executes every one
// of them from vstart (exit 0x1ffe, all twelve cases).
    .option arch, +v
    .option norvc  // norvc last: gas 13 .option arch resets it

#ifdef SPIKE_HTIF
#define EXIT slli t1, s1, 1; ori t1, t1, 1; la t2, tohost; sd t1, 0(t2); 1: j 1b
#else
#define EXIT li t1, 0x10000000; sd s1, 0(t1); 1: j 1b
#endif

// Case \n: \insn with vstart = 1 must trap (cause 2) exactly once.
// The vector destination is v8 (element 0 preset to 0x77 at the
// case's vtype) or the scalar a0 (preset to 0x77); both must be
// unchanged.
.macro CASE n, insn:vararg
    la t3, tinfo
    sd x0, 0(t3)
    sd x0, 8(t3)
    li a0, 0x77
    vmv.v.x v8, a0
    li t3, 1
    csrw vstart, t3
    \insn
    csrw vstart, x0
    li t4, 0
    la t3, tinfo
    ld t2, 0(t3)
    li t1, 1
    bne t2, t1, 2f
    ld t2, 8(t3)
    li t1, 2
    bne t2, t1, 2f
    li t1, 0x77
    bne a0, t1, 2f
    vsetvli t2, x0, e8, m1, tu, mu
    vmv.x.s t2, v8
    andi t2, t2, 0xff
    bne t2, t1, 2f
    j 3f
2:  li t4, 1
3:  slli t4, t4, \n
    or s1, s1, t4
.endm

    .text
    .globl _start
_start:
    la t1, trap
    csrw mtvec, t1
    li t1, (3 << 13) | (3 << 9)    // mstatus.FS and .VS = Dirty
    csrs mstatus, t1
    li s1, 0
    li a1, 16
    vsetvli x0, a1, e8, m1, tu, mu
    vmv.v.i v4, -1
    vmv.v.i v16, 3
    vmv.v.i v24, 1

    CASE 1, viota.m v8, v4
    vsetvli x0, a1, e8, m1, tu, mu
    CASE 2, vcpop.m a0, v4
    vsetvli x0, a1, e8, m1, tu, mu
    CASE 3, vfirst.m a0, v4
    vsetvli x0, a1, e8, m1, tu, mu
    CASE 4, vmsbf.m v8, v4
    vsetvli x0, a1, e8, m1, tu, mu
    CASE 5, vmsif.m v8, v4
    vsetvli x0, a1, e8, m1, tu, mu
    CASE 6, vmsof.m v8, v4
    vsetvli x0, a1, e8, m1, tu, mu
    CASE 7, vcompress.vm v8, v16, v4
    vsetvli x0, a1, e8, m1, tu, mu
    CASE 8, vredsum.vs v8, v16, v24
    vsetvli x0, a1, e8, m1, tu, mu
    CASE 9, vwredsum.vs v8, v16, v24
    vsetvli x0, a1, e32, m1, tu, mu
    CASE 10, vfredosum.vs v8, v16, v24
    vsetvli x0, a1, e32, m1, tu, mu
    CASE 11, vfredusum.vs v8, v16, v24
    vsetvli x0, a1, e32, m1, tu, mu
    CASE 12, vfwredusum.vs v8, v16, v24

    EXIT

    // Count traps, record mcause, skip the 4-byte instruction.
    .align 2
trap:
    la t5, tinfo
    ld t6, 0(t5)
    addi t6, t6, 1
    sd t6, 0(t5)
    csrr t6, mcause
    sd t6, 8(t5)
    csrr t6, mepc
    addi t6, t6, 4
    csrw mepc, t6
    mret

    .data
#ifdef SPIKE_HTIF
    .align 6
    .globl tohost
tohost: .dword 0
    .align 6
    .globl fromhost
fromhost: .dword 0
#endif
    .align 3
tinfo: .dword 0, 0                  // trap count, last mcause
