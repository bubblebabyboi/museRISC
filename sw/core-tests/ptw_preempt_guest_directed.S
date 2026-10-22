// Data-miss preemption of a fetch walk, two-stage variants (issue
// #73 oops review, other-preemption-paths lens; H extension).
//   phase 0: guest (VS-mode, vsatp Sv39 over Sv39x4), shape of
//            ptw_preempt_directed.S: page A ends with a load from
//            VA_D (VS root[1]) and k = 0..3 NOPs, IF runs into page
//            B, and the load preempts B's fetch walk.
//   phase 1: as phase 0 in HS-mode (V=0, satp Sv39) with HLV.D
//            (SPVP=1) as the load: a single-stage fetch walk
//            preempted by a two-stage data walk.
//   phases 2, 3: guest. An older load reaches MEM about two cycles
//            after IF enters page B, i.e. always during the fetch
//            walk's first read, which in a guest is the G-root read
//            for the VS root PTE: the same address as the data
//            walk's first read, so a stale copy is harmless. To
//            preempt the walk at every later read (VS root, VS L1,
//            VS leaf, and the G reads between them) page A ends
//            with `jr t6`: IF falls through into page B (jumps
//            resolve in EX) and starts its walk, then the jump
//            lands in a NOP sled in page A (TLB hit) that runs N
//            NOPs before the load, while the abandoned walk goes
//            on. phase 2: G root and upper VS levels cacheable, the
//            code L0 table uncached, N = 0, 2, .., 62; phase 3: all
//            tables uncached, N = 0, 16, .., 496.
// A stale VS-stage PTE taken as the data walk's G-root entry
// sends the G walk through a VS table and raises a load
// guest-page fault (cause 21) on a valid address; other mixes
// give wrong data (0x1FF). Exit code 0 = pass; otherwise
// 0x100 | mcause, plus (variant << 12), (iter << 20),
// (phase << 24).
    .option arch, +h
    .option norvc
    .text
    .globl _start

.equ PT_ROOT,  0x20020000    // VS root (also the HS satp root)
.equ PT_L1A,   0x20021000
.equ PT_L0A,   0x20022000
.equ PT_L1D,   0x20023000
.equ PT_L0D,   0x20024000
.equ PT_GROOT, 0x20030000    // Sv39x4 root (16 KiB aligned)
.equ PT2_GROOT, 0x00100000   // phase 2: cacheable, beyond the image
.equ PT2_ROOT,  0x00104000
.equ PT2_L1A,   0x00105000
.equ PT2_L1D,   0x00106000
.equ PT2_L0D,   0x00107000
.equ PT2_L0A,   0x20026000   // phase 2: the one uncached level
.equ VA_A,     0x200000      // code: VA_A + i*4K -> code_pages + i*4K
.equ VA_D,     0x40000000    // data page (VS root[1])
.equ NPAGES,   18            // code pages (pairs 0..8)
.equ SLED,     512           // NOPs in the phase-2/3 sled
.equ MAGIC,    0x5a5a1234
.equ ITERS,    16            // phases 0, 1
.equ ITERS2,   4             // phases 2, 3
.equ NVAR,     4             // phases 0, 1: k
.equ NVAR2,    32            // phases 2, 3: sled lengths
.equ NPHASE,   4

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
    // Flags: V1 R2 W4 X8 U16 A64 D128. Pointer = V only.
    // Table set 1 (all uncached). G root[0]: 1 GiB identity leaf.
    li t2, PT_GROOT
    li t1, 0xdf
    sd t1, 0(t2)
    li t1, (PT_L1A >> 2) | 0x01
    li t2, PT_ROOT
    sd t1, 0(t2)                  // root[0] -> L1A
    li t1, (PT_L0A >> 2) | 0x01
    li t2, PT_L1A + 8
    sd t1, 0(t2)                  // L1A[1] -> L0A (VA 2M..4M)
    la t1, code_pages             // L0A[i]: VA_A + i*4K -> code_pages + i*4K
    srli t1, t1, 2
    ori t1, t1, 0xCB              // RX A D
    li t2, PT_L0A
    li t3, NPAGES
2:  sd t1, 0(t2)
    addi t1, t1, 0x400            // +4 KiB in PPN<<10 form
    addi t2, t2, 8
    addi t3, t3, -1
    bnez t3, 2b
    li t1, (PT_L1D >> 2) | 0x01
    li t2, PT_ROOT + 8
    sd t1, 0(t2)                  // root[1] -> L1D
    li t1, (PT_L0D >> 2) | 0x01
    li t2, PT_L1D
    sd t1, 0(t2)                  // L1D[0] -> L0D
    la t1, page_d
    srli t1, t1, 2
    ori t1, t1, 0xC7              // RW A D
    li t2, PT_L0D
    sd t1, 0(t2)                  // L0D[0]: VA_D -> page_d
    // Table set 2 (same map; only L0A2 uncached).
    li t2, PT2_GROOT
    li t1, 0xdf
    sd t1, 0(t2)
    li t1, (PT2_L1A >> 2) | 0x01
    li t2, PT2_ROOT
    sd t1, 0(t2)
    li t1, (PT2_L1D >> 2) | 0x01
    sd t1, 8(t2)
    li t1, (PT2_L0A >> 2) | 0x01
    li t2, PT2_L1A + 8
    sd t1, 0(t2)
    li t1, (PT2_L0D >> 2) | 0x01
    li t2, PT2_L1D
    sd t1, 0(t2)
    la t1, page_d
    srli t1, t1, 2
    ori t1, t1, 0xC7
    li t2, PT2_L0D
    sd t1, 0(t2)
    la t1, code_pages
    srli t1, t1, 2
    ori t1, t1, 0xCB
    li t2, PT2_L0A
    li t3, NPAGES
2:  sd t1, 0(t2)
    addi t1, t1, 0x400
    addi t2, t2, 8
    addi t3, t3, -1
    bnez t3, 2b
    fence.i
    li t1, 8
    slli t1, t1, 60
    li t2, PT_ROOT >> 12
    or t2, t2, t1
    csrw satp, t2                 // HS translation (phase 1)
    li t1, (1 << 8)
    csrs hstatus, t1              // SPVP = 1: HLV accesses as VS
    li s2, 0                      // iteration
    li s3, 0                      // phase
    li s6, 0                      // variant
    li s5, VA_D
    j enter

// ECALL ends one pass: cause 9 (from HS) in phase 1, else 10 (from
// VS); a0 must hold MAGIC.
m_handler:
    csrr t1, mcause
    li t2, 10
    li t3, 1
    bne s3, t3, 1f
    li t2, 9
1:  bne t1, t2, m_fail
    li t2, MAGIC
    bne a0, t2, m_bad
    li t3, 2
    addi s6, s6, 1
    li t2, NVAR
    bltu s3, t3, 1f
    li t2, NVAR2
1:  bltu s6, t2, enter
    li s6, 0
    addi s2, s2, 1
    li t2, ITERS
    bltu s3, t3, 1f
    li t2, ITERS2
1:  bltu s2, t2, enter
    li s2, 0
    addi s3, s3, 1
    li t2, NPHASE
    bltu s3, t2, enter
    li t1, 0x10000000
    sd x0, 0(t1)
1:  j 1b
m_bad:
    li t1, 0xFF                   // wrong data, no trap
m_fail:
    ori t0, t1, 0x100
    slli t2, s6, 12
    or t0, t0, t2
    slli t2, s2, 20
    or t0, t0, t2
    slli t2, s3, 24
    or t0, t0, t2
    li t1, 0x10000000
    sd t0, 0(t1)
1:  j 1b

enter:
    // vsatp/hgatp: table set 2 in phase 2, else set 1.
    li t1, 8
    slli t1, t1, 60
    li t2, PT_ROOT >> 12
    li t3, PT_GROOT >> 12
    li t4, 2
    bne s3, t4, 1f
    li t2, PT2_ROOT >> 12
    li t3, PT2_GROOT >> 12
1:  or t2, t2, t1
    csrw vsatp, t2
    or t3, t3, t1
    csrw hgatp, t3
    sfence.vma
    hfence.gvma
    hfence.vvma
    li a0, 0
    li t4, 2
    bgeu s3, t4, 3f
    // Phases 0, 1: pair p = k (+ NVAR in phase 1), page A of pair p
    // at VA_A + 2*p*4K, entry = its end - 4*(k+1).
    mv t1, s6
    li t4, 1
    bne s3, t4, 1f
    addi t1, t1, NVAR
1:  slli t1, t1, 13               // 2*p*4K
    li t2, VA_A + 0x1000 - 4
    add t1, t1, t2
    slli t2, s6, 2
    sub t1, t1, t2
    j 4f
    // Phases 2, 3: pair 8, entry at its `jr t6`; t6 = sled entry
    // that runs N NOPs (N = 2*v in phase 2, 16*v in phase 3).
3:  slli t2, s6, 1
    li t4, 3
    bne s3, t4, 1f
    slli t2, s6, 4
1:  li t6, VA_A + 16*0x1000 + SLED*4
    slli t2, t2, 2
    sub t6, t6, t2
    li t1, VA_A + 16*0x1000 + 0xFFC
4:  csrw mepc, t1
    li t1, (3 << 11)
    csrc mstatus, t1
    li t1, (1 << 11)              // MPP = S
    csrs mstatus, t1
    li t1, 1
    slli t1, t1, 39               // MPV
    csrc mstatus, t1
    li t2, 1
    beq s3, t2, 1f
    csrs mstatus, t1              // phases 0, 2, 3: enter VS
1:  mret

    .balign 4096
code_pages:
// phase 0 (guest load), pairs 0..3
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
// phase 1 (HS HLV.D), pairs 4..7
    .skip 0x1000 - 4
    hlv.d a0, (s5)
    ecall
    .skip 0x1000 - 4
    .skip 0x1000 - 8
    hlv.d a0, (s5)
    nop
    ecall
    .skip 0x1000 - 4
    .skip 0x1000 - 12
    hlv.d a0, (s5)
    nop
    nop
    ecall
    .skip 0x1000 - 4
    .skip 0x1000 - 16
    hlv.d a0, (s5)
    nop
    nop
    nop
    ecall
    .skip 0x1000 - 4
// phases 2, 3: pair 8. Page A: NOP sled, load, ECALL; `jr t6` in
// its last word. Page B is only ever fetched on the wrong path.
pair8_a:
    .rept SLED
    nop
    .endr
    ld a0, 0(s5)
    ecall
    .skip 0x1000 - SLED*4 - 12
    jr t6
pair8_b:
    ecall
    .skip 0x1000 - 4

    .balign 4096
page_d:
    .dword MAGIC
    .skip 4096 - 8
