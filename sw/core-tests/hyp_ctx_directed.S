// Two-stage translation context back to back with HLV/HSV (#53
// review): every write that changes an HLV's translation context
// (hstatus.SPVP, vsstatus.SUM/MXR, HS MXR, vsatp ASID, hgatp VMID)
// is immediately followed by the HLV/HSV it affects, plus HLVX,
// GPA-width guest faults (stval/htval/GVA), HSV A/D through the
// G stage, and M-mode MPRV+MPV loads. HS runs Bare; faults are
// delegated to HS, whose handler records scause/stval/htval/hstatus
// and skips. With FPGA_TIMING the D-TLB lookup happens in EX with
// EX's context. t0 = test number; exit store 0 = pass.
    .option arch, +h
    .option norvc
    .text
    .globl _start
.equ EXIT, 0x10000000
.equ SPVP, (1 << 8)
.equ SUM,  (1 << 18)
.equ MXR,  (1 << 19)
.equ MPRV, (1 << 17)
.equ MPV,  (1 << 39)
// guest VAs (VS tables), GPA == host PA below 2M
.equ VA_S,  0x400000            // -> gp_s  RW       (0x5001)
.equ VA_U,  0x401000            // -> gp_u  RW U     (0x5002)
.equ VA_X,  0x402000            // -> gp_x  X only   (0x5003)
.equ VA_GX, 0x403000            // -> GPA 0x200000 (G stage: X only, 0x5004)
.equ VA_V,  0x404000            // -> GPA 0x201000 (G: VMID1 hp_a 0x5005, VMID2 hp_b 0x5006)
.equ VA_W,  0x405000            // -> GPA 2^41 (G-stage width fault)
.equ VA_D,  0x406000            // -> gp_d  RW A, D=0
.equ GPA_GX, 0x200000
.equ GPA_V,  0x201000
.equ GPA_BIG, (1 << 41)

.macro PTE dst, pa, flags       // dst = (pa >> 2) | flags (pa in a register)
    srli \dst, \pa, 2
    ori \dst, \dst, \flags
.endm
.macro CHK_CAUSE c
    la t2, h_cause
    ld t1, 0(t2)
    li t3, \c
    bne t1, t3, fail
    sd x0, 0(t2)
.endm
.macro CHK_NOTRAP
    la t2, h_cause
    ld t1, 0(t2)
    bnez t1, fail
.endm
.macro CHK reg, v
    li t3, \v
    bne \reg, t3, fail
.endm

_start:
    la sp, stack_top
    la t1, trap_stack_top
    csrw mscratch, t1
    csrw sscratch, t1
    la t1, handler_m
    csrw mtvec, t1
    la t1, handler_hs
    csrw stvec, t1
    li t1, -1
    csrw pmpaddr15, t1
    li t1, 0x1f
    slli t1, t1, 56
    csrw pmpcfg2, t1
    // ---- G stage, VMID 1: GPA 0..2M identity (U RWX), GPA 2M.. 4K
    la a0, g_root
    la a1, g_l1
    PTE a2, a1, 0x01
    sd a2, 0(a0)
    li a2, 0xdf
    sd a2, 0(a1)                // 2M identity leaf
    la a3, g_l0
    PTE a2, a3, 0x01
    sd a2, 8(a1)                // GPA 0x200000.. -> g_l0
    la a4, hp_x
    PTE a2, a4, 0xd9            // V X U A D: execute-only G page
    sd a2, 0(a3)
    la a4, hp_a
    PTE a2, a4, 0xd7            // V RW U A D
    sd a2, 8(a3)
    // ---- G stage, VMID 2: same, GPA_V -> hp_b
    la a0, g_root2
    la a1, g_l1_2
    PTE a2, a1, 0x01
    sd a2, 0(a0)
    li a2, 0xdf
    sd a2, 0(a1)
    la a3, g_l0_2
    PTE a2, a3, 0x01
    sd a2, 8(a1)
    la a4, hp_x
    PTE a2, a4, 0xd9
    sd a2, 0(a3)
    la a4, hp_b
    PTE a2, a4, 0xd7
    sd a2, 8(a3)
    // ---- VS tables, ASID 1
    la a0, vs_root
    la a1, vs_l1
    PTE a2, a1, 0x01
    sd a2, 0(a0)
    li a2, 0xcf
    sd a2, 0(a1)                // VA 0..2M identity (VS RWX)
    la a3, vs_l0
    PTE a2, a3, 0x01
    sd a2, 16(a1)               // VA 0x400000.. -> vs_l0
    la a4, gp_s
    PTE a2, a4, 0xc7
    sd a2, 0(a3)
    la a4, gp_u
    PTE a2, a4, 0xd7
    sd a2, 8(a3)
    la a4, gp_x
    PTE a2, a4, 0xc9
    sd a2, 16(a3)
    li a4, GPA_GX
    PTE a2, a4, 0xc7
    sd a2, 24(a3)
    li a4, GPA_V
    PTE a2, a4, 0xc7
    sd a2, 32(a3)
    li a4, GPA_BIG
    PTE a2, a4, 0xc7
    sd a2, 40(a3)
    la a4, gp_d
    PTE a2, a4, 0x47            // V RW A, D = 0
    sd a2, 48(a3)
    // ---- VS tables, ASID 2: VA_S -> gp_s2
    la a0, vs_root2
    la a1, vs_l1_2
    PTE a2, a1, 0x01
    sd a2, 0(a0)
    li a2, 0xcf
    sd a2, 0(a1)
    la a3, vs_l0_2
    PTE a2, a3, 0x01
    sd a2, 16(a1)
    la a4, gp_s2
    PTE a2, a4, 0xc7
    sd a2, 0(a3)
    // payloads
    li a2, 0x5001
    la a4, gp_s
    sd a2, 0(a4)
    li a2, 0x5002
    la a4, gp_u
    sd a2, 0(a4)
    li a2, 0x5003
    la a4, gp_x
    sd a2, 0(a4)
    li a2, 0x5004
    la a4, hp_x
    sd a2, 0(a4)
    li a2, 0x5005
    la a4, hp_a
    sd a2, 0(a4)
    li a2, 0x5006
    la a4, hp_b
    sd a2, 0(a4)
    li a2, 0x6001
    la a4, gp_s2
    sd a2, 0(a4)
    // vsatp/hgatp values
    la a0, vs_root
    srli a0, a0, 12
    li a1, (8 << 60) | (1 << 44)
    or a0, a0, a1
    la a1, vsatp1
    sd a0, 0(a1)
    la a0, vs_root2
    srli a0, a0, 12
    li a1, (8 << 60) | (2 << 44)
    or a0, a0, a1
    la a1, vsatp2
    sd a0, 0(a1)
    la a0, g_root
    srli a0, a0, 12
    li a1, (8 << 60) | (1 << 44)
    or a0, a0, a1
    la a1, hgatp1
    sd a0, 0(a1)
    la a0, g_root2
    srli a0, a0, 12
    li a1, (8 << 60) | (2 << 44)
    or a0, a0, a1
    la a1, hgatp2
    sd a0, 0(a1)
    // delegate load/store page and guest-page faults to HS
    li t1, (1 << 13) | (1 << 15) | (1 << 21) | (1 << 23)
    csrw medeleg, t1
    csrw mideleg, x0
    la t1, hgatp1
    ld t1, 0(t1)
    csrw hgatp, t1
    la t1, vsatp1
    ld t1, 0(t1)
    csrw vsatp, t1
    hfence.gvma zero, zero
    la t1, hs_main
    csrw mepc, t1
    li t1, (3 << 11)
    csrc mstatus, t1
    li t1, (1 << 11)
    csrs mstatus, t1
    li t1, (1 << 7)
    csrs mie, t1                // MTIE: lower modes take M timer IRQs
    mret

hs_main:
    // 1: hstatus.SPVP adjacency (VS vs VU on a non-U page).
    li t0, 1
    li a1, VA_S
    li a4, SPVP
    csrs hstatus, a4
    hlv.d a3, (a1)
    CHK_NOTRAP
    CHK a3, 0x5001
    csrc hstatus, a4
    hlv.d a3, (a1)              // VU on a supervisor page: 13
    CHK_CAUSE 13
    la t2, h_tval
    ld t1, 0(t2)
    CHK t1, VA_S
    la t2, h_hstatus
    ld t1, 0(t2)
    srli t1, t1, 6
    andi t1, t1, 1
    CHK t1, 1                   // GVA
    csrs hstatus, a4
    li a3, 0
    hlv.d a3, (a1)              // the access before the clear
    csrc hstatus, a4
    CHK_NOTRAP
    CHK a3, 0x5001
    li a1, VA_U
    hlv.d a3, (a1)              // VU on a U page: fine
    CHK_NOTRAP
    CHK a3, 0x5002
    csrs hstatus, a4            // SPVP = VS from here on
    // 2: vsstatus.SUM adjacency (VS on a U page).
    li t0, 2
    li a5, SUM
    csrs vsstatus, a5
    hlv.d a3, (a1)
    CHK_NOTRAP
    CHK a3, 0x5002
    csrc vsstatus, a5
    hlv.d a3, (a1)
    CHK_CAUSE 13
    csrs vsstatus, a5
    li a3, 0x77
    hsv.d a3, (a1)
    csrc vsstatus, a5
    hsv.d a3, (a1)
    CHK_CAUSE 15
    csrs vsstatus, a5
    hlv.d a3, (a1)
    csrc vsstatus, a5
    CHK a3, 0x77
    // 3: vsstatus.MXR (VS-stage X-only page) and HS MXR (G-stage
    //    X-only page) adjacency; HLVX needs neither.
    li t0, 3
    li a1, VA_X
    li a5, MXR
    csrs vsstatus, a5
    hlv.w a3, (a1)
    CHK_NOTRAP
    CHK a3, 0x5003
    csrc vsstatus, a5
    hlv.w a3, (a1)
    CHK_CAUSE 13
    hlvx.wu a3, (a1)
    CHK_NOTRAP
    CHK a3, 0x5003
    li a1, VA_GX
    csrs sstatus, a5            // HS MXR: G-stage X readable
    hlv.w a3, (a1)
    CHK_NOTRAP
    CHK a3, 0x5004
    csrc sstatus, a5
    hlv.w a3, (a1)              // G-stage denial: guest page fault
    CHK_CAUSE 21
    la t2, h_htval
    ld t1, 0(t2)
    CHK t1, (GPA_GX >> 2)
    hfence.gvma zero, zero
    csrs sstatus, a5
    hlv.w a3, (a1)              // miss + two-stage walk with HS MXR
    csrc sstatus, a5
    hlv.w a5, (a1)              // TLB hit, HS MXR clear: 21
    CHK_CAUSE 21
    CHK a3, 0x5004
    // 4: vsatp ASID switch adjacency.
    li t0, 4
    li a1, VA_S
    la a6, vsatp1
    ld a6, 0(a6)
    la a7, vsatp2
    ld a7, 0(a7)
    hlv.d a3, (a1)
    CHK a3, 0x5001
    csrw vsatp, a7
    hlv.d a3, (a1)
    CHK a3, 0x6001
    csrw vsatp, a6
    hlv.d a3, (a1)
    CHK a3, 0x5001
    csrw vsatp, a7
    li a1, VA_U                 // unmapped in ASID 2
    hlv.d a3, (a1)
    CHK_CAUSE 13
    csrw vsatp, a6
    hlv.d a3, (a1)              // SUM clear again: VS on U page
    CHK_CAUSE 13
    // 5: hgatp VMID switch adjacency (same GPA, other host page).
    li t0, 5
    li a1, VA_V
    la a6, hgatp1
    ld a6, 0(a6)
    la a7, hgatp2
    ld a7, 0(a7)
    hlv.d a3, (a1)
    CHK a3, 0x5005
    csrw hgatp, a7
    hlv.d a3, (a1)
    CHK a3, 0x5006
    csrw hgatp, a6
    hlv.d a3, (a1)
    CHK a3, 0x5005
    csrw hgatp, a7
    li a2, 0x5106
    hsv.d a2, (a1)
    csrw hgatp, a6
    hlv.d a3, (a1)
    CHK a3, 0x5005
    la a4, hp_b
    ld a3, 0(a4)
    CHK a3, 0x5106
    // 6: GPA-width guest faults: VS leaf to GPA 2^41 (G-stage width
    //    fault during the walk), and VS Bare with a VA >= 2^41.
    li t0, 6
    li a1, VA_W
    hlv.d a3, (a1)
    CHK_CAUSE 21
    la t2, h_tval
    ld t1, 0(t2)
    CHK t1, VA_W
    la t2, h_htval
    ld t1, 0(t2)
    CHK t1, (GPA_BIG >> 2)
    li a3, 1
    hsv.d a3, (a1)
    CHK_CAUSE 23
    hfence.gvma zero, zero
    li a2, VA_S
    hlv.d a3, (a2)              // fill
    hlv.d a5, (a1)              // width fault right after the fill
    CHK_CAUSE 21
    CHK a3, 0x5001
    csrw vsatp, x0
    li a1, GPA_BIG + 0x10
    hlv.d a3, (a1)
    CHK_CAUSE 21
    la t2, h_htval
    ld t1, 0(t2)
    CHK t1, ((GPA_BIG + 0x10) >> 2)
    la t2, h_tval
    ld t1, 0(t2)
    CHK t1, GPA_BIG + 0x10
    la a6, vsatp1
    ld a6, 0(a6)
    csrw vsatp, a6
    // 7: HSV to a VS page with D clear: the walker sets VS A/D
    //    through the G stage.
    li t0, 7
    li a1, VA_D
    li a2, 0xD0D0
    hsv.d a2, (a1)
    hlv.d a3, (a1)
    CHK_NOTRAP
    CHK a3, 0xD0D0
    la a4, vs_l0
    ld a3, 48(a4)
    andi a3, a3, 0xC0
    CHK a3, 0xC0
    // 8: M-mode MPRV with MPV: loads translate two-stage; MPV
    //    cleared right before the next load (then HS Bare).
    li t0, 8
    la a1, m_part
    la a2, resume_m
    sd a1, 0(a2)
    ecall

m_part:
    li t0, 8
    li a1, VA_S
    li a5, (3 << 11)
    csrc mstatus, a5
    li a5, (1 << 11)            // MPP = S
    csrs mstatus, a5
    li a4, MPV
    csrs mstatus, a4
    li a5, MPRV
    csrs mstatus, a5
    ld a3, 0(a1)                // VS (two-stage)
    csrc mstatus, a4
    ld a6, 0(a1)                // HS, Bare: PA 0x400000 (0)
    csrc mstatus, a5
    CHK a3, 0x5001
    CHK a6, 0
    csrs mstatus, a4
    csrs mstatus, a5
    li a1, VA_V
    ld a3, 0(a1)
    csrw hgatp, a7              // VMID 2 right before the next load
    ld a6, 0(a1)
    csrc mstatus, a5
    csrc mstatus, a4
    CHK a3, 0x5005
    CHK a6, 0x5106

pass:
    li t1, EXIT
    sd x0, 0(t1)
1:  j 1b
fail:
    li t1, EXIT
    sd t0, 0(t1)
1:  j 1b

handler_m:
    csrrw sp, mscratch, sp      // M timer interrupts (--irq-timer-after)
    sd t1, -40(sp)              // just return; anything else falls
    csrr t1, mcause             // through to the handler below
    bgez t1, 9f
    ld t1, -40(sp)
    csrrw sp, mscratch, sp
    mret
9:  ld t1, -40(sp)
    csrrw sp, mscratch, sp
    csrr t1, mcause
    li t2, 9
    bne t1, t2, 1f
    la t2, resume_m
    ld t1, 0(t2)
    beqz t1, 1f
    csrw mepc, t1
    li t1, (3 << 11)
    csrs mstatus, t1
    mret
1:  csrr t1, mcause             // unexpected: fail with cause
    slli t1, t1, 16
    or t0, t0, t1
    li t1, EXIT
    sd t0, 0(t1)
1:  j 1b

handler_hs:
    csrrw sp, sscratch, sp
    sd t1, -8(sp)
    sd t2, -16(sp)
    csrr t1, scause
    la t2, h_cause
    sd t1, 0(t2)
    csrr t1, stval
    la t2, h_tval
    sd t1, 0(t2)
    csrr t1, htval
    la t2, h_htval
    sd t1, 0(t2)
    csrr t1, hstatus
    la t2, h_hstatus
    sd t1, 0(t2)
    csrr t1, sepc
    addi t1, t1, 4
    csrw sepc, t1
    ld t1, -8(sp)
    ld t2, -16(sp)
    csrrw sp, sscratch, sp
    sret

    .data
    .align 3
vsatp1:    .dword 0
vsatp2:    .dword 0
hgatp1:    .dword 0
hgatp2:    .dword 0
h_cause:   .dword 0
h_tval:    .dword 0
h_htval:   .dword 0
h_hstatus: .dword 0
resume_m:  .dword 0
    .skip 512
stack_top:
    .skip 512
trap_stack_top:
    .align 14
g_root:   .skip 16384
g_root2:  .skip 16384
    .align 12
g_l1:     .skip 4096
g_l0:     .skip 4096
g_l1_2:   .skip 4096
g_l0_2:   .skip 4096
vs_root:  .skip 4096
vs_l1:    .skip 4096
vs_l0:    .skip 4096
vs_root2: .skip 4096
vs_l1_2:  .skip 4096
vs_l0_2:  .skip 4096
gp_s:     .skip 4096
gp_u:     .skip 4096
gp_x:     .skip 4096
gp_d:     .skip 4096
gp_s2:    .skip 4096
hp_x:     .skip 4096
hp_a:     .skip 4096
hp_b:     .skip 4096
