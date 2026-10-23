// Stale walker response after a G-stage GPA-width fault (issue #73
// skeptic review of the fetch-walk preemption fix).
//
// sigil_mmu leaves W_G_READ without a walker grant in one more case
// besides flush/abort and data-miss preemption: g_width_fault (the
// GPA to translate has bits above 40 set), which ends the walk in
// its first W_G_READ cycle. In that same cycle the core's walk_issue
// is free to send the G-root read for that GPA (walk_req_o is just
// state != W_IDLE), and nothing arms dq_drop_q, so the read stays
// live on the data port while the walker is idle. The next walk to
// start (a fetch walk, or a data walk) takes the response as its
// own first PTE.
//
// Guest (V=1, VS-mode) code under Sv39 vsatp + Sv39x4 hgatp, all
// tables in uncached RAM. Page A (VA 0x3FFFF000, root[0]) ends with
// [div] jr s3, so IF runs into page B (VA 0x40000000) and starts a
// fetch walk: G-read of the VS root GPA, VS root[1], which points
// to an L1 table at a GPA with bit 41 set -> W_G_READ with
// g_width_fault, issuing a read of G_ROOT[2] (= 0). The jr has
// meanwhile redirected to page C (VA 0x80000000, root[2]), where a
// NOP sled of n instructions precedes ld a0, 0(VA_D) (root[3]) and
// ecall. The B walk is speculative: it must vanish without effect.
//   phase 0 (fetch consumer): page C is cold, so its fetch walk
//     starts right after the width fault; consuming the stale
//     G_ROOT[2] = 0 as its G-root PTE gives an instruction
//     guest-page fault (cause 20) on a valid page.
//   phases 1, 2 (data consumer, page C pre-loaded, n = 0..NMAX-1,
//     entry at jr / at div): the load's data walk either preempts
//     the B walk (n small: the preemption fix's own case, for a
//     G-stage fetch walk) or starts after the width fault and takes
//     G_ROOT[2] = 0 (load guest-page fault, cause 21).
// PTW_GW_DATA_ONLY (ptw_gwidth_load_directed.S) skips phase 0, so a
// failure shows the data-walk consumer.
// With PTW_HYP_GOOD_B defined (ptw_preempt_hyp_directed.S) page B
// is validly mapped instead (7-read G-stage fetch walk), which
// isolates the preemption of W_G_READ / W_VS_READ fetch walks.
// Exit code 0 = pass; otherwise 0x100 | mcause (0x1FF = wrong data)
// | (phase << 12) | (n << 16).
    .option arch, +h
    .option norvc
    .text
    .globl _start

.equ G_ROOT,  0x20020000     // Sv39x4 root, 16 KiB (uncached)
.equ VS_ROOT, 0x20024000
.equ VS_L1A,  0x20025000
.equ VS_L0A,  0x20026000
.equ VS_L1C,  0x20027000
.equ VS_L0C,  0x20028000
.equ VS_L1D,  0x20029000
.equ VS_L0D,  0x2002A000
.equ VS_L1B,  0x2002B000     // PTW_HYP_GOOD_B only
.equ VS_L0B,  0x2002C000
.equ PT_END,  0x2002D000
.equ VA_A,    0x3FFFF000     // root[0] L1[511] L0[511]
.equ VA_B,    0x40000000     // root[1]
.equ VA_C,    0x80000000     // root[2]
.equ VA_D,    0xC0000000     // root[3]
.equ BAD_IDX, 2              // GPA[40:30] of the bad GPA
.equ MAGIC,   0x5a5a1234
.equ NF,      8              // phase-0 passes
#ifndef NMAX
.equ NMAX,    320            // sled lengths per data phase
#endif
.equ SLED,    1000

_start:
    li t0, 1
    la t1, m_handler
    csrw mtvec, t1
    li t1, -1
    csrw pmpaddr15, t1
    li t1, 0x1f
    slli t1, t1, 56
    csrw pmpcfg2, t1
    li t1, G_ROOT
    li t2, PT_END
1:  sd x0, 0(t1)
    addi t1, t1, 8
    bltu t1, t2, 1b
    // G stage: GPA 0..1G -> PA 0..1G (1 GiB leaf, V R W X U A D).
    li t1, 0xDF
    li t2, G_ROOT
    sd t1, 0(t2)
    // VS flags: V1 R2 W4 X8 A64 D128. Pointer = V only.
    li t1, VS_L1A
    srli t1, t1, 2
    ori t1, t1, 0x01
    li t2, VS_ROOT
    sd t1, 0(t2)                  // root[0] -> L1A
    li t1, VS_L0A
    srli t1, t1, 2
    ori t1, t1, 0x01
    li t2, VS_L1A + 511*8
    sd t1, 0(t2)                  // L1A[511] -> L0A
    la t1, code_a
    srli t1, t1, 2
    ori t1, t1, 0xCB              // RX A D
    li t2, VS_L0A + 511*8
    sd t1, 0(t2)                  // L0A[511]: VA_A -> code_a
#ifdef PTW_HYP_GOOD_B
    li t1, VS_L1B
    srli t1, t1, 2
    ori t1, t1, 0x01
    li t2, VS_ROOT + 8
    sd t1, 0(t2)                  // root[1] -> L1B
    li t1, VS_L0B
    srli t1, t1, 2
    ori t1, t1, 0x01
    li t2, VS_L1B
    sd t1, 0(t2)                  // L1B[0] -> L0B
    la t1, code_b
    srli t1, t1, 2
    ori t1, t1, 0xCB
    li t2, VS_L0B
    sd t1, 0(t2)                  // L0B[0]: VA_B -> code_b
#else
    li t1, 1
    slli t1, t1, 29               // PPN of GPA (1 << 41) | (BAD_IDX << 30)
    li t2, BAD_IDX << 18
    or t1, t1, t2
    slli t1, t1, 10
    ori t1, t1, 0x01
    li t2, VS_ROOT + 8
    sd t1, 0(t2)                  // root[1] -> L1 at a 42-bit GPA
#endif
    li t1, VS_L1C
    srli t1, t1, 2
    ori t1, t1, 0x01
    li t2, VS_ROOT + 16
    sd t1, 0(t2)                  // root[2] -> L1C
    li t1, VS_L0C
    srli t1, t1, 2
    ori t1, t1, 0x01
    li t2, VS_L1C
    sd t1, 0(t2)                  // L1C[0] -> L0C
    la t1, code_c
    srli t1, t1, 2
    ori t1, t1, 0xCB
    li t2, VS_L0C
    sd t1, 0(t2)                  // L0C[0]: VA_C -> code_c
    li t1, VS_L1D
    srli t1, t1, 2
    ori t1, t1, 0x01
    li t2, VS_ROOT + 24
    sd t1, 0(t2)                  // root[3] -> L1D
    li t1, VS_L0D
    srli t1, t1, 2
    ori t1, t1, 0x01
    li t2, VS_L1D
    sd t1, 0(t2)                  // L1D[0] -> L0D
    la t1, page_d
    srli t1, t1, 2
    ori t1, t1, 0xC7              // RW A D
    li t2, VS_L0D
    sd t1, 0(t2)                  // L0D[0]: VA_D -> page_d
    // hgatp Sv39x4 VMID 1, vsatp Sv39.
    li t1, 0x8001000000000000
    li t2, G_ROOT >> 12
    or t1, t1, t2
    csrw hgatp, t1
    li t1, 0x8000000000000000
    li t2, VS_ROOT >> 12
    or t1, t1, t2
    csrw vsatp, t1
    li s2, 0                      // passes done
#ifdef PTW_GW_DATA_ONLY
    li s4, 1                      // phase (data consumers only)
#else
    li s4, 0                      // phase
#endif
    li s6, 0                      // n (sled length) / phase-0 pass
    li s5, VA_D
    li s9, 1
    li s10, 1
    slli s10, s10, 60             // div s10/s9: ~33 EX cycles
    j enter

// ECALL from VS (cause 10) ends a pass; a0 must hold MAGIC.
m_handler:
    csrr t1, mcause
    li t2, 10
    bne t1, t2, m_fail
    li t2, MAGIC
    bne a0, t2, m_bad
    addi s2, s2, 1
    addi s6, s6, 1
    li t2, NF
    beqz s4, 2f
    li t2, NMAX
2:  bltu s6, t2, enter
    li s6, 0
    addi s4, s4, 1
    li t2, 3
    bltu s4, t2, enter
    li t1, 0x10000000
    sd x0, 0(t1)
1:  j 1b
m_bad:
    li t1, 0xFF                   // wrong data, no trap
m_fail:
    ori t0, t1, 0x100
    slli t2, s4, 12
    or t0, t0, t2
    slli t2, s6, 16
    or t0, t0, t2
    li t1, 0x10000000
    sd t0, 0(t1)
1:  j 1b

enter:
    sfence.vma                    // cold TLB
    li a0, 0
    // jr target: VA_C + 4 * (SLED - n); phase 0 uses n = 0.
    li t1, SLED
    beqz s4, 3f
    sub t1, t1, s6
3:  slli t1, t1, 2
    li s3, VA_C
    add s3, s3, t1
    // Entry: jr (phases 0, 1) or div; jr (phase 2).
    li t1, VA_A + 0xFFC
    li t2, 2
    bne s4, t2, 4f
    addi t1, t1, -4
4:  csrw mepc, t1
    li t2, (3 << 11)
    csrc mstatus, t2
    li t2, (1 << 11)              // MPP = S
    csrs mstatus, t2
    li t2, 1
    slli t2, t2, 39               // MPV = 1: mret enters VS
    csrs mstatus, t2
    // Pre-load page A (and page C in phases 1, 2) with MPRV loads
    // translated as VS (MPRV, MPP = S, MPV = 1).
    li t2, (1 << 17)
    csrs mstatus, t2
    lw t3, 0(t1)
    beqz s4, 5f
    li t1, VA_C
    lw t3, 0(t1)
5:  li t2, (1 << 17)
    csrc mstatus, t2
    mret

    .balign 4096
code_a:
    .skip 0x1000 - 8
    div t3, s10, s9
    jr s3
#ifdef PTW_HYP_GOOD_B
    .balign 4096
code_b:
    ecall                         // never reached (speculative fetch)
    .skip 0x1000 - 4
#endif
    .balign 4096
code_c:
    .rept SLED
    nop
    .endr
    ld a0, 0(s5)
    ecall
    .balign 4096
page_d:
    .dword MAGIC
    .skip 4096 - 8
