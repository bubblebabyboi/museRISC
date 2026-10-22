// Hardware A/D update (Svadu) atomicity against an older store to
// the same PTE (issue #73 oops review, svadu-atomicity lens).
//
// The walker's A/D update is a read (W_VS_READ, leaf latched into
// pte_q) followed by a separate write of pte_q | A (W_VS_UPD). MEM
// has priority on the shared data port, so for a FETCH walk an
// older MEM store that reaches the port between the two lands in
// memory and is then overwritten by the stale pte_q | A. The
// update must be atomic: the final PTE must reflect the store
// (either store-then-update or update-then-store order).
//
// S-mode code ends page A with a DIV (operand-tuned latency of
// 1..34 cycles) and then a store to page B's leaf PTE (A=0, D=0).
// While the DIV holds EX, IF runs into page B, misses the TLB and
// starts a fetch walk; the store reaches MEM after the delay. The
// store sets RSW bit 8 (a marker the walker ignores). Page B reads
// the PTE back through the same mapping and ECALLs; the M handler
// requires the marker bit. Ops: 0 SD of base|marker, 1 AMOOR.D of
// the marker, 2 LR.D/SC.D of base|marker (an SC failure is legal
// and skips the check). Phase 0 evicts the leaf PTE's D$ line
// (its walk read takes the bus latency); phase 1 leaves it cached.
// Page tables are in cacheable RAM; page A's translation and the
// store's (VA_T, the L0A table page mapped RW) are pre-loaded by
// MPRV loads, so only page B walks after MRET.
//
// Exit 0 = pass; otherwise 0x100 | mcause (0x1FF = marker lost),
// plus (delay index << 12), (op << 18), (phase << 20), (iter << 21).
    .option norvc
    .text
    .globl _start

.equ PT_ROOT, 0x100000
.equ PT_L1A,  0x101000
.equ PT_L0A,  0x102000
.equ EVICT0,  0x110000       // conflict lines: same D$ set, 4 KiB stride
.equ VA_BASE, 0x200000       // L1A[1] -> L0A
.equ IDX_T,   60             // L0A[60]: VA_T -> PT_L0A (RW A D)
.equ VA_T,    VA_BASE + IDX_T * 0x1000
.equ NDLY,    34
.equ NOPS,    3
.equ ITERS,   4
.equ MARK,    0x100          // PTE RSW bit 8

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
    li t2, PT_ROOT + 0x3000
1:  sd x0, 0(t1)
    addi t1, t1, 8
    bltu t1, t2, 1b
    // Flags: V1 R2 W4 X8 A64 D128. Pointer = V only.
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
    // Page A of op p: L0A[8+16p-1] -> code page 2p (RX A D).
    // Page B of op p: L0A[8+16p]   -> code page 2p+1, set per pass.
    li t3, 0
2:  slli t1, t3, 13
    la t2, code_pages
    add t1, t1, t2
    srli t1, t1, 2
    ori t1, t1, 0xCB
    slli t2, t3, 7                // 16 PTEs per op
    li t4, PT_L0A + 7*8
    add t2, t2, t4
    sd t1, 0(t2)
    addi t3, t3, 1
    li t4, 3
    bltu t3, t4, 2b
    li t1, PT_L0A
    srli t1, t1, 2
    ori t1, t1, 0xC7              // RW A D
    li t2, PT_L0A + IDX_T*8
    sd t1, 0(t2)                  // VA_T -> L0A table page
    fence.i
    li t1, 8
    slli t1, t1, 60
    li t2, PT_ROOT >> 12
    or t1, t1, t2
    csrw satp, t1
    li s2, 0                      // iteration
    li s3, 0                      // delay index
    li s4, 0                      // op
    li s7, 0                      // phase
    j enter

// ECALL from S (page B): a0 = PTE read back, t3 = SC result.
m_handler:
    csrr t1, mcause
    li t2, 9
    bne t1, t2, m_fail
    bnez t3, 3f                   // SC failed: no store, no check
    andi t2, a0, MARK
    beqz t2, m_bad
3:  addi s3, s3, 1
    li t2, NDLY
    bltu s3, t2, enter
    li s3, 0
    addi s4, s4, 1
    li t2, NOPS
    bltu s4, t2, enter
    li s4, 0
    addi s7, s7, 1
    li t2, 2
    bltu s7, t2, enter
    li s7, 0
    addi s2, s2, 1
    li t2, ITERS
    bltu s2, t2, enter
    li t1, 0x10000000
    sd x0, 0(t1)
1:  j 1b
m_bad:
    li t1, 0xFF                   // store to the PTE lost
m_fail:
    ori t0, t1, 0x100
    slli t2, s3, 12
    or t0, t0, t2
    slli t2, s4, 18
    or t0, t0, t2
    slli t2, s7, 20
    or t0, t0, t2
    slli t2, s2, 21
    or t0, t0, t2
    li t1, 0x10000000
    sd t0, 0(t1)
1:  j 1b

enter:
    // Page B's leaf PTE (A=0, D=0): t5 = value, t4 = its PA.
    slli t1, s4, 13
    li t2, 0x1000
    add t1, t1, t2
    la t2, code_pages
    add t1, t1, t2
    srli t1, t1, 2
    ori t5, t1, 0x0B              // V R X
    slli t4, s4, 7
    li t1, PT_L0A + 8*8
    add t4, t4, t1
    sd t5, 0(t4)
    sfence.vma                    // cold TLB
    // s8 = VA of that PTE through VA_T; s9 = store operand.
    slli s8, s4, 7
    li t1, VA_T + 8*8
    add s8, s8, t1
    ori s9, t5, MARK
    li t1, 1
    bne s4, t1, 4f
    li s9, MARK                   // AMOOR operand
4:  // DIV operands: delay index j -> 1 + j cycles.
    li a1, 1
    li a2, 0                      // j = 0: divide by zero
    beqz s3, 5f
    li a2, 1
    li a1, 0                      // j = 1: |a| < |b|
    li t1, 1
    beq s3, t1, 5f
    addi t1, s3, -2
    slli t1, t1, 1
    li a1, 1
    sll a1, a1, t1                // j >= 2: a = 2^(2(j-2)), n = j-1
5:  li a0, 0
    li t3, 0
    // Entry: page A of op p, 8 bytes before its end (12 for LR/SC).
    slli t1, s4, 16               // 16 pages per op
    li t2, VA_BASE + 7*0x1000 + 0x1000 - 8
    add t1, t1, t2
    li t2, 2
    bne s4, t2, 6f
    addi t1, t1, -4
6:  csrw mepc, t1
    li t2, (3 << 11)
    csrc mstatus, t2
    li t2, (1 << 11)              // MPP = S
    csrs mstatus, t2
    // Pre-load page A and VA_T translations (MPRV, MPP = S). The
    // VA_T load reads a line away from page B's PTE line.
    li t2, (1 << 17)
    csrs mstatus, t2
    lw t6, 0(t1)
    li t1, VA_T + 0x800
    ld t6, 0(t1)
    csrc mstatus, t2
    bnez s7, 8f
    // Evict page B's PTE line: 8 conflict loads in its set.
    srli t1, t4, 6
    andi t1, t1, 63
    slli t1, t1, 6
    li t2, EVICT0
    add t1, t1, t2
    li t6, 8
7:  ld t2, 0(t1)
    li t2, 0x1000
    add t1, t1, t2
    addi t6, t6, -1
    bnez t6, 7b
8:  mret

    .balign 4096
code_pages:
// op 0: A0 / B0
    .skip 0x1000 - 8
    div t1, a1, a2
    sd s9, 0(s8)
    ld a0, 0(s8)
    ecall
    .skip 0x1000 - 8
// op 1: A1 / B1
    .skip 0x1000 - 8
    div t1, a1, a2
    amoor.d x0, s9, (s8)
    ld a0, 0(s8)
    ecall
    .skip 0x1000 - 8
// op 2: A2 / B2
    .skip 0x1000 - 12
    lr.d t6, (s8)
    div t1, a1, a2
    sc.d t3, s9, (s8)
    ld a0, 0(s8)
    ecall
    .skip 0x1000 - 8
