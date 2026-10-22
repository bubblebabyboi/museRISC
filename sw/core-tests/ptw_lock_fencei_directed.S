// A FENCE.I waiting in MEM while a fetch walk updates A/D (#53 merge
// onto the #73 walker fixes).
//
// The walker's A/D lock (walk_lock) gives it the data port from the
// leaf PTE read to its write-back; MEM's own access waits. With
// FPGA_TIMING the data-port payload select (mem_port_sel) is MEM's
// whenever MEM holds a translated access or a FENCE.I, and the walker
// issues only when it is not MEM's. A translated access loses its
// registered translation for a cycle after every walker grant (the
// replay), which leaves the walker that cycle; a FENCE.I has no
// translation, so a select not masked by the lock blocks the
// write-back for good while the lock blocks the FENCE.I: a hang.
//
// S-mode code at VA_A = 0x3FFF_F000 ends the page with a load that
// misses the D-TLB and a FENCE.I. The load reaches MEM as FENCE.I
// enters ID and IF falls through into VA_B = 0x4000_0000, the next
// page: root[1], a 1 GiB leaf (RX) with A = 0 to PA 0x8000_0000 (an
// ECALL). The load's data walk and then its own (uncached) access
// hold FENCE.I in ID while the fetch walk waits for the port; the
// fetch walk's root[1] read issues as FENCE.I moves to EX, so
// FENCE.I reaches MEM with the read in flight and the A update
// (W_VS_UPD) follows. Tables and the load target are uncached RAM.
// Each pass ends at the ECALL (cause 9), and root[1] must then have
// A set.
// Exit code 0 = pass; otherwise 0x100 | mcause, or 0x1F0 for a PTE
// without A, plus (iter << 16). A hang ends at the cycle limit.
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
.equ LD_VA,   0x20023000     // the load's target (uncached)
.equ PTE_B,   (PA_B >> 2) | 0x0B   // V R X, A = D = 0
.equ ITERS,   32

_start:
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
    li t4, LD_VA
    j enter

// ECALL from S at VA_B (cause 9) ends one pass.
m_handler:
    csrr t1, mcause
    li t2, 9
    bne t1, t2, m_fail
    li t2, PT_ROOT + 8
    ld t1, 0(t2)
    andi t1, t1, 0x40             // the walker set A
    beqz t1, m_badpte
    addi s2, s2, 1
    li t2, ITERS
    bltu s2, t2, enter
    li t1, 0x10000000
    sd x0, 0(t1)
1:  j 1b
m_badpte:
    li t1, 0xF0
m_fail:
    ori t0, t1, 0x100
    slli t2, s2, 16
    or t0, t0, t2
    li t1, 0x10000000
    sd t0, 0(t1)
1:  j 1b

enter:
    li t2, PT_ROOT + 8
    li t1, PTE_B
    sd t1, 0(t2)                  // root[1]: A = 0 again
    sfence.vma                    // the load and VA_B miss the TLB
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
    .rept 14                      // the I$ line fill completes here
    nop
    .endr
    ld t6, 0(t4)                  // D-TLB miss: holds FENCE.I in ID
    fence.i                       // last word of page A
    .balign 4096
