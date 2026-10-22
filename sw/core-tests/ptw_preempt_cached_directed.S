// Data-miss preemption of an in-flight fetch walk, page tables in
// cacheable RAM (issue #73 oops hunt; companion of
// ptw_preempt_directed.S, which keeps the tables uncached).
//
// Same shape: S-mode code ends page A with a load from VA_D
// (root[1]) and k = 0..3 NOPs; IF runs into page B, misses the
// TLB and its fetch walk reads root[0] through the D$ while the
// load is still in ID/EX; the load then misses the TLB in MEM and
// preempts the fetch walk. Here root[0]'s table L1A has a valid
// 2 MiB leaf at index 0 (VA 0..2M -> PA 0, the test image), so a
// data walk that consumes the fetch walk's root[0] response
// translates VA_D (L1 index 0) to PA 0 and the load silently
// returns the first code word instead of MAGIC: wrong data through
// a valid mapping, no trap (the second F2 oops signature), and the
// bad 2 MiB TLB entry for VA_D stays until the next SFENCE.VMA.
//
// Before each pass the M handler flushes the TLB and pre-loads
// page A's translation (an MPRV load), so only page B's fetch
// walks. Phase 0: it then evicts the page-table lines from the D$
// (conflict loads to the same set), so the fetch walk's reads miss
// and take the bus latency, as a PTE miss does on the F2 DDR4.
// Phase 1: no eviction (walk reads hit in the D$).
// Exit code 0 = pass; otherwise 0x100 | mcause (0x1FF = wrong data),
// plus (k << 12), (phase << 15), (iter << 16).
    .option norvc
    .text
    .globl _start

.equ PT_ROOT, 0x100000
.equ PT_L1A,  0x101000
.equ PT_L0A,  0x102000
.equ PT_L1D,  0x103000
.equ PT_L0D,  0x104000
.equ EVICT0,  0x110000       // 4 lines in the same D$ set as the tables
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
    li t1, 0xCF                   // L1A[0]: 2M leaf VA 0 -> PA 0, RWX A D
    li t2, PT_L1A
    sd t1, 0(t2)
    li t1, PT_L0A
    srli t1, t1, 2
    ori t1, t1, 0x01
    sd t1, 8(t2)                  // L1A[1] -> L0A (VA 2M..4M)
    la t1, code_pages
    srli t1, t1, 2
    ori t1, t1, 0xCB              // RX A D
    li t2, PT_L0A
    li t3, 2*NVAR
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
    fence.i
    li t1, 8
    slli t1, t1, 60
    li t2, PT_ROOT >> 12
    or t1, t1, t2
    csrw satp, t1
    li s2, 0                      // iteration
    li s6, 0                      // variant k
    li s7, 0                      // phase
    li s5, VA_D
    j enter

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
    li s2, 0
    addi s7, s7, 1
    li t2, 2
    bltu s7, t2, enter
    li t1, 0x10000000
    sd x0, 0(t1)
1:  j 1b
m_bad:
    li t1, 0xFF                   // wrong data, no trap
m_fail:
    ori t0, t1, 0x100
    slli t2, s6, 12
    or t0, t0, t2
    slli t2, s7, 15
    or t0, t0, t2
    slli t2, s2, 16
    or t0, t0, t2
    li t1, 0x10000000
    sd t0, 0(t1)
1:  j 1b

enter:
    sfence.vma                    // cold TLB
    li a0, 0
    slli t1, s6, 13
    li t2, VA_A + 0x1000 - 4
    add t1, t1, t2
    slli t2, s6, 2
    sub t1, t1, t2
    csrw mepc, t1
    li t2, (3 << 11)
    csrc mstatus, t2
    li t2, (1 << 11)              // MPP = S
    csrs mstatus, t2
    // Pre-load page A's translation (MPRV: an S-mode data access
    // walks and fills the unified TLB; the RX leaf is readable), so
    // that only page B's fetch walks after MRET.
    li t2, (1 << 17)
    csrs mstatus, t2
    lw t3, 0(t1)
    csrc mstatus, t2
    bnez s7, 3f
    // Evict the page-table lines (all in D$ set 0): 2 x 4 conflict
    // loads, so page B's walk reads miss in the D$.
    li t1, EVICT0
    li t3, 8
4:  ld t2, 0(t1)
    li t2, 0x1000
    add t1, t1, t2
    addi t3, t3, -1
    bnez t3, 4b
3:  mret

    .balign 4096
code_pages:
    .skip 0x1000 - 4
    ld a0, 0(s5)
    ecall
    .skip 0x1000 - 4
    .skip 0x1000 - 8
    ld a0, 0(s5)
    nop
    ecall
    .skip 0x1000 - 4
    .skip 0x1000 - 12
    ld a0, 0(s5)
    nop
    nop
    ecall
    .skip 0x1000 - 4
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
