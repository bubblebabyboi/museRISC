// Fetch-walk preemption next to traps and already-dropped requests
// (issue #73 skeptic review of the preemption fix).
//
// Step 1: page A ends with
//     ld t4, 0(VA_Y)     uncached load, TLB hit: holds MEM a while
//     ld t5, 1(VA_D)     misaligned: excepts in EX (cause 4)
//     ld a0, 0(VA_D)     data-TLB miss
// and IF runs on into cold page B (fetch walk F1, root read R1 in
// flight). IF delivers one word every other cycle, so instructions
// normally travel with a bubble between them; the first load's
// mem_stall lets the fetch of the third catch up, so the misaligned
// load reaches WB (trap_take) in the same cycle the data-missing
// load sits in MEM, i.e. the cycle in which sigil_mmu would preempt
// F1. The trap must win (abort), R1 is dropped and the load is
// squashed.
// Step 2: the M handler waits d loop iterations and returns to the
// last word of page A2 (pre-loaded), ld a0, 0(VA_D); IF runs into
// cold page B2 and starts fetch walk F2. While R1 (dropped) is still
// in flight F2 cannot issue, and the load's data miss preempts F2
// with dq_drop_q already set; later d values move the preemption
// onto R1's response cycle, onto F2's own root-read issue and onto
// F2's read in flight. The load must return MAGIC and page B2's
// ecall end the pass. d sweeps 0..NDLY-1, ITERS times.
// Tables in uncached RAM. Exit code 0 = pass; otherwise
// 0x100 | mcause (0x1FF = wrong data) | (step << 11) | (d << 12)
// | (iter << 20).
    .option norvc
    .text
    .globl _start

.equ PT_ROOT, 0x20020000     // uncached RAM in core_tb's map
.equ PT_L1A,  0x20021000
.equ PT_L0A,  0x20022000
.equ PT_L1D,  0x20023000
.equ PT_L0D,  0x20024000
.equ VA_A,    0x200000       // L0A[0]; page B = L0A[1]
.equ VA_A2,   0x202000       // L0A[2]; page B2 = L0A[3]
.equ VA_D,    0x40000000     // root[1]
.equ VA_Y,    0x204000       // L0A[4] -> PT_Y (uncached scratch)
.equ PT_Y,    0x20025000
.equ MAGIC,   0x5a5a1234
.equ ITERS,   3
.equ NDLY,    64

_start:
    li t0, 1
    la t1, m_handler
    csrw mtvec, t1
    li t1, -1
    csrw pmpaddr15, t1
    li t1, 0x1f
    slli t1, t1, 56
    csrw pmpcfg2, t1
    li t1, PT_ROOT
    li t2, PT_ROOT + 0x6000
1:  sd x0, 0(t1)
    addi t1, t1, 8
    bltu t1, t2, 1b
    li t1, PT_L1A
    srli t1, t1, 2
    ori t1, t1, 0x01
    li t2, PT_ROOT
    sd t1, 0(t2)                  // root[0] -> L1A
    li t1, PT_L0A
    srli t1, t1, 2
    ori t1, t1, 0x01
    li t2, PT_L1A + 8
    sd t1, 0(t2)                  // L1A[1] -> L0A (VA 2M..4M)
    la t1, code_pages
    srli t1, t1, 2
    ori t1, t1, 0xCB              // RX A D
    li t2, PT_L0A
    li t3, 4
2:  sd t1, 0(t2)
    addi t1, t1, 0x400
    addi t2, t2, 8
    addi t3, t3, -1
    bnez t3, 2b
    li t1, PT_Y
    srli t1, t1, 2
    ori t1, t1, 0xC7              // RW A D
    sd t1, 0(t2)                  // L0A[4]: VA_Y -> PT_Y (uncached)
    li t1, PT_L1D
    srli t1, t1, 2
    ori t1, t1, 0x01
    li t2, PT_ROOT + 8
    sd t1, 0(t2)                  // root[1] -> L1D
    li t1, PT_L0D
    srli t1, t1, 2
    ori t1, t1, 0x01
    li t2, PT_L1D
    sd t1, 0(t2)                  // L1D[0] -> L0D
    la t1, page_d
    srli t1, t1, 2
    ori t1, t1, 0xC7              // RW A D
    li t2, PT_L0D
    sd t1, 0(t2)                  // L0D[0]: VA_D -> page_d
    li t1, 8
    slli t1, t1, 60
    li t2, PT_ROOT >> 12
    or t1, t1, t2
    csrw satp, t1
    li s2, 0                      // iteration
    li s4, 0                      // step (0: expect the page-A trap, 1: page-B2 ecall)
    li s6, 0                      // d
    li s5, VA_D
    li s7, VA_Y
    li s8, VA_A2 + 0x1000 - 4     // step-2 entry (page-A2 load)
    j enter

m_handler:
    // Step 1 trap (misaligned load on page A), fast path so that the
    // page-A2 load arrives while R1 is still in flight: record cause
    // and epc (checked at step 2), wait d iterations, return to the
    // last word of page A2 (MPP is already S; the TLB is not flushed,
    // A2 stays loaded).
    bnez s4, 6f
    csrr s11, mcause
    csrr s3, mepc
    csrw mepc, s8
    li s4, 1
    mv t3, s6
    beqz t3, 8f
7:  addi t3, t3, -1
    bnez t3, 7b
8:  mret
    // Step 2 trap (ecall on page B2): check step 1 and the load.
6:  li t1, 4
    bne s11, t1, 9f
    li t2, VA_A + 0x1000 - 8
    bne s3, t2, m_badpc
    csrr t1, mcause
    li t2, 9
    bne t1, t2, m_fail
    li t2, MAGIC
    bne a0, t2, m_bad
    li s4, 0
    addi s6, s6, 1
    li t2, NDLY
    bltu s6, t2, enter
    li s6, 0
    addi s2, s2, 1
    li t2, ITERS
    bltu s2, t2, enter
    li t1, 0x10000000
    sd x0, 0(t1)
1:  j 1b
m_badpc:
    li t1, 0xFE
    j m_fail
9:  mv t1, s11                    // step-1 trap had the wrong cause
    li s4, 0
    j m_fail
m_bad:
    li t1, 0xFF
m_fail:
    ori t0, t1, 0x100
    slli t2, s4, 11
    or t0, t0, t2
    slli t2, s6, 12
    or t0, t0, t2
    slli t2, s2, 20
    or t0, t0, t2
    li t1, 0x10000000
    sd t0, 0(t1)
1:  j 1b

enter:
    sfence.vma
    li a0, 0
    li t1, VA_A + 0x1000 - 12
    csrw mepc, t1
    li t2, (3 << 11)
    csrc mstatus, t2
    li t2, (1 << 11)              // MPP = S
    csrs mstatus, t2
    // Pre-load pages A and A2 (MPRV loads); B, B2 and VA_D stay cold.
    li t2, (1 << 17)
    csrs mstatus, t2
    lw t3, 0(t1)
    li t1, VA_A2
    lw t3, 0(t1)
    ld t3, 0(s7)                  // VA_Y
    csrc mstatus, t2
    mret

    .balign 4096
code_pages:
    .skip 0x1000 - 12             // page A
    ld t4, 0(s7)
    ld t5, 1(s5)                  // misaligned: cause 4 at WB
    ld a0, 0(s5)
    ecall                         // page B (never executed)
    .skip 0x1000 - 4
    .skip 0x1000 - 4              // page A2
    ld a0, 0(s5)
    ecall                         // page B2
    .skip 0x1000 - 4

    .balign 4096
page_d:
    .dword MAGIC
    .skip 4096 - 8
