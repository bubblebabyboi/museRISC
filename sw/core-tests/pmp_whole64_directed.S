// PMP partial match of an 8-byte element of a whole-register load with
// EEW=64 (issue #8, review of 3ae351d). vl<n>re64.v has evl =
// NFIELDS*VLEN/64 elements of 8 bytes (vstart counts them), and Spike
// and Sail perform each as one 8-byte access, so an NA4 entry or a TOR
// boundary splitting an element fails it, in M too, with tval = the
// element's address. The core transfers whole registers byte by byte
// and checks each byte alone: no fault in M (tests 1, 4), tval at the
// first failing byte in S/U (test 2). vl1re8.v (test 3, 1-byte
// elements) is the control both agree on. FAILS on the RTL as of
// f239397 (at test 1); not in the directed run list. Passes on Spike
// when assembled with -DSPIKE_HTIF (tohost exit, link at 0x80000000).
// Convention: t0 = test number, exit store 0 = pass.
    .option arch, +v
    .option norvc  // norvc last: gas 13 .option arch resets it

#ifdef SPIKE_HTIF
#define EXIT_PASS li t1, 1; la t2, tohost; sd t1, 0(t2); 1: j 1b
#define EXIT_FAIL slli t1, t0, 1; ori t1, t1, 1; la t2, tohost; sd t1, 0(t2); 1: j 1b
#else
#define EXIT_PASS li t1, 0x10000000; sd x0, 0(t1); 1: j 1b
#define EXIT_FAIL li t1, 0x10000000; sd t0, 0(t1); 1: j 1b
#endif

#define MPRV (1 << 17)
#define NA4  (2 << 3)
#define TOR  (1 << 3)

// Exactly one trap since tr was cleared, cause \c, mtval = \tv,
// vstart = \vs.
.macro EXP c, tv, vs
    la a4, tr
    ld a5, 0(a4)
    li a6, 1
    bne a5, a6, fail
    ld a5, 8(a4)
    li a6, \c
    bne a5, a6, fail
    ld a5, 16(a4)
    bne a5, \tv, fail
    ld a5, 24(a4)
    li a6, \vs
    bne a5, a6, fail
.endm
.macro CLR
    la a4, tr
    sd zero, 0(a4)
.endm

    .text
    .globl _start
_start:
    la t1, handler
    csrw mtvec, t1
    li t1, (1 << 9)                // VS = Initial
    csrs mstatus, t1
    la s1, buf
    csrw pmpcfg0, zero             // (Spike resets entry 0 to NAPOT RWX)
    csrw pmpcfg2, zero

    // ---- 1: M, entry 0 NA4 RWX over word 1 of element 1 (buf+12):
    //      vl1re64.v buf faults on element 1 (tval buf+8, vstart 1) ----
    li t0, 1
    addi t1, s1, 12
    srli t1, t1, 2
    csrw pmpaddr0, t1
    li t1, NA4 | 7
    csrw pmpcfg0, t1
    CLR
    vl1re64.v v1, (s1)
    addi t2, s1, 8
    EXP 5, t2, 1

    // ---- 2: as U (MPRV, MPP = U), entry 0 TOR [0, buf+20) RWX and
    //      nothing above: vl1re64.v buf faults on element 2, which the
    //      TOR top splits (tval buf+16, vstart 2) ----
    li t0, 2
    addi t1, s1, 20
    srli t1, t1, 2
    csrw pmpaddr0, t1
    li t1, TOR | 7
    csrw pmpcfg0, t1
    li s2, MPRV
    CLR
    csrs mstatus, s2
    vl1re64.v v1, (s1)
    csrc mstatus, s2
    addi t2, s1, 16
    EXP 5, t2, 2

    // ---- 3: control, same configuration: vl1re8.v faults on byte 20
    //      (tval buf+20, vstart 20) ----
    li t0, 3
    CLR
    csrs mstatus, s2
    vl1re8.v v1, (s1)
    csrc mstatus, s2
    addi t2, s1, 20
    EXP 5, t2, 20

    // ---- 4: M, entry 0 NA4 RWX over word 0 of element 9 (second
    //      register, buf+72): vl2re64.v buf faults on element 9 ----
    li t0, 4
    csrw pmpcfg0, zero
    addi t1, s1, 72
    srli t1, t1, 2
    csrw pmpaddr0, t1
    li t1, NA4 | 7
    csrw pmpcfg0, t1
    CLR
    vl2re64.v v2, (s1)
    addi t2, s1, 72
    EXP 5, t2, 9
    csrw pmpcfg0, zero

pass:
    EXIT_PASS
fail:
    EXIT_FAIL

// Records count, mcause, mtval, vstart; skips the instruction.
    .align 4
handler:
    csrw mscratch, a4
    la a4, tr
    sd a5, 32(a4)
    ld a5, 0(a4)
    addi a5, a5, 1
    sd a5, 0(a4)
    csrr a5, mcause
    sd a5, 8(a4)
    csrr a5, mtval
    sd a5, 16(a4)
    csrr a5, vstart
    sd a5, 24(a4)
    csrw vstart, zero
    csrr a5, mepc
    addi a5, a5, 4
    csrw mepc, a5
    ld a5, 32(a4)
    csrr a4, mscratch
    mret

    .data
    .align 3
tr: .dword 0, 0, 0, 0, 0
    .align 7
buf: .skip 256
#ifdef SPIKE_HTIF
    .align 6
    .globl tohost
tohost: .dword 0
    .align 6
    .globl fromhost
fromhost: .dword 0
#endif
