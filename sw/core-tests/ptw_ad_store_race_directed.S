// Hardware A/D write-back is not atomic against an older store to
// the same PTE (issue #73 oops review, other-preemption-paths lens:
// the walker's A/D update state loses the port to MEM).
//
// sigil_mmu reads a leaf PTE in W_VS_READ and, if A (or D) must be
// set, writes pte_q | A back in W_VS_UPD. Between the two the port
// is arbitrated cycle by cycle and MEM has priority (walk_issue
// needs !mem_needs_port). A fetch walk is younger than every
// instruction in MEM, so an older store to the same PTE that
// reaches MEM while the walker's leaf read is in flight is
// performed first, and the write-back then overwrites it with the
// stale value read before the store.
//
// S-mode code at VA_A = 0x3FFF_F000 warms the D-TLB for the table
// window, then ends the page with `sd t5, 0(t4)` to the PTE of
// VA_B = 0x4000_0000, the next page: VS root[1], a 1 GiB leaf (RX)
// with A = 0, to PA 0x8000_0000 (which holds an ECALL). IF falls
// through into VA_B while the store is in ID, so the fetch walk's
// one read (root[1]) is on the port when the store reaches MEM.
//   phase 0: the store sets RSW bit 9 (old | 0x200). Memory must
//            keep bit 9; the race leaves old | A instead.
//   phase 1: the store clears the PTE (unmap). Memory must read 0
//            afterwards (the fetch may still use the old
//            translation, or take a page fault); the race leaves a
//            valid PTE (old | A) in memory.
// Exit code 0 = pass; otherwise 0x100 | mcause, or 0x1F0 + n for
// a wrong PTE value (n = phase), plus (iter << 16), (phase << 24).
    .option norvc
    .text
    .globl _start

.equ PT_ROOT, 0x20020000     // uncached RAM in core_tb's map
.equ PT_L1A,  0x20021000     // root[0]
.equ PT_L0A,  0x20022000     // L1A[511]
.equ VA_A,    0x3FFFF000     // code page A
.equ VA_B,    0x40000000     // root[1] 1 GiB leaf, A = 0
.equ PA_B,    0x80000000
.equ VA_TAB,  0x20000000     // L1A[256]: 2 MiB RW leaf over the tables
.equ PTE_B,   (PA_B >> 2) | 0x0B   // V R X, A = D = 0
.equ ITERS,   32
.equ NPHASE,  2

_start:
    li t0, 1
    la t1, m_handler
    csrw mtvec, t1
    li t1, -1
    csrw pmpaddr15, t1
    li t1, 0x1f
    slli t1, t1, 56
    csrw pmpcfg2, t1
    // Flags: V1 R2 W4 X8 A64 D128. Pointer = V only.
    li t2, PT_ROOT
    li t1, (PT_L1A >> 2) | 0x01
    sd t1, 0(t2)                  // root[0] -> L1A
    li t2, PT_L1A + 511*8
    li t1, (PT_L0A >> 2) | 0x01
    sd t1, 0(t2)                  // L1A[511] -> L0A
    li t2, PT_L1A + 256*8
    li t1, (VA_TAB >> 2) | 0xC7   // 2 MiB RW A D, identity
    sd t1, 0(t2)
    la t1, page_a
    srli t1, t1, 2
    ori t1, t1, 0xCB              // RX A D
    li t2, PT_L0A + 511*8
    sd t1, 0(t2)                  // L0A[511]: VA_A -> page_a
    li t2, PA_B
    li t1, 0x00000073             // ecall at VA_B
    sw t1, 0(t2)
    fence.i
    li t1, 8
    slli t1, t1, 60
    li t2, PT_ROOT >> 12
    or t1, t1, t2
    csrw satp, t1
    li s2, 0                      // iteration
    li s3, 0                      // phase
    li t4, PT_ROOT + 8            // VA (= PA) of root[1]
    j enter

// ECALL from S at VA_B (cause 9), or (phase 1 only) an instruction
// page fault on VA_B (cause 12), ends one pass.
m_handler:
    csrr t1, mcause
    li t2, 9
    beq t1, t2, 1f
    li t2, 12
    bne t1, t2, m_fail
    beqz s3, m_fail
1:  li t2, PT_ROOT + 8
    ld t1, 0(t2)
    bnez s3, 2f
    andi t1, t1, 0x200            // phase 0: RSW bit 9 must survive
    beqz t1, m_badpte
    j 3f
2:  bnez t1, m_badpte             // phase 1: PTE must stay cleared
3:  addi s2, s2, 1
    li t2, ITERS
    bltu s2, t2, enter
    li s2, 0
    addi s3, s3, 1
    li t2, NPHASE
    bltu s3, t2, enter
    li t1, 0x10000000
    sd x0, 0(t1)
1:  j 1b
m_badpte:
    addi t1, s3, 0xF0
m_fail:
    ori t0, t1, 0x100
    slli t2, s2, 16
    or t0, t0, t2
    slli t2, s3, 24
    or t0, t0, t2
    li t1, 0x10000000
    sd t0, 0(t1)
1:  j 1b

enter:
    li t2, PT_ROOT + 8
    li t1, PTE_B
    sd t1, 0(t2)                  // root[1]: A = 0 again
    mv t5, t1
    ori t5, t5, 0x200             // phase 0 store value: old | RSW bit 9
    beqz s3, 1f
    li t5, 0                      // phase 1 store value: unmap
1:  sfence.vma
    li t1, VA_A + 0xFC0
    csrw mepc, t1
    li t1, (3 << 11)
    csrc mstatus, t1
    li t1, (1 << 11)              // MPP = S
    csrs mstatus, t1
    mret

    .balign 4096
page_a:
    .skip 0xFC0
    ld t6, 0(t4)                  // D-TLB fill for the table window
    .rept 14
    nop
    .endr
    sd t5, 0(t4)                  // older store to VA_B's PTE (last word)
    .balign 4096
