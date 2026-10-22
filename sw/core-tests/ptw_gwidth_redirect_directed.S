// G-stage GPA-width fault abandons a walker read that is already
// on the data port (issue #73 oops review, other-preemption-paths
// lens; H extension, two-stage translation).
//
// sigil_mmu W_G_READ checks g_width_fault (GPA bits above 40 set)
// before walk_grant_i and goes to W_IDLE in the same cycle that
// it asserts walk_req_o, so the core issues that state's G-root
// read (hgatp root + GPA[40:30]*8) onto the data port. Nothing
// drops its response: dq_drop_q is armed only on sfence, trap or
// fetch-walk preemption. The next walk that starts from W_IDLE
// before the response returns takes it as its own first read.
//
// The guest runs in VS-mode (vsatp Sv39 over an Sv39x4 G stage).
// Guest code at VA_A = 0x3FFF_F000 ends with `jr s8`. The core
// predicts not-taken and resolves jumps in EX, so IF falls
// through into VA_B = 0x4000_0000 and starts a fetch walk. VS
// root[1] points at a next-level table at GPA 2^41 + GX GiB, so
// that (wrong-path) walk ends with a GPA-width guest-page fault,
// after issuing a read of G root[GX]. The right G-root entry for
// every other walk here is G root[0].
//   phases 0, 1: the jump goes to VA_C (cold TLB, k = 0..3 NOPs
//     before the jump). VA_C's fetch walk starts from W_IDLE while
//     the G root[GX] read is in flight and takes it as the G leaf
//     for its VS root PTE.
//   phases 2, 3: the jump goes into a NOP sled in page A (TLB hit)
//     that runs N = 0, 2, .., 126 NOPs and then loads from VA_D
//     (cold TLB). When the load misses after the width fault and
//     before the stale response returns, the data walk starts
//     from W_IDLE and takes G root[GX] as the G leaf for its VS
//     root PTE (no preemption is involved, so the drop-on-preempt
//     fix does not apply).
//   phases 0, 2: G root[GX] = 0. Instruction (20) or load (21)
//     guest-page fault on a valid, mapped page.
//   phases 1, 3: G root[GX] = 1 GiB leaf to SPA 0x8000_0000. The
//     walk reads a planted VS root at SPA 0xA002_0000 (a 1 GiB VS
//     leaf, VA = GPA) and then runs the wrong code at SPA
//     0x3FFF_E000 (phase 1) or loads the wrong dword at SPA
//     0x3FFF_D000 (phase 3), with no trap.
// Correct hardware ends every pass with ECALL from VS (cause 10)
// and a0 = MAGIC. Page tables live in uncached RAM (core_tb I/O
// window), so every walker read takes the full bus latency. Exit
// code 0 = pass; otherwise 0x100 | mcause (0x1FF = wrong code or
// data, no trap), plus (variant << 12), (iter << 20),
// (phase << 24).
    .option arch, +h
    .option norvc
    .text
    .globl _start

.equ PT_VSROOT, 0x20020000   // uncached RAM in core_tb's map
.equ PT_VSL1,   0x20021000   // VS root[0] -> VA 0 .. 1G
.equ PT_VSL0,   0x20022000   // VSL1[511]  -> VA 0x3FE0_0000 .. 1G
.equ PT_GROOT,  0x20030000   // Sv39x4 root (16 KiB aligned)
.equ VA_A,      0x3FFFF000   // last guest page under VS root[0]
.equ VA_B,      0x40000000   // VS root[1]: next level at GPA >= 2^41
.equ VA_C,      0x3FFFE000   // phases 0, 1: jump target page
.equ VA_D,      0x3FFFD000   // phases 2, 3: load page
.equ GX,        5            // G root index of the abandoned read
.equ BADGPA,    (1 << 41) | (GX << 30)
.equ FAKE_VSROOT, 0xA0020000 // 0x8000_0000 + (PT_VSROOT & (1G-1))
.equ WRONG_CODE, 0x3FFFE000  // SPA a fake 1G VS leaf gives VA_C
.equ WRONG_DATA, 0x3FFFD000  // SPA a fake 1G VS leaf gives VA_D
.equ SLED,      128
.equ MAGIC,     0x5a5a1234
.equ ITERS,     8            // phases 0, 1
.equ ITERS2,    2            // phases 2, 3
.equ NVAR,      4            // phases 0, 1: k
.equ NVAR2,     64           // phases 2, 3: N = 2*v
.equ NPHASE,    4

_start:
    li t0, 1
    la t1, m_handler
    csrw mtvec, t1
    li t1, -1
    csrw pmpaddr15, t1
    li t1, 0x1f
    slli t1, t1, 56
    csrw pmpcfg2, t1
    // Flags: V1 R2 W4 X8 U16 A64 D128. Pointer = V only.
    // G stage: root[0] = 1 GiB identity leaf (GPA 0..1G), U RWX A D.
    li t2, PT_GROOT
    li t1, 0xdf
    sd t1, 0(t2)
    sd x0, GX*8(t2)
    // VS stage.
    li t2, PT_VSROOT
    li t1, (PT_VSL1 >> 2) | 0x01
    sd t1, 0(t2)                  // VS root[0] -> VSL1
    li t1, (BADGPA >> 2) | 0x01
    sd t1, 8(t2)                  // VS root[1] -> GPA 2^41 + GX GiB
    li t2, PT_VSL1 + 511*8
    li t1, (PT_VSL0 >> 2) | 0x01
    sd t1, 0(t2)                  // VSL1[511] -> VSL0
    la t1, page_a
    srli t1, t1, 2
    ori t1, t1, 0xCB              // RX A D
    li t2, PT_VSL0 + 511*8
    sd t1, 0(t2)                  // VSL0[511]: VA_A -> page_a
    la t1, page_c
    srli t1, t1, 2
    ori t1, t1, 0xCB
    li t2, PT_VSL0 + 510*8
    sd t1, 0(t2)                  // VSL0[510]: VA_C -> page_c
    la t1, page_d
    srli t1, t1, 2
    ori t1, t1, 0xC7              // RW A D
    li t2, PT_VSL0 + 509*8
    sd t1, 0(t2)                  // VSL0[509]: VA_D -> page_d
    // Phase-1/3 decoys: fake VS root[0] at SPA 0xA002_0000 is a
    // 1 GiB VS leaf (VA 0..1G -> GPA 0..1G, RX A D), so VA_C runs
    // the code at SPA WRONG_CODE and VA_D reads SPA WRONG_DATA.
    li t2, FAKE_VSROOT
    li t1, 0xCB
    sd t1, 0(t2)
    li t2, WRONG_CODE
    li t1, 0x0BA00513             // addi a0, x0, 0xBA
    sw t1, 0(t2)
    li t1, 0x00451513             // slli a0, a0, 4   (a0 = 0xBA0)
    sw t1, 4(t2)
    li t1, 0x00d56513             // ori  a0, a0, 0xD (a0 = 0xBAD)
    sw t1, 8(t2)
    li t1, 0x00000073             // ecall
    sw t1, 12(t2)
    li t2, WRONG_DATA
    li t1, 0xBAD
    sd t1, 0(t2)
    fence.i
    // hgatp Sv39x4 (VMID 0), vsatp Sv39 (ASID 0).
    li t1, 8
    slli t1, t1, 60
    li t2, PT_GROOT >> 12
    or t2, t2, t1
    csrw hgatp, t2
    li t2, PT_VSROOT >> 12
    or t2, t2, t1
    csrw vsatp, t2
    li s2, 0                      // iteration
    li s3, 0                      // phase
    li s6, 0                      // variant
    li s5, VA_D
    j enter

// ECALL from VS (cause 10) ends one pass: a0 must hold MAGIC.
m_handler:
    csrr t1, mcause
    li t2, 10
    bne t1, t2, m_fail
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
    li t1, 0xFF                   // wrong code or data, no trap
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
    // G root[GX]: 0 in phases 0, 2; 1 GiB leaf in phases 1, 3.
    li t1, PT_GROOT + GX*8
    andi t2, s3, 1
    beqz t2, 1f
    li t2, (0x80000000 >> 2) | 0xdf   // 1 GiB leaf -> SPA 0x8000_0000
    sd t2, 0(t1)
    j 2f
1:  sd x0, 0(t1)
2:  sfence.vma
    hfence.gvma
    hfence.vvma
    li a0, 0
    li t2, 2
    bgeu s3, t2, 3f
    // Phases 0, 1: s8 = VA_C, entry k NOPs before the jump.
    li s8, VA_C
    slli t2, s6, 2
    li t1, VA_A + 0xFFC
    sub t1, t1, t2
    j 4f
    // Phases 2, 3: s8 = sled entry that runs N = 2*v NOPs.
3:  li s8, VA_A + SLED*4
    slli t2, s6, 3
    sub s8, s8, t2
    li t1, VA_A + 0xFFC
4:  csrw mepc, t1
    li t1, (3 << 11)
    csrc mstatus, t1
    li t1, (1 << 11)              // MPP = S
    csrs mstatus, t1
    li t1, 1
    slli t1, t1, 39               // MPV = 1: mret enters VS
    csrs mstatus, t1
    mret

    .balign 4096
page_a:
    .rept SLED
    nop
    .endr
    ld a0, 0(s5)
    ecall
    .skip 0x1000 - SLED*4 - 8 - 16
    nop
    nop
    nop
    jr s8                         // IF falls through into VA_B
    .balign 4096
page_c:
    li a0, MAGIC
    ecall
    .balign 4096
page_d:
    .dword MAGIC
    .balign 4096
