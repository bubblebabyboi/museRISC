// Vector directed test (issue #23, stages 8a/8b): vsetvl
// family and VLMAX/vill semantics, mstatus.VS gating, vmv
// moves, the first integer ALU classes, and unit-stride
// vector loads/stores including EEW != SEW, masked loads,
// and a mid-instruction PMP fault that commits the elements
// before it and sets vstart to the faulting index.
// Convention: t0 = test number, exit store 0 = pass.
    .option arch, +v
    .option norvc  // norvc last: gas 13 .option arch resets it
    .text
    .globl _start
_start:
    la sp, stack_top
    la t1, handler_m
    csrw mtvec, t1
    la t1, trap_stack_top
    addi t1, t1, -64
    csrw mscratch, t1

    // 1: vector op with VS=Off traps as illegal (cause 2).
    li t0, 1
    vsetvli a0, a1, e64, m1, ta, ma
    la a1, trap_cause
    ld a1, 0(a1)
    li a2, 2
    bne a1, a2, fail

    // Enable vector state (VS=Initial).
    li t1, (1 << 9)
    csrs mstatus, t1

    // 2: vsetvli computes VLMAX-capped vl: e64/m8 -> 64.
    li t0, 2
    li a1, 100
    vsetvli a0, a1, e64, m8, ta, ma
    li a2, 64
    bne a0, a2, fail
    csrr a1, vl
    bne a1, a2, fail
    csrr a1, vtype
    li a2, 0xdb                    // vma|vta|e64|m8
    bne a1, a2, fail
    csrr a1, vlenb
    li a2, 64
    bne a1, a2, fail

    // 3: vmv.v.x broadcast and vmv.x.s readback (e64).
    li t0, 3
    li a1, 0x1122334455667788
    vmv.v.x v8, a1                 // LMUL=8 group base
    vmv.x.s a0, v8
    bne a0, a1, fail

    // 4: e32/m2 integer ALU: 5 + 7 = 12, 5 - 2 = 3, shifts.
    li t0, 4
    li a1, 10
    vsetvli a0, a1, e32, m2, ta, ma
    li a2, 10
    bne a0, a2, fail
    vmv.v.i v4, 5
    vmv.v.i v6, 7
    vadd.vv v8, v4, v6
    vmv.x.s a0, v8
    li a2, 12
    bne a0, a2, fail
    li a1, 2
    vsub.vx v8, v4, a1
    vmv.x.s a0, v8
    li a2, 3
    bne a0, a2, fail
    vrsub.vi v8, v4, 9             // 9 - 5
    vmv.x.s a0, v8
    li a2, 4
    bne a0, a2, fail
    vsll.vi v8, v4, 3              // 5 << 3
    vmv.x.s a0, v8
    li a2, 40
    bne a0, a2, fail
    vmv.v.i v4, -16
    vsra.vi v8, v4, 2              // -16 >> 2 (arithmetic)
    vmv.x.s a0, v8
    li a2, -4
    bne a0, a2, fail
    vsrl.vi v8, v4, 2              // logical: 0x3ffffffc
    vmv.x.s a0, v8
    li a2, 0x3ffffffc
    bne a0, a2, fail

    // 5: vmv.s.x writes element 0 only; vmv.v.v copies.
    li t0, 5
    li a1, 64
    vsetvli a0, a1, e64, m1, ta, ma
    vmv.v.i v2, 7
    li a1, 99
    vmv.s.x v2, a1
    vmv.x.s a0, v2
    bne a0, a1, fail
    vmv.v.v v4, v2
    vmv.x.s a0, v4
    bne a0, a1, fail

    // 6: masked-off element 0 (v0 = 0, mu) keeps old vd.
    li t0, 6
    li a1, 8
    vsetvli a0, a1, e8, m1, ta, ma
    vmv.v.i v0, 0                  // all mask bits clear
    li a1, 4
    vsetvli a0, a1, e64, m1, tu, mu
    vmv.v.i v2, 11
    vmv.v.i v4, 3
    vadd.vv v2, v2, v4, v0.t       // masked off: stays 11
    vmv.x.s a0, v2
    li a2, 11
    bne a0, a2, fail

    // 7: vsetivli and fractional LMUL VLMAX (e64/mf2 -> 4).
    li t0, 7
    vsetivli a0, 7, e16, m1, ta, ma
    li a2, 7
    bne a0, a2, fail
    li a1, 100
    vsetvli a0, a1, e64, mf2, ta, ma
    li a2, 4
    bne a0, a2, fail

    // 8: illegal vtype via vsetvl sets vill and vl=0; a
    // following vector op traps; a valid vsetvli recovers.
    li t0, 8
    li a1, 10
    li a2, (4 << 3)                // vsew=4 -> SEW 128 > ELEN
    vsetvl a0, a1, a2
    bnez a0, fail
    csrr a1, vtype
    bgez a1, fail                  // vill is bit 63
    la a1, trap_cause
    sd x0, 0(a1)
    vadd.vv v2, v2, v2             // traps: vill
    la a1, trap_cause
    ld a1, 0(a1)
    li a2, 2
    bne a1, a2, fail
    li a1, 4
    vsetvli a0, a1, e64, m1, ta, ma
    li a2, 4
    bne a0, a2, fail
    vmv.v.i v2, 6
    vmv.x.s a0, v2
    li a2, 6
    bne a0, a2, fail

    // 9: unit-stride e64 load/store round trip, checked
    // element-wise with scalar loads.
    li t0, 9
    li a1, 4
    vsetvli a0, a1, e64, m1, ta, ma
    la a1, vec_buf
    vle64.v v2, (a1)
    vmv.x.s a0, v2
    li a2, 0x0102030405060708
    bne a0, a2, fail
    vadd.vi v2, v2, 1
    la a1, vec_out
    vse64.v v2, (a1)
    la a1, vec_out
    ld a0, 8(a1)
    li a2, 0x1112131415161719
    bne a0, a2, fail
    ld a0, 24(a1)
    li a2, 0x3132333435363739
    bne a0, a2, fail

    // 10: EEW < SEW load (e32 data under e64 vtype packs
    // pairs of words into 64-bit elements).
    li t0, 10
    li a1, 4
    vsetvli a0, a1, e64, m1, ta, ma
    la a1, vec_buf
    vle32.v v2, (a1)
    vmv.x.s a0, v2                 // buf words 0,1 packed LE
    li a2, 0x0102030405060708
    bne a0, a2, fail

    // 11: masked load (mask bits 0 and 2) preserves the
    // masked-off elements of the old destination (mu).
    li t0, 11
    li a1, 4
    vsetvli a0, a1, e64, m1, tu, mu
    vmv.v.i v2, -2                 // old vd = all -2
    li a1, 5                       // mask bits 0 and 2
    vmv.v.x v0, a1
    la a1, vec_buf
    vle64.v v2, (a1), v0.t
    la a1, vec_out
    vse64.v v2, (a1)
    la a1, vec_out
    ld a0, 0(a1)
    li a2, 0x0102030405060708
    bne a0, a2, fail
    ld a0, 8(a1)
    li a2, -2
    bne a0, a2, fail
    ld a0, 16(a1)
    li a2, 0x2122232425262728
    bne a0, a2, fail

    // 13: multiply + divide-by-zero (stage 8c classes).
    li t0, 13
    li a1, 4
    vsetvli a0, a1, e32, m1, ta, ma
    la a1, vec_buf
    vle32.v v2, (a1)               // els: 05060708 01020304 ...
    li a1, 3
    vmul.vx v2, v2, a1
    la a1, vec_out
    vse32.v v2, (a1)
    la a1, vec_out
    lw a0, 4(a1)
    li a2, 0x0306090c
    bne a0, a2, fail
    vdivu.vx v4, v2, x0            // divide by zero -> all ones
    vmv.x.s a0, v4
    li a2, -1
    bne a0, a2, fail

    // 14: compare-generated mask drives a masked add.
    li t0, 14
    li a1, 4
    vsetvli a0, a1, e32, m1, tu, mu
    la a1, vec_buf
    vle32.v v2, (a1)
    li a1, 0x10000000
    vmsltu.vx v0, v2, a1           // bits: el0,el1 set
    vadd.vi v2, v2, 1, v0.t
    la a1, vec_out
    vse32.v v2, (a1)
    la a1, vec_out
    lw a0, 0(a1)
    li a2, 0x05060709
    bne a0, a2, fail
    lw a0, 8(a1)                   // masked-off el2 unchanged
    li a2, 0x15161718
    bne a0, a2, fail

    // 15: widening add e16 -> e32, stored via EEW=32.
    li t0, 15
    li a1, 4
    vsetvli a0, a1, e16, m1, ta, ma
    la a1, vec_buf
    vle16.v v2, (a1)               // el0 = 0x0708
    li a1, -1
    vwadd.vx v4, v2, a1            // el0 = 0x707
    la a1, vec_out
    vse32.v v4, (a1)
    la a1, vec_out
    lw a0, 0(a1)
    li a2, 0x707
    bne a0, a2, fail

    // 16: reduction sum.
    li t0, 16
    li a1, 4
    vsetvli a0, a1, e32, m1, ta, ma
    la a1, vec_buf
    vle32.v v2, (a1)
    vmv.v.i v4, 0
    vredsum.vs v6, v2, v4
    vmv.x.s a0, v6
    li a2, 0x2c303438
    bne a0, a2, fail

    // 17: vid + slide1up + gather-immediate.
    li t0, 17
    vid.v v2
    li a1, 99
    vslide1up.vx v2, v2, a1        // 99, 0, 1, 2
    vmv.x.s a0, v2
    li a2, 99
    bne a0, a2, fail
    vrgather.vi v4, v2, 2          // every element = v2[2] = 1
    vmv.x.s a0, v4
    li a2, 1
    bne a0, a2, fail

    // 18: saturating add sets vxsat.
    li t0, 18
    li a1, 4
    vsetvli a0, a1, e8, m1, ta, ma
    csrw vxsat, x0
    li a1, 100
    vmv.v.x v2, a1
    vsadd.vx v2, v2, a1            // 200 -> 127, saturates
    csrr a0, vxsat
    li a2, 1
    bne a0, a2, fail
    vmv.x.s a0, v2
    li a2, 127
    bne a0, a2, fail

    // 19: narrowing clip e64 -> e32 saturates.
    li t0, 19
    la a1, vec_out
    li a2, 0x100000005
    sd a2, 0(a1)
    li a2, -5
    sd a2, 8(a1)
    csrw vxsat, x0
    li a1, 2
    vsetvli a0, a1, e32, m1, ta, ma
    la a1, vec_out
    vle64.v v4, (a1)               // EMUL=2 group v4-v5
    vnclip.wi v2, v4, 0
    vmv.x.s a0, v2
    li a2, 0x7fffffff
    bne a0, a2, fail
    csrr a0, vxsat
    li a2, 1
    bne a0, a2, fail

    // 20: whole-register move ignores vtype (vill set).
    li t0, 20
    li a1, 4
    vsetvli a0, a1, e32, m1, ta, ma
    li a1, 77
    vmv.v.x v4, a1
    li a2, 0x100                   // reserved vtype bit -> vill
    li a1, 4
    vsetvl a0, a1, a2
    csrr a0, vtype
    bgez a0, fail                  // vill must read back set
    vmv1r.v v6, v4
    li a1, 1
    vsetvli a0, a1, e32, m1, ta, ma
    vmv.x.s a0, v6
    li a2, 77
    bne a0, a2, fail

    // 21: strided load/store (stride 8 over e32 data).
    li t0, 21
    li a1, 4
    vsetvli a0, a1, e32, m1, ta, ma
    la a1, vec_buf
    li a2, 8
    vlse32.v v2, (a1), a2          // low words of each dword
    la a1, vec_out
    vse32.v v2, (a1)
    la a1, vec_out
    lw a0, 8(a1)
    li a2, 0x25262728
    bne a0, a2, fail
    vid.v v2
    la a1, vec_out
    li a2, 8
    vsse32.v v2, (a1), a2          // out32[0,2,4,6] = 0,1,2,3
    la a1, vec_out
    lw a0, 16(a1)
    li a2, 2
    bne a0, a2, fail

    // 22: indexed load/store (byte offsets 12,8,4,0).
    li t0, 22
    la a1, vec_idx
    vle32.v v4, (a1)
    la a1, vec_buf
    vluxei32.v v2, (a1), v4
    vmv.x.s a0, v2                 // buf32[3]
    li a2, 0x11121314
    bne a0, a2, fail
    la a1, vec_out
    vsuxei32.v v2, (a1), v4        // scatter back reversed
    la a1, vec_out
    lw a0, 0(a1)                   // <- v2 el3 = buf32[0]
    li a2, 0x05060708
    bne a0, a2, fail

    // 23: whole-register load/store under vill.
    li t0, 23
    li a2, 0x100
    li a1, 4
    vsetvl a0, a1, a2              // vill = 1
    la a1, vec_buf
    vl1re64.v v2, (a1)
    la a1, vec_out
    vs1r.v v2, (a1)
    la a1, vec_out
    ld a0, 8(a1)
    li a2, 0x1112131415161718
    bne a0, a2, fail

    // 24: segment load/store (2 fields, e32).
    li t0, 24
    li a1, 2
    vsetvli a0, a1, e32, m1, ta, ma
    la a1, vec_buf
    vlseg2e32.v v2, (a1)           // v2=f0 {05060708,15161718}
                                    // v3=f1 {01020304,11121314}
    vmv.x.s a0, v3
    li a2, 0x01020304
    bne a0, a2, fail
    la a1, vec_out
    vsseg2e32.v v2, (a1)
    la a1, vec_out
    lw a0, 8(a1)                   // interleaved word 2 = f0e1
    li a2, 0x15161718
    bne a0, a2, fail

    // 25: viota.m reads one mask register (vs2) whatever LMUL is:
    // v5 under LMUL=2 is legal (riscv-dv regression, issue #8:
    // the core raised an illegal-instruction exception).
    li t0, 25
    la a1, trap_cause
    sd x0, 0(a1)
    li a1, 8
    vsetvli a0, a1, e32, m2, ta, ma
    li a1, 0x5a                    // mask bits 1,3,4,6
    vmv.s.x v5, a1
    viota.m v8, v5                 // {0,0,1,1,2,3,3,4}
    la a1, trap_cause
    ld a1, 0(a1)
    bnez a1, fail
    vslidedown.vi v12, v8, 7
    vmv.x.s a0, v12
    li a2, 4
    bne a0, a2, fail

    // 99: mid-instruction fault. PMP (locked, so last test):
    // allow [0, buf+16), deny [buf+16, buf+64). The e64 load
    // commits elements 0-1, faults at element 2, vstart=2.
    li t0, 99
    la a1, vec_buf
    addi a2, a1, 16
    srli a2, a2, 2
    csrw pmpaddr0, a2
    la a1, vec_buf
    addi a2, a1, 64
    srli a2, a2, 2
    csrw pmpaddr1, a2
    li a2, 0x888f                  // e0 TOR L RWX, e1 TOR L ---
    csrw pmpcfg0, a2
    li a1, 4
    vsetvli a0, a1, e64, m1, ta, ma
    vmv.v.i v2, 0
    la a1, trap_cause
    sd x0, 0(a1)
    la a1, vec_buf
    vle64.v v2, (a1)               // faults at element 2
    la a1, trap_cause
    ld a1, 0(a1)
    li a2, 5
    bne a1, a2, fail
    csrr a1, vstart
    li a2, 2
    bne a1, a2, fail
    vmv.x.s a0, v2                 // element 0 committed
    li a2, 0x0102030405060708
    bne a0, a2, fail
    // Fault-only-first over the same split buffer: loads
    // elements 0-1, trims vl to 2, and does not trap.
    li a1, 4
    vsetvli a0, a1, e64, m1, ta, ma
    la a1, trap_cause
    sd x0, 0(a1)
    la a1, vec_buf
    vle64ff.v v2, (a1)
    la a1, trap_cause
    ld a1, 0(a1)
    bnez a1, fail
    csrr a0, vl
    li a2, 2
    bne a0, a2, fail
    // But a fault on the first accessed element traps.
    li a1, 4
    vsetvli a0, a1, e64, m1, ta, ma
    la a1, trap_cause
    sd x0, 0(a1)
    la a1, vec_buf
    addi a1, a1, 16
    vle64ff.v v2, (a1)
    la a1, trap_cause
    ld a1, 0(a1)
    li a2, 5
    bne a1, a2, fail
    j pass

handler_m:
    csrrw sp, mscratch, sp
    sd t1, 0(sp)
    sd t2, 8(sp)
    la t2, trap_cause
    csrr t1, mcause
    sd t1, 0(t2)
    csrr t1, mepc
    addi t1, t1, 4
    csrw mepc, t1
    ld t1, 0(sp)
    ld t2, 8(sp)
    csrrw sp, mscratch, sp
    mret

pass:
    li t1, 0x10000000
    sd x0, 0(t1)
1:  j 1b
fail:
    li t1, 0x10000000
    sd t0, 0(t1)
1:  j 1b

    .data
    .align 3
trap_cause: .dword 0
    .align 3
vec_out:    .skip 512
    .align 3
vec_buf:    .dword 0x0102030405060708, 0x1112131415161718
            .dword 0x2122232425262728, 0x3132333435363738
            .skip 480
vec_idx:    .word 12, 8, 4, 0
            .skip 496
    .skip 512
stack_top:
    .skip 512
trap_stack_top:
