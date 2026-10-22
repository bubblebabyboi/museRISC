// Fetch-walk preemption next to traps and already-dropped requests
// (issue #73 skeptic review of the preemption fix).
//
// Step 1: page A ends with  ecall ; ld a0, 0(VA_D)  and IF runs on
// into cold page B (fetch walk F1, root read R1 in flight). The
// ecall reaches WB (trap_take) in the same cycle the load sits in
// MEM with a data-TLB miss, i.e. the cycle in which sigil_mmu would
// preempt F1: the trap must win (abort), R1 is dropped and the load
// is squashed.
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
    li t2, PT_ROOT + 0x5000
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
    li s4, 0                      // step (0: expect page-A ecall, 1: page-B2 ecall)
    li s6, 0                      // d
    li s5, VA_D
    j enter

m_handler:
    csrr t1, mcause
    li t2, 9
    bne t1, t2, m_fail
    bnez s4, 6f
    // Step 1 trap (ecall on page A): wait d iterations, then run
    // the page-A2 load. The TLB is not flushed (A2 stays loaded).
    csrr t1, mepc
    li t2, VA_A + 0x1000 - 8
    bne t1, t2, m_badpc
    li s4, 1
    li t1, VA_A2 + 0x1000 - 4
    csrw mepc, t1
    li t2, (3 << 11)
    csrc mstatus, t2
    li t2, (1 << 11)
    csrs mstatus, t2
    mv t3, s6
    beqz t3, 8f
7:  addi t3, t3, -1
    bnez t3, 7b
8:  mret
    // Step 2 trap (ecall on page B2): check the load.
6:  li t2, MAGIC
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
    li t1, VA_A + 0x1000 - 8
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
    csrc mstatus, t2
    mret

    .balign 4096
code_pages:
    .skip 0x1000 - 8              // page A
    ecall
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
