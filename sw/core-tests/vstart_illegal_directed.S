// vstart != 0 on the instructions RVV 1.0 requires to raise an
// illegal-instruction exception then (issue #8 viota.m review):
// every reduction (sec. 14: vred*, vwredsum(u), vfred*, vfwred*),
// vcpop.m and vfirst.m (15.2-15.3), vmsbf.m, vmsif.m, vmsof.m
// (15.4-15.6), viota.m (15.8) and vcompress.vm (16.5).
//  1-26: vstart = 1 (16, 100 for 24-26) with vl = 16; the
//        instruction must take exactly one illegal-instruction
//        trap, leave its destination (v8 / a0) unchanged and
//        leave vstart as it was.
// 27-30: the same instructions with vstart = 0 do not trap and
//        leave vstart 0.
// 31-34: a vector load/store that starts at vstart != 0 resets
//        vstart when it completes; one of these instructions
//        right behind it must not trap (the core holds it in EX
//        until the load/store has left MEM, so its legality check
//        sees the reset vstart; without that hold the core traps
//        case 31 with a warm I-cache).
// Exit value: bit i set = case i failed (0 = pass). Passes on
// Spike (-DSPIKE_HTIF). Before the vstart check (RTL up to
// 4958c3f) Sigil executed cases 1-26 from vstart.
    .option arch, +v
    .option norvc  // norvc last: gas 13 .option arch resets it

#ifdef SPIKE_HTIF
#define EXIT slli t1, s1, 1; ori t1, t1, 1; la t2, tohost; sd t1, 0(t2); 1: j 1b
#else
#define EXIT li t1, 0x10000000; sd s1, 0(t1); 1: j 1b
#endif

// Record case \n as failed when the branch to 2f is taken.
.macro RESULT n
    j 3f
2:  li t4, 1
    slli t4, t4, \n
    or s1, s1, t4
3:
.endm

// Case \n: \insn with vstart = \vs must trap (cause 2) exactly
// once. The vector destination is v8 (element 0 preset to 0x77 at
// the case's vtype) or the scalar a0 (preset to 0x77); both must be
// unchanged, and vstart must still read \vs.
.macro CASE n, vs, insn:vararg
    la t3, tinfo
    sd x0, 0(t3)
    sd x0, 8(t3)
    li a0, 0x77
    vmv.v.x v8, a0
    li t3, \vs
    csrw vstart, t3
    \insn
    csrr t5, vstart
    csrw vstart, x0
    li t1, \vs
    bne t5, t1, 2f
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
    RESULT \n
.endm

// Case \n: \insn with vstart = 0 must not trap; vstart reads 0.
.macro OKCASE n, insn:vararg
    la t3, tinfo
    sd x0, 0(t3)
    csrw vstart, x0
    \insn
    csrr t5, vstart
    bnez t5, 2f
    la t3, tinfo
    ld t2, 0(t3)
    bnez t2, 2f
    RESULT \n
.endm

// Cases 31-34: HOLD_PRE \vs sets vstart = \vs and runs a scalar
// load (its MEM wait lets the fetch catch up, so the next two
// instructions enter EX back to back); a vector load/store from
// lsbuf (a2) and the instruction under test follow directly;
// HOLD_POST \n then checks that neither trapped and that vstart
// reads 0. Run three times (cold and warm I-cache).
.macro HOLD_PRE vs
    la t3, tinfo
    sd x0, 0(t3)
    la a2, lsbuf
    li t3, \vs
    csrw vstart, t3
    ld t2, 0(a2)
.endm
.macro HOLD_POST n
    csrr t5, vstart
    bnez t5, 2f
    la t3, tinfo
    ld t2, 0(t3)
    bnez t2, 2f
    RESULT \n
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
    vmv.v.i v0, 5

    CASE 1, 1, viota.m v8, v4
    vsetvli x0, a1, e8, m1, tu, mu
    CASE 2, 1, vcpop.m a0, v4
    vsetvli x0, a1, e8, m1, tu, mu
    CASE 3, 1, vfirst.m a0, v4
    vsetvli x0, a1, e8, m1, tu, mu
    CASE 4, 1, vmsbf.m v8, v4
    vsetvli x0, a1, e8, m1, tu, mu
    CASE 5, 1, vmsif.m v8, v4
    vsetvli x0, a1, e8, m1, tu, mu
    CASE 6, 1, vmsof.m v8, v4
    vsetvli x0, a1, e8, m1, tu, mu
    CASE 7, 1, vcompress.vm v8, v16, v4
    vsetvli x0, a1, e8, m1, tu, mu
    CASE 8, 1, vredsum.vs v8, v16, v24
    vsetvli x0, a1, e8, m1, tu, mu
    CASE 9, 1, vredand.vs v8, v16, v24
    vsetvli x0, a1, e8, m1, tu, mu
    CASE 10, 1, vredor.vs v8, v16, v24
    vsetvli x0, a1, e8, m1, tu, mu
    CASE 11, 1, vredxor.vs v8, v16, v24
    vsetvli x0, a1, e8, m1, tu, mu
    CASE 12, 1, vredminu.vs v8, v16, v24
    vsetvli x0, a1, e8, m1, tu, mu
    CASE 13, 1, vredmin.vs v8, v16, v24
    vsetvli x0, a1, e8, m1, tu, mu
    CASE 14, 1, vredmaxu.vs v8, v16, v24
    vsetvli x0, a1, e8, m1, tu, mu
    CASE 15, 1, vredmax.vs v8, v16, v24
    vsetvli x0, a1, e8, m1, tu, mu
    CASE 16, 1, vwredsumu.vs v8, v16, v24
    vsetvli x0, a1, e8, m1, tu, mu
    CASE 17, 1, vwredsum.vs v8, v16, v24
    vsetvli x0, a1, e32, m1, tu, mu
    CASE 18, 1, vfredosum.vs v8, v16, v24
    vsetvli x0, a1, e32, m1, tu, mu
    CASE 19, 1, vfredusum.vs v8, v16, v24
    vsetvli x0, a1, e32, m1, tu, mu
    CASE 20, 1, vfredmin.vs v8, v16, v24
    vsetvli x0, a1, e32, m1, tu, mu
    CASE 21, 1, vfredmax.vs v8, v16, v24
    vsetvli x0, a1, e32, m1, tu, mu
    CASE 22, 1, vfwredosum.vs v8, v16, v24
    vsetvli x0, a1, e32, m1, tu, mu
    CASE 23, 1, vfwredusum.vs v8, v16, v24
    // masked forms, vstart = vl and vstart > vl
    vsetvli x0, a1, e8, m1, tu, mu
    CASE 24, 1, viota.m v8, v4, v0.t
    vsetvli x0, a1, e8, m1, tu, mu
    CASE 25, 16, vcpop.m a0, v4, v0.t
    vsetvli x0, a1, e8, m1, tu, mu
    CASE 26, 100, vredsum.vs v8, v16, v24, v0.t

    // vstart = 0: executed
    vsetvli x0, a1, e8, m1, tu, mu
    OKCASE 27, viota.m v8, v4
    OKCASE 28, vredsum.vs v8, v16, v24
    OKCASE 29, vcompress.vm v8, v16, v4
    vsetvli x0, a1, e32, m1, tu, mu
    OKCASE 30, vfredosum.vs v8, v16, v24

    // vstart != 0 consumed by the load/store right before
    li s2, 3
hold_loop:
    vsetvli x0, a1, e8, m1, tu, mu
    HOLD_PRE 3
    vle8.v v12, (a2)
    vredsum.vs v8, v16, v24
    HOLD_POST 31
    HOLD_PRE 5
    vse8.v v16, (a2)
    vcpop.m a0, v4
    HOLD_POST 32
    li t1, 16                       // vcpop of 16 set bits
    beq a0, t1, 4f
    li t4, 1 << 32
    or s1, s1, t4
4:
    HOLD_PRE 2
    vl1re64.v v12, (a2)
    viota.m v8, v4
    HOLD_POST 33
    vsetvli x0, a1, e32, m1, tu, mu
    HOLD_PRE 1
    vle32.v v12, (a2)
    vfwredusum.vs v8, v16, v24
    HOLD_POST 34
    addi s2, s2, -1
    bnez s2, hold_loop

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
    .align 6
lsbuf: .zero 64
