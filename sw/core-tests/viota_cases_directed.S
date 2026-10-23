// viota.m directed cases with hand-computed results (issue #8: vs2 is
// one mask register whatever LMUL is). Complements the random and
// sweep programs (viota_directed, viota_sweep_directed) with values
// worked out from RVV 1.0 sec. 15.8:
//   - the spec's two examples (unmasked; masked, vma=0), the masked
//     one at LMUL=4 with vs2 = v2, not aligned to the vd group;
//   - LMUL 1/2/4/8 at SEW 8..64, vs2 not LMUL-aligned (v31, v5, v3,
//     v13, v17), vl = VLMAX up to 512 (count wraps mod 2^SEW);
//   - mu (masked-off elements unchanged), ma (unchanged or all ones),
//     tu tails across the whole group, vs2 = v0 under v0.t;
//   - vl = 0 under ta/ma: no element is written (sec. 5.4);
//   - back-to-back hazards: vs2 written by the instruction just before
//     (vmset.m, vlm.v), vd read by the one just after (vmsne.vv,
//     vse8.v), vsetvli changing LMUL just before viota.m;
//   - the encodings RVV 1.0 makes illegal: vd not aligned to LMUL,
//     v0.t with vd = v0 (LMUL 1 and a v0..v7 group at LMUL 8), vill.
// vstart != 0 (must also trap) is in viota_vstart_directed; vs2 inside
// the vd group is reserved and not tested.
// The same program runs on Spike when assembled with -DSPIKE_HTIF
// (tohost exit, linked at 0x80000000) and passes there.
// Convention: t0 = test number, exit store 0 = pass.
    .option arch, +v
    .option norvc  // norvc last: gas 13 .option arch resets it

#ifdef SPIKE_HTIF
#define EXIT_PASS li t1, 1; la t2, tohost; sd t1, 0(t2); 1: j 1b
#define EXIT_FAIL slli t1, t0, 1; ori t1, t1, 1; la t2, tohost; sd t1, 0(t2); 1: j 1b
#else
#define EXIT_PASS li t1, 0x10000000; sd x0, 0(t1); 1: j 1b
#define EXIT_FAIL li t1, 0x10000000; sd t0, 0(t1); 1: j 1b
#endif

// viota.m vd, vs2[, v0.t] as a raw word (the assembler rejects
// v0.t with vd = v0); vm = 1 unmasked, 0 masked.
#define VIOTA(vd, vs2, vm) .word (0x14 << 26) | ((vm) << 25) | ((vs2) << 20) | (0x10 << 15) | (2 << 12) | ((vd) << 7) | 0x57

.macro CLRTRAP
    la a5, tinfo
    sd x0, 0(a5)
    sd x0, 8(a5)
.endm
.macro NOTRAP
    la a5, tinfo
    ld a2, 0(a5)
    bnez a2, fail
.endm
// exactly one trap, an illegal instruction
.macro ONETRAP
    la a5, tinfo
    ld a2, 0(a5)
    li a3, 1
    bne a2, a3, fail
    ld a2, 8(a5)
    li a3, 2
    bne a2, a3, fail
.endm
// dword \off of buf must equal \val
.macro CHKD off, val
    la a1, buf
    ld a2, \off(a1)
    li a3, \val
    bne a2, a3, fail
.endm
// scalar \reg must be 0
.macro ZERO reg
    bnez \reg, fail
.endm

    .text
    .globl _start
_start:
    la t1, trap
    csrw mtvec, t1
    li t1, (3 << 13) | (3 << 9)    // mstatus.FS and .VS = Dirty
    csrs mstatus, t1

    // 1: spec example, unmasked, e8 m1 vl=8: v2 = 1 0 0 1 0 0 0 1
    // (elements 7..0) gives 2 2 2 1 1 1 1 0; tail (tu) unchanged.
    li t0, 1
    li a1, 64
    vsetvli x0, a1, e8, m1, tu, mu
    li a1, 0x5a
    vmv.v.x v4, a1
    vmv.v.i v2, 0
    li a1, 8
    vsetvli x0, a1, e8, m1, tu, mu
    li a1, 0x91
    vmv.s.x v2, a1
    CLRTRAP
    viota.m v4, v2
    NOTRAP
    la a1, buf
    vs1r.v v4, (a1)
    CHKD 0, 0x0202020101010100
    CHKD 8, 0x5a5a5a5a5a5a5a5a
    CHKD 56, 0x5a5a5a5a5a5a5a5a

    // 2: spec example, masked (vma=0) at e8 m4, vd = v4, vs2 = v2
    // (not aligned to the 4-register group). v0 = 1 1 1 0 1 0 1 1,
    // v4 = 2 3 4 5 6 7 8 9 gives 1 1 1 5 1 7 1 0; elements 8..255
    // of the group unchanged (tu).
    li t0, 2
    li a1, 256
    vsetvli x0, a1, e8, m4, tu, mu
    li a1, 0x5a
    vmv.v.x v4, a1
    li a1, 8
    vsetvli x0, a1, e8, m4, tu, mu
    la a1, ex2_v4
    vle8.v v4, (a1)
    li a1, 0xeb
    vmv.s.x v0, a1
    CLRTRAP
    viota.m v4, v2, v0.t
    NOTRAP
    la a1, buf
    vs4r.v v4, (a1)
    CHKD 0, 0x0101010501070100
    CHKD 8, 0x5a5a5a5a5a5a5a5a
    CHKD 248, 0x5a5a5a5a5a5a5a5a

    // 3: e8 m8 vl=512, vd = v8, vs2 = v31 (the last register) set by
    // vmset.m just before; every element active, so element i holds
    // i mod 256 (= vid.v at e8), compared by vmsne.vv just after.
    li t0, 3
    li a1, 512
    vsetvli a0, a1, e8, m8, tu, mu
    li a2, 512
    bne a0, a2, fail
    vid.v v16
    vmv.v.i v8, 0
    vmclr.m v31
    CLRTRAP
    vmset.m v31
    viota.m v8, v31
    vmsne.vv v1, v8, v16
    vcpop.m a0, v1
    ZERO a0
    NOTRAP
    la a1, buf
    vs1r.v v15, (a1)               // elements 448..511
    CHKD 0, 0xc7c6c5c4c3c2c1c0
    CHKD 56, 0xfffefdfcfbfaf9f8

    // 4: e16 m8 vl=256 (VLMAX), vd = v16, vs2 = v5 = 0x55..55 (even
    // elements set): element i holds ceil(i/2) = (i+1) >> 1. vsetvli
    // changes LMUL from 1 to 8 just before viota.m.
    li t0, 4
    li a1, 64
    vsetvli x0, a1, e8, m1, tu, mu
    li a1, 0x55
    vmv.v.x v5, a1
    li a1, -1
    vsetvli a0, a1, e16, m8, tu, mu
    CLRTRAP
    viota.m v16, v5
    NOTRAP
    li a2, 256
    bne a0, a2, fail
    vid.v v24
    vadd.vi v24, v24, 1
    vsrl.vi v24, v24, 1
    vmsne.vv v1, v16, v24
    vcpop.m a0, v1
    ZERO a0
    la a1, buf
    vs1r.v v23, (a1)               // elements 224..255: 112..128
    CHKD 0, 0x0072007100710070
    CHKD 56, 0x0080007f007f007e

    // 5: e32 m2, vl=20, masked, ta ma: v0 = 0xaa..aa (odd elements
    // active), vs2 = v3 all ones, vd = v4 preset to P. An active
    // (odd) element i holds the number of active elements below it,
    // i >> 1; a masked-off element (even, below vl) is P or all ones.
    li t0, 5
    li a1, 64
    vsetvli x0, a1, e8, m1, tu, mu
    li a1, 0xaa
    vmv.v.x v0, a1
    vmv.v.i v3, -1
    li a1, 32
    vsetvli x0, a1, e32, m2, tu, mu
    li a6, 0x12345678
    vmv.v.x v4, a6
    li a1, 20
    vsetvli a0, a1, e32, m2, ta, ma
    CLRTRAP
    viota.m v4, v3, v0.t
    NOTRAP
    vid.v v8
    vsrl.vi v8, v8, 1
    vmsne.vv v1, v4, v8, v0.t
    vcpop.m a0, v1, v0.t
    ZERO a0
    vmseq.vx v2, v4, a6
    li a1, -1
    vmseq.vx v10, v4, a1
    vmor.mm v2, v2, v10
    vmnor.mm v2, v2, v0            // masked off and neither P nor ones
    vcpop.m a0, v2
    ZERO a0

    // 6: e64 m4, vl=8, vd = v20, vs2 = v0 under v0.t (mu, tu):
    // v0 = 0x96 (elements 1, 2, 4, 7 active) gives 0 1 2 3 there;
    // elements 0, 3, 5, 6 and the tail 8..31 keep Q.
    li t0, 6
    li a1, 32
    vsetvli x0, a1, e64, m4, tu, mu
    li a1, 0x0123456789abcdef
    vmv.v.x v20, a1
    li a1, 64
    vsetvli x0, a1, e8, m1, tu, mu
    vmv.v.i v0, 0
    li a1, 0x96
    vmv.s.x v0, a1
    li a1, 8
    vsetvli x0, a1, e64, m4, tu, mu
    CLRTRAP
    viota.m v20, v0, v0.t
    NOTRAP
    la a1, buf
    vs4r.v v20, (a1)
    CHKD 0, 0x0123456789abcdef
    CHKD 8, 0
    CHKD 16, 1
    CHKD 24, 0x0123456789abcdef
    CHKD 32, 2
    CHKD 40, 0x0123456789abcdef
    CHKD 48, 0x0123456789abcdef
    CHKD 56, 3
    CHKD 64, 0x0123456789abcdef
    CHKD 248, 0x0123456789abcdef

    // 7: vl = 0 at e8 m8 with ta ma: no element is written, not even
    // agnostic tail elements (RVV 1.0 sec. 5.4).
    li t0, 7
    li a1, 512
    vsetvli x0, a1, e8, m8, tu, mu
    li a6, 0x5a
    vmv.v.x v8, a6                 // (v3 is still all ones, test 5)
    vsetivli a0, 0, e8, m8, ta, ma
    ZERO a0
    CLRTRAP
    viota.m v8, v3
    NOTRAP
    li a1, 512
    vsetvli x0, a1, e8, m8, tu, mu
    vmsne.vx v1, v8, a6
    vcpop.m a0, v1
    ZERO a0

    // 8: e8 m4 vl=256, vs2 = v13 (not aligned) loaded by vlm.v just
    // before (all ones over zeros), vd = v4 stored by vse8.v just
    // after: element i = i.
    li t0, 8
    li a1, 64
    vsetvli x0, a1, e8, m1, tu, mu
    vmv.v.i v13, 0
    li a1, 256
    vsetvli x0, a1, e8, m4, tu, mu
    vmv.v.i v4, 0
    la a1, ones
    la a2, buf
    CLRTRAP
    vlm.v v13, (a1)
    viota.m v4, v13
    vse8.v v4, (a2)
    NOTRAP
    CHKD 0, 0x0706050403020100
    CHKD 96, 0x6766656463626160
    CHKD 248, 0xfffefdfcfbfaf9f8

    // 9: vsetvli to LMUL 8 just before: viota.m v9, v3 has vd not
    // aligned to the group: illegal, v9 unchanged.
    li t0, 9
    li a1, 64
    vsetvli x0, a1, e8, m1, tu, mu
    li a6, 0x33
    vmv.v.x v9, a6
    li a1, -1
    CLRTRAP
    vsetvli x0, a1, e8, m8, tu, mu
    VIOTA(9, 3, 1)
    ONETRAP
    li a1, 64
    vsetvli x0, a1, e8, m1, tu, mu
    vmsne.vx v1, v9, a6
    vcpop.m a0, v1
    ZERO a0

    // 10: vsetvli to LMUL 8 just before, vs2 = v17 (odd, outside the
    // v8 group): legal. Then vsetvli to LMUL 2 and viota.m v2, v1:
    // legal (v1 is outside v2..v3).
    li t0, 10
    li a1, -1
    CLRTRAP
    vsetvli x0, a1, e8, m8, tu, mu
    VIOTA(8, 17, 1)
    vsetvli x0, a1, e16, m2, tu, mu
    VIOTA(2, 1, 1)
    NOTRAP

    // 11: v0.t with vd = v0 at LMUL 1: illegal, v0 unchanged.
    li t0, 11
    li a1, 64
    vsetvli x0, a1, e8, m1, tu, mu
    li a6, 0x6c
    vmv.v.x v0, a6
    CLRTRAP
    VIOTA(0, 3, 0)
    ONETRAP
    vmsne.vx v1, v0, a6
    vcpop.m a0, v1
    ZERO a0

    // 12: v0.t with the vd group v0..v7 at LMUL 8 (vs2 = v9 outside
    // it): illegal. vd = v8 with vs2 = v0 under v0.t: legal.
    li t0, 12
    li a1, 512
    vsetvli x0, a1, e8, m8, tu, mu
    CLRTRAP
    VIOTA(0, 9, 0)
    ONETRAP
    CLRTRAP
    VIOTA(8, 0, 0)
    NOTRAP

    // 13: vtype.vill set (reserved vlmul 4): illegal.
    li t0, 13
    li a1, 4
    li a2, 16
    vsetvl a0, a2, a1
    CLRTRAP
    VIOTA(8, 3, 1)
    ONETRAP
    csrr a0, vtype
    srli a0, a0, 63
    beqz a0, fail

    EXIT_PASS
fail:
    EXIT_FAIL

    // Count traps, record mcause, skip the 4-byte instruction.
    .align 2
trap:
    la t5, tinfo
    ld t6, 0(t5)
    addi t6, t6, 1
    sd t6, 0(t5)
    csrr t6, mcause
    sd t6, 8(t5)
    csrr t6, mepc
    addi t6, t6, 4
    csrw mepc, t6
    mret

    .data
#ifdef SPIKE_HTIF
    .align 6
    .globl tohost
tohost: .dword 0
    .align 6
    .globl fromhost
fromhost: .dword 0
#endif
    .align 3
tinfo: .dword 0, 0                  // trap count, last mcause
ex2_v4: .byte 9, 8, 7, 6, 5, 4, 3, 2 // spec example v4, element 0 first
    .align 3
ones: .fill 64, 1, 0xff
    .align 6
buf: .zero 512
