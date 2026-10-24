// No-vector configuration (SIGIL_NO_VECTOR, issue #13 MPW cut-down
// core): the core behaves as RV64GC + B + K + H without V.
//   1-8:     misa.V = 0 (misa = RV64 IMABCFDHSU); mstatus.VS,
//            sstatus.VS and vsstatus.VS are read-only zero and do
//            not feed mstatus.SD; FS still does.
//   10-30:   every access to a vector CSR (vstart, vxsat, vxrm, vcsr,
//            vl, vtype, vlenb; CSRRW/RS/RC and immediate forms, reads
//            and writes) raises illegal-instruction.
//   31-95:   every vector instruction class raises illegal-
//            instruction: vsetvli/vsetivli/vsetvl, OP-V in all seven
//            funct3 classes (OPIVV, OPFVV, OPMVV, OPIVI, OPIVX,
//            OPFVF, OPMVX), and the vector loads/stores in the
//            LOAD-FP/STORE-FP space (widths 000/101/110/111):
//            unit-stride, strided, indexed (unordered/ordered),
//            whole-register, mask, fault-only-first, segment and
//            masked forms.
//   100-119: the same in S, U and VS (V=1) mode: illegal-instruction
//            (cause 2, not virtual-instruction), taken to M.
//   120-127: scalar FP loads/stores (LOAD-FP/STORE-FP widths 010/011)
//            and FP arithmetic are unaffected; they dirty FS (SD set).
// Each trapping case checks: exactly one trap, mcause 2, mepc = the
// instruction's address, mtval = its encoding, and the mode it was
// taken from (mstatus.MPP / MPV). Exit value: the first failing case
// number (0 = pass). Passes on Spike without V
// (--isa=rv64imafdcbh_..., -DSPIKE_HTIF, linked at 0x80000000).
    .option arch, +v
    .option norvc  // norvc last: gas 13 .option arch resets it

#ifdef SPIKE_HTIF
#define EXIT slli t1, s1, 1; ori t1, t1, 1; la t2, tohost; sd t1, 0(t2); 1: j 1b
#else
#define EXIT li t1, 0x10000000; sd s1, 0(t1); 1: j 1b
#endif

    .equ MPP_MASK, 3 << 11
    .equ MPV,      1 << 39

// Record case s3 as failed (first failure only) when 2f is taken.
.macro RESULT
    j 3f
2:  bnez s1, 3f
    mv s1, s3
3:
.endm

// Case \n: \insn must raise exactly one illegal-instruction trap
// (mcause 2) with mepc = its address, mtval = its 32-bit encoding,
// taken from the mode in s4 (MPP | MPV << 2).
.macro ILL n, insn:vararg
    li s3, \n
    la t3, tinfo
    sd x0, 0(t3)
    sd x0, 8(t3)
    sd x0, 16(t3)
    sd x0, 24(t3)
    sd x0, 32(t3)
99: \insn
    la t2, 99b
    la t3, tinfo
    ld t1, 0(t3)
    li t0, 1
    bne t1, t0, 2f
    ld t1, 8(t3)
    li t0, 2
    bne t1, t0, 2f
    ld t1, 16(t3)
    bne t1, t2, 2f
    lwu t0, 0(t2)
    ld t1, 24(t3)
    bne t1, t0, 2f
    ld t1, 32(t3)
    bne t1, s4, 2f
    RESULT
.endm

// Case \n: a0 must equal \val.
.macro EXPECT n, val
    li s3, \n
    li t0, \val
    bne a0, t0, 2f
    RESULT
.endm

// Leave M for mode \mpp (0 U, 1 S) with V = \mpv; s4 = the mode a
// trap from there records. ecall returns to M (the handler).
.macro ENTER mpp, mpv
    li t5, MPP_MASK | MPV
    csrc mstatus, t5
    li t5, (\mpp << 11) | (\mpv << 39)
    csrs mstatus, t5
    li s4, \mpp | (\mpv << 2)
    la t5, 98f
    csrw mepc, t5
    mret
98:
.endm
.macro LEAVE
    ecall
    li s4, 3
.endm

    .text
    .globl _start
_start:
    la t1, trap
    csrw mtvec, t1
    li s1, 0
    li s4, 3                       // traps from M: MPP = 3, MPV = 0
    csrw pmpcfg0, zero             // (Spike resets entry 0 to NAPOT RWX)
    csrw pmpcfg2, zero
    // Entry 0: NAPOT over everything, RWX (opens memory to S/U/VS).
    li t1, -1
    csrw pmpaddr0, t1
    li t1, 0x1f
    csrw pmpcfg0, t1
    csrw satp, zero
    csrw 0x680, zero               // hgatp: Bare
    csrw 0x280, zero               // vsatp: Bare
    csrw medeleg, zero
    csrw 0x602, zero               // hedeleg
    la a0, buf                     // vector LS base (never accessed)
    li a1, 16
    li a2, 8

    // ---- 1-8: misa, mstatus.VS, sstatus.VS, vsstatus.VS, SD ----
    li s3, 1
    csrr a0, misa
    EXPECT 1, 0x80000000001411AF   // MXL=2, I M A B C F D H S U (no V)
    li t1, MPP_MASK                // (MPP = M from here on)
    csrs mstatus, t1
    li t1, (3 << 13) | (3 << 9)
    csrc mstatus, t1               // FS = VS = Off
    li t1, 3 << 9
    csrs mstatus, t1               // try VS = Dirty
    csrr a0, mstatus
    srli a0, a0, 9
    andi a0, a0, 3
    EXPECT 2, 0                    // mstatus.VS reads 0
    csrr a0, mstatus
    srli a0, a0, 63
    EXPECT 3, 0                    // SD: FS and VS Off
    li t1, 3 << 9
    csrs sstatus, t1
    csrr a0, sstatus
    srli a0, a0, 9
    andi a0, a0, 3
    EXPECT 4, 0                    // sstatus.VS reads 0
    csrw sstatus, t1               // a plain write of VS = 3 as well
    csrr a0, mstatus
    srli a0, a0, 9
    andi a0, a0, 3
    EXPECT 5, 0
    csrs 0x200, t1                 // vsstatus.VS
    csrr a0, 0x200
    srli a0, a0, 9
    andi a0, a0, 3
    EXPECT 6, 0                    // vsstatus.VS reads 0
    csrr a0, 0x200
    srli a0, a0, 63
    EXPECT 7, 0                    // vsstatus.SD
    li t1, 3 << 13
    csrs mstatus, t1               // FS = Dirty: SD = 1
    csrr a0, mstatus
    srli a0, a0, 63
    EXPECT 8, 1
    // FS = Initial, VS "= Initial" (ignored) for the rest, as a
    // vector program's startup would set them.
    li t1, 3 << 13
    csrc mstatus, t1
    li t1, (1 << 13) | (1 << 9)
    csrs mstatus, t1

    // ---- 10-30: vector CSRs do not exist ----
    ILL 10, csrr a3, vstart
    ILL 11, csrw vstart, zero
    ILL 12, csrrs a3, vstart, zero
    ILL 13, csrr a3, vxsat
    ILL 14, csrwi vxsat, 1
    ILL 15, csrrci a3, vxsat, 1
    ILL 16, csrr a3, vxrm
    ILL 17, csrw vxrm, a1
    ILL 18, csrrsi a3, vxrm, 2
    ILL 19, csrr a3, vcsr
    ILL 20, csrw vcsr, a1
    ILL 21, csrrc a3, vcsr, a1
    ILL 22, csrr a3, vl
    ILL 23, csrrs a3, vl, zero
    ILL 24, csrr a3, vtype
    ILL 25, csrrc a3, vtype, zero
    ILL 26, csrr a3, vlenb
    ILL 27, csrrsi a3, vlenb, 0
    ILL 28, csrw vl, a1            // read-only and absent
    ILL 29, csrwi vtype, 0
    ILL 30, csrrw zero, vstart, a1 // write without read

    // ---- 31-45: configuration and OP-V arithmetic classes ----
    ILL 31, vsetvli a3, a1, e8, m1, ta, ma
    ILL 32, vsetvli zero, zero, e64, m8, tu, mu
    ILL 33, vsetivli a3, 4, e32, m2, tu, mu
    ILL 34, vsetvl a3, a1, a2
    ILL 35, vadd.vv v1, v2, v3                 // OPIVV
    ILL 36, vfadd.vv v1, v2, v3                // OPFVV
    ILL 37, vmul.vv v1, v2, v3                 // OPMVV
    ILL 38, vadd.vi v1, v2, 5                  // OPIVI
    ILL 39, vadd.vx v1, v2, a1                 // OPIVX
    ILL 40, vfadd.vf v1, v2, fa0               // OPFVF
    ILL 41, vmul.vx v1, v2, a1                 // OPMVX
    ILL 42, vmv.x.s a3, v2
    ILL 43, vfmv.f.s fa1, v2
    ILL 44, vmv1r.v v1, v2
    ILL 45, vredsum.vs v1, v2, v3
    ILL 46, vcpop.m a3, v2
    ILL 47, viota.m v4, v2
    ILL 48, vmseq.vv v0, v1, v2
    ILL 49, vadd.vv v1, v2, v3, v0.t           // masked
    ILL 50, vfwcvt.f.xu.v v2, v4
    ILL 51, vmv.v.i v1, 0
    ILL 52, vid.v v1
    ILL 53, vslideup.vx v1, v2, a1
    ILL 54, vrgather.vv v1, v2, v3
    ILL 55, vcompress.vm v1, v2, v0

    // ---- 60-95: vector loads/stores (LOAD-FP/STORE-FP) ----
    ILL 60, vle8.v v1, (a0)                    // width 000
    ILL 61, vle16.v v1, (a0)                   // width 101
    ILL 62, vle32.v v1, (a0)                   // width 110
    ILL 63, vle64.v v1, (a0)                   // width 111
    ILL 64, vle8.v v1, (a0), v0.t
    ILL 65, vlse32.v v1, (a0), a2              // strided
    ILL 66, vluxei16.v v1, (a0), v2            // indexed, unordered
    ILL 67, vloxei64.v v1, (a0), v2            // indexed, ordered
    ILL 68, vl1re8.v v1, (a0)                  // whole register
    ILL 69, vl8re64.v v8, (a0)
    ILL 70, vlm.v v1, (a0)                     // mask
    ILL 71, vle8ff.v v1, (a0)                  // fault-only-first
    ILL 72, vlseg2e16.v v2, (a0)               // segment
    ILL 73, vlsseg3e32.v v3, (a0), a2
    ILL 74, vluxseg2ei8.v v2, (a0), v6
    ILL 80, vse8.v v1, (a0)
    ILL 81, vse16.v v1, (a0)
    ILL 82, vse32.v v1, (a0)
    ILL 83, vse64.v v1, (a0)
    ILL 84, vse32.v v1, (a0), v0.t
    ILL 85, vsse64.v v1, (a0), a2
    ILL 86, vsuxei8.v v1, (a0), v2
    ILL 87, vsoxei32.v v1, (a0), v2
    ILL 88, vs1r.v v1, (a0)
    ILL 89, vs8r.v v8, (a0)
    ILL 90, vsm.v v1, (a0)
    ILL 91, vsseg3e8.v v3, (a0)
    ILL 92, vssseg2e64.v v2, (a0), a2
    ILL 93, vsoxseg2ei16.v v2, (a0), v6

    // ---- 100-119: S, U and VS mode ----
    ENTER 1, 0                     // S
    ILL 100, vsetvli a3, a1, e8, m1, ta, ma
    ILL 101, vle64.v v1, (a0)
    ILL 102, vse8.v v1, (a0)
    ILL 103, vadd.vx v1, v2, a1
    ILL 104, csrr a3, vl
    ILL 105, csrw vstart, zero
    LEAVE
    ENTER 0, 0                     // U
    ILL 106, vsetivli a3, 4, e32, m2, tu, mu
    ILL 107, vlse32.v v1, (a0), a2
    ILL 108, vfadd.vf v1, v2, fa0
    ILL 109, csrr a3, vlenb
    ILL 110, csrr a3, vcsr
    LEAVE
    ENTER 1, 1                     // VS (V=1)
    ILL 111, vsetvl a3, a1, a2
    ILL 112, vl1re8.v v1, (a0)
    ILL 113, vsm.v v1, (a0)
    ILL 114, vmul.vv v1, v2, v3
    ILL 115, csrr a3, vtype
    ILL 116, csrwi vxrm, 1
    LEAVE
    ENTER 0, 1                     // VU (V=1)
    ILL 117, vle8ff.v v1, (a0)
    ILL 118, vredsum.vs v1, v2, v3
    ILL 119, csrr a3, vxsat
    LEAVE

    // ---- 120-127: scalar FP is unaffected ----
    li s3, 120
    la t3, tinfo
    sd x0, 0(t3)
    la t2, fpin
    fld fa2, 0(t2)                 // LOAD-FP width 011
    flw fa3, 8(t2)                 // LOAD-FP width 010
    fadd.d fa4, fa2, fa2
    fadd.s fa5, fa3, fa3
    la t2, fpout
    fsd fa4, 0(t2)                 // STORE-FP width 011
    fsw fa5, 8(t2)                 // STORE-FP width 010
    ld a0, 0(t2)
    EXPECT 121, 0x4014000000000000 // 2.5 + 2.5 = 5.0
    lwu a0, 8(t2)
    EXPECT 122, 0x40700000         // 1.875 + 1.875 = 3.75
    la t3, tinfo
    ld a0, 0(t3)
    EXPECT 123, 0                  // no traps
    csrr a0, mstatus
    srli a0, a0, 13
    andi a0, a0, 3
    EXPECT 124, 3                  // FS = Dirty
    csrr a0, mstatus
    srli a0, a0, 9
    andi a0, a0, 3
    EXPECT 125, 0                  // VS still 0
    csrr a0, mstatus
    srli a0, a0, 63
    EXPECT 126, 1                  // SD from FS
    csrr a0, fflags
    EXPECT 127, 0                  // exact results

    EXIT

    // ecall (cause 8/9/10/11): return to M. Anything else: count it,
    // record mcause, mepc, mtval and the source mode (MPP | MPV << 2),
    // and skip the 4-byte instruction (returning to its mode).
    .align 2
trap:
    csrr t6, mcause
    addi t6, t6, -8
    li t5, 3
    bgtu t6, t5, 1f
    li t5, MPP_MASK
    csrs mstatus, t5
    li t5, MPV
    csrc mstatus, t5
    j 2f
1:  la t5, tinfo
    ld t6, 0(t5)
    addi t6, t6, 1
    sd t6, 0(t5)
    csrr t6, mcause
    sd t6, 8(t5)
    csrr t6, mepc
    sd t6, 16(t5)
    csrr t6, mtval
    sd t6, 24(t5)
    csrr t6, mstatus
    srli t4, t6, 11
    andi t4, t4, 3
    srli t6, t6, 37                // MPV (bit 39) -> bit 2
    andi t6, t6, 4
    or t6, t6, t4
    sd t6, 32(t5)
2:  csrr t6, mepc
    addi t6, t6, 4
    csrw mepc, t6
    mret

    .data
    .align 3
tinfo: .dword 0, 0, 0, 0, 0
fpin:  .dword 0x4004000000000000   // 2.5
       .word 0x3ff00000, 0          // 1.875
fpout: .dword 0, 0
buf:   .space 512
#ifdef SPIKE_HTIF
    .align 6
    .globl tohost
tohost: .dword 0
    .globl fromhost
fromhost: .dword 0
#endif
