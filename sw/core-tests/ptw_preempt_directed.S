// Data-miss preemption of a fetch walk whose PTE read is already
// on the data port (issue #73 Linux oops; fixed by sigil_mmu
// walk_abandon_o, which makes the core drop that read).
//
// S-mode code ends a 4 KiB page A with a load from VA_D (a page
// under a different root entry, root[1]) followed by k = 0..3
// NOPs, so IF runs on into page B, misses the TLB and starts a
// fetch walk whose root read (root[0]) goes onto the data port
// while the load is still in ID/EX. The load then reaches MEM
// with a TLB miss of its own: sigil_mmu preempts the fetch walk
// ("an older data miss preempts a fetch walk") and restarts as a
// data walk for VA_D, but the fetch walk's root read is still in
// flight. Its response must not be consumed by the data walk: if
// it is, the data walk takes root[0] (-> L1A) as VA_D's root PTE,
// follows L1A[VA_D[29:21] = 0], which is invalid, and raises a
// load page fault on a valid, mapped address (or, with a valid
// L1A[0], translates VA_D to the wrong page).
//
// Page tables live in uncached RAM (core_tb I/O window), so each
// walk read takes the full bus latency, as a D$ miss on a PTE
// line does on the F2 DDR4. The M handler flushes the TLB and
// re-enters page A ITERS times per variant. Exit code 0 = pass;
// otherwise 0x100 | mcause, plus (k << 12), plus (iter << 16).
    .option norvc
    .text
    .globl _start

.equ PT_ROOT, 0x20020000     // uncached RAM in core_tb's map
.equ PT_L1A,  0x20021000
.equ PT_L0A,  0x20022000
.equ PT_L1D,  0x20023000
.equ PT_L0D,  0x20024000
.equ VA_A,    0x200000       // code: VA_A + i*4K -> code_pages + i*4K
.equ VA_D,    0x40000000     // data page (root[1])
.equ MAGIC,   0x5a5a1234
.equ ITERS,   16
.equ NVAR,    4

_start:
    li t0, 1
    la t1, m_handler
    csrw mtvec, t1
    li t1, -1
    csrw pmpaddr15, t1
    li t1, 0x1f
    slli t1, t1, 56
    csrw pmpcfg2, t1
    // Zero the five table pages.
    li t1, PT_ROOT
    li t2, PT_ROOT + 0x5000
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
    // L0A[i]: VA_A + i*4K -> code_pages + i*4K, i = 0 .. 2*NVAR-1
    la t1, code_pages
    srli t1, t1, 2
    ori t1, t1, 0xCB              // RX A D
    li t2, PT_L0A
    li t3, 2*NVAR
2:  sd t1, 0(t2)
    addi t1, t1, 0x400            // +4 KiB in PPN<<10 form
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
    fence.i
    li t1, 8
    slli t1, t1, 60
    li t2, PT_ROOT >> 12
    or t1, t1, t2
    csrw satp, t1
    li s2, 0                      // iteration
    li s6, 0                      // variant k
    li s5, VA_D
    j enter

// ECALL from S (page B) ends one pass: a0 must hold MAGIC.
m_handler:
    csrr t1, mcause
    li t2, 9
    bne t1, t2, m_fail
    li t2, MAGIC
    bne a0, t2, m_bad
    addi s6, s6, 1
    li t2, NVAR
    bltu s6, t2, enter
    li s6, 0
    addi s2, s2, 1
    li t2, ITERS
    bltu s2, t2, enter
    li t1, 0x10000000
    sd x0, 0(t1)
1:  j 1b
m_bad:
    li t1, 0xFF                   // wrong data, no trap
m_fail:
    ori t0, t1, 0x100
    slli t2, s6, 12
    or t0, t0, t2
    slli t2, s2, 16
    or t0, t0, t2
    li t1, 0x10000000
    sd t0, 0(t1)
1:  j 1b

// Enter variant s6: entry = VA_A + 2*k*4K + 4K - 4*(k+1).
enter:
    sfence.vma                    // cold TLB
    li a0, 0
    slli t1, s6, 13               // 2*k*4K
    li t2, VA_A + 0x1000 - 4
    add t1, t1, t2
    slli t2, s6, 2
    sub t1, t1, t2
    csrw mepc, t1
    li t1, (3 << 11)
    csrc mstatus, t1
    li t1, (1 << 11)              // MPP = S
    csrs mstatus, t1
    mret

    .balign 4096
code_pages:
// page A0 / B0: load is the last word of A (k = 0)
    .skip 0x1000 - 4
    ld a0, 0(s5)
    ecall
    .skip 0x1000 - 4
// page A1 / B1 (k = 1)
    .skip 0x1000 - 8
    ld a0, 0(s5)
    nop
    ecall
    .skip 0x1000 - 4
// page A2 / B2 (k = 2)
    .skip 0x1000 - 12
    ld a0, 0(s5)
    nop
    nop
    ecall
    .skip 0x1000 - 4
// page A3 / B3 (k = 3)
    .skip 0x1000 - 16
    ld a0, 0(s5)
    nop
    nop
    nop
    ecall
    .skip 0x1000 - 4

    .balign 4096
page_d:
    .dword MAGIC
    .skip 4096 - 8
