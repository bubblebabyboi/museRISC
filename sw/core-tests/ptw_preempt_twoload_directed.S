// Fetch-walk preemption without any page-table miss in the D$
// (issue #73 oops hunt; see ptw_preempt_directed.S for the bug).
//
// Shape of the F2 oops at anon_vma_clone+0x62:
//     ld s11, 8(s4)     # load1: TLB hit, D$ miss (long refill)
//     ld a4, 0(s11)     # load2: TLB miss, another root entry
// While load1 waits for its D$ refill, IF runs into a page whose
// translation is not in the TLB and starts a fetch walk; the walk
// cannot use the data port (MEM owns it) and waits in W_VS_READ.
// When load1 completes, load2 enters MEM with a TLB miss, so in
// that same cycle the walker issues the fetch walk's root read
// (MEM no longer needs the port) AND sigil_mmu preempts the fetch
// walk for load2's data walk. The response of the fetch read (a
// D$ hit: all page-table lines stay resident here) is then taken
// as load2's root PTE.
//
// Tables (cacheable, D$ set 0, never evicted): root[0] -> L1A,
// L1A[0] = 2 MiB leaf VA 0..2M -> PA 0 (decoy), L1A[1] -> L0A (code,
// VA_A.., and VA_E -> page_e); root[1] -> L1D -> L0D (VA_D ->
// page_d = MAGIC). A data walk that consumes root[0] for VA_D
// follows L1A[0] and returns the first code word instead of MAGIC.
// Before each pass the M handler flushes the TLB, pre-loads page
// A's and VA_E's translations (MPRV loads) and evicts page_e's
// line (D$ set 32) so that load1 misses.
// Exit code 0 = pass; otherwise 0x100 | mcause (0x1FF = wrong
// data), plus (k << 12) and (iter << 16).
    .option norvc
    .text
    .globl _start

.equ PT_ROOT, 0x100000
.equ PT_L1A,  0x101000
.equ PT_L0A,  0x102000
.equ PT_L1D,  0x103000
.equ PT_L0D,  0x104000
.equ EVICT0,  0x110800       // 4K-strided lines in D$ set 32
.equ VA_A,    0x200000       // code: VA_A + i*4K -> code_pages + i*4K
.equ VA_E,    0x300000       // load1's page (L0A[256])
.equ VA_D,    0x40000000     // load2's page (root[1])
.equ MAGIC,   0x5a5a1234
.equ EMAGIC,  0x77
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
    li t1, 0xCF                   // L1A[0]: 2M leaf VA 0 -> PA 0 (decoy)
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
    la t1, page_e
    srli t1, t1, 2
    ori t1, t1, 0xC7              // RW A D
    li t2, PT_L0A + 256*8
    sd t1, 0(t2)                  // L0A[256]: VA_E -> page_e
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
    ori t1, t1, 0xC7
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
    li s8, VA_E + 0x800
    j enter

m_handler:
    csrr t1, mcause
    li t2, 9
    bne t1, t2, m_fail
    li t2, MAGIC
    bne a0, t2, m_bad
    li t2, EMAGIC
    bne t5, t2, m_bad
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

// Entry = VA_A + 2*k*4K + 4K - 8 - 4*k (load1, load2, k NOPs, page end).
enter:
    sfence.vma                    // cold TLB
    li a0, 0
    li t5, 0
    slli t1, s6, 13
    li t2, VA_A + 0x1000 - 8
    add t1, t1, t2
    slli t2, s6, 2
    sub t1, t1, t2
    csrw mepc, t1
    li t2, (3 << 11)
    csrc mstatus, t2
    li t2, (1 << 11)              // MPP = S
    csrs mstatus, t2
    // Pre-load page A's and VA_E's translations (MPRV loads).
    li t2, (1 << 17)
    csrs mstatus, t2
    lw t3, 0(t1)
    ld t3, 0(s8)
    csrc mstatus, t2
    // Evict page_e's line (set 32): 8 conflict loads.
    li t1, EVICT0
    li t3, 8
4:  ld t2, 0(t1)
    li t2, 0x1000
    add t1, t1, t2
    addi t3, t3, -1
    bnez t3, 4b
    mret

    .balign 4096
code_pages:
    .skip 0x1000 - 8
    ld t5, 0(s8)                  // load1 (VA_E, TLB hit, D$ miss)
    ld a0, 0(s5)                  // load2 (VA_D, TLB miss)
    ecall
    .skip 0x1000 - 4
    .skip 0x1000 - 12
    ld t5, 0(s8)
    ld a0, 0(s5)
    nop
    ecall
    .skip 0x1000 - 4
    .skip 0x1000 - 16
    ld t5, 0(s8)
    ld a0, 0(s5)
    nop
    nop
    ecall
    .skip 0x1000 - 4
    .skip 0x1000 - 20
    ld t5, 0(s8)
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
    .balign 4096
page_e:
    .skip 0x800
    .dword EMAGIC
    .skip 4096 - 0x808
