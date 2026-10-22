// Back-to-back fetch-walk preemptions (issue #73 skeptic review of
// the preemption fix). Page A_k ends with three loads to three
// different root entries, then k NOPs; IF runs into page B_k and
// starts a fetch walk. Load 1 preempts it with its root read in
// flight (trigger A); after load 1's data walk the fetch walk
// restarts but waits behind load 1's own port access, so load 2's
// miss preempts it in the very cycle the restarted fetch walk issues
// its root read (trigger B); load 3 repeats that. Every preemption
// must drop exactly the fetch walk's request and nothing of the
// data walks'. Tables in uncached RAM (each walk read pays the full
// bus latency). Exit code 0 = pass; otherwise 0x100 | mcause
// (0x1FF = wrong data) | (k << 12) | (iter << 16).
    .option norvc
    .text
    .globl _start

.equ PT_ROOT, 0x20020000     // uncached RAM in core_tb's map
.equ PT_L1A,  0x20021000
.equ PT_L0A,  0x20022000
.equ PT_L1D,  0x20023000     // + 0x2000 * j for data page j
.equ PT_END,  0x20029000
.equ VA_A,    0x200000       // code: VA_A + i*4K -> code_pages + i*4K
.equ VA_D1,   0x40000000     // root[1]
.equ VA_D2,   0x80000000     // root[2]
.equ VA_D3,   0xC0000000     // root[3]
.equ MAGIC1,  0x5a5a1111
.equ MAGIC2,  0x5a5a2222
.equ MAGIC3,  0x5a5a3333
.equ ITERS,   12
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
    li t2, PT_END
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
    // root[j] -> L1_j -> L0_j -> page_dj, j = 1..3
    li t4, 1
    la t5, page_d1
3:  li t1, PT_L1D - 0x2000
    slli t2, t4, 13
    add t1, t1, t2                // L1_j
    addi t3, t1, 0                // keep L1_j
    srli t1, t1, 2
    ori t1, t1, 0x01
    li t2, PT_ROOT
    slli t6, t4, 3
    add t2, t2, t6
    sd t1, 0(t2)                  // root[j] -> L1_j
    li t1, 0x1000
    add t1, t3, t1                // L0_j
    addi t6, t1, 0
    srli t1, t1, 2
    ori t1, t1, 0x01
    sd t1, 0(t3)                  // L1_j[0] -> L0_j
    srli t1, t5, 2
    ori t1, t1, 0xC7              // RW A D
    sd t1, 0(t6)                  // L0_j[0] -> page_dj
    li t1, 0x1000
    add t5, t5, t1
    addi t4, t4, 1
    li t1, 4
    bltu t4, t1, 3b
    li t1, 8
    slli t1, t1, 60
    li t2, PT_ROOT >> 12
    or t1, t1, t2
    csrw satp, t1
    li s2, 0                      // iteration
    li s6, 0                      // variant k
    li s5, VA_D1
    li s7, VA_D2
    li s8, VA_D3
    j enter

m_handler:
    csrr t1, mcause
    li t2, 9
    bne t1, t2, m_fail
    li t2, MAGIC1
    bne a0, t2, m_bad
    li t2, MAGIC2
    bne a1, t2, m_bad
    li t2, MAGIC3
    bne a2, t2, m_bad
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
    li t1, 0xFF
m_fail:
    ori t0, t1, 0x100
    slli t2, s6, 12
    or t0, t0, t2
    slli t2, s2, 16
    or t0, t0, t2
    li t1, 0x10000000
    sd t0, 0(t1)
1:  j 1b

// Entry = VA_A + 2*k*4K + 4K - 12 - 4*k.
enter:
    sfence.vma
    li a0, 0
    li a1, 0
    li a2, 0
    slli t1, s6, 13
    li t2, VA_A + 0x1000 - 12
    add t1, t1, t2
    slli t2, s6, 2
    sub t1, t1, t2
    csrw mepc, t1
    li t2, (3 << 11)
    csrc mstatus, t2
    li t2, (1 << 11)              // MPP = S
    csrs mstatus, t2
    // Pre-load page A's translation (MPRV load) so the first walk
    // of the pass is the page-B fetch walk.
    li t2, (1 << 17)
    csrs mstatus, t2
    lw t3, 0(t1)
    csrc mstatus, t2
    mret

    .balign 4096
code_pages:
    .skip 0x1000 - 12
    ld a0, 0(s5)
    ld a1, 0(s7)
    ld a2, 0(s8)
    ecall
    .skip 0x1000 - 4
    .skip 0x1000 - 16
    ld a0, 0(s5)
    ld a1, 0(s7)
    ld a2, 0(s8)
    nop
    ecall
    .skip 0x1000 - 4
    .skip 0x1000 - 20
    ld a0, 0(s5)
    ld a1, 0(s7)
    ld a2, 0(s8)
    nop
    nop
    ecall
    .skip 0x1000 - 4
    .skip 0x1000 - 24
    ld a0, 0(s5)
    ld a1, 0(s7)
    ld a2, 0(s8)
    nop
    nop
    nop
    ecall
    .skip 0x1000 - 4

    .balign 4096
page_d1:
    .dword MAGIC1
    .skip 4096 - 8
page_d2:
    .dword MAGIC2
    .skip 4096 - 8
page_d3:
    .dword MAGIC3
    .skip 4096 - 8
