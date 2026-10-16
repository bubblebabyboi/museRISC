// Directed M-unit pipeline tests for the multi-cycle muserisc_muldiv_mc
// (muldiv-multicycle): back-to-back dependent mul/div at every forwarding
// distance, load-use into a divide, divide results feeding stores,
// branches and jalr, every divide-by-zero / overflow form, WAW and
// x0 destinations, and interleaving with multi-cycle FP ops (fdiv.d,
// fsqrt.d) and element-serial vector ops (vector mul/div, vector loads
// holding MEM while a multiply completes). Expected values come from a
// Python RV64M model (generator kept out of tree; values are literal).
// Convention: t0 = test number, exit store 0 = pass.
    .option arch, +v
    .option norvc
    .text
    .globl _start
_start:
    li t1, (1 << 13) | (1 << 9)   // FS=Initial, VS=Initial
    csrs mstatus, t1

    // ---- 1: dependent chain, distance 1 (EX->EX forwarding every step)
    li t0, 1
    li a0, 0x123456789abcdef1
    li a1, 0x0fedcba987654321
    mul s2, a0, a1
    mulh s3, s2, a0
    mulhu s4, s3, s2
    mulhsu s5, s4, s3
    divu s6, a0, s5
    div s7, s6, a1
    rem s8, a0, s6
    remu s9, s8, a1
    mulw s10, s9, a0
    divw s11, a0, s10
    divuw a2, s11, a1
    remw a3, a0, a2
    remuw a4, a3, a1
    mul a5, a4, a4
    li t2, 0x3224a4396cc6d011
    bne s2, t2, fail
    li t2, 0x0390d3ed53f761d7
    bne s3, t2, fail
    li t2, 0x00b2cc0bbc4d37d9
    bne s4, t2, fail
    li t2, 0x00027d8aedbe0b16
    bne s5, t2, fail
    li t2, 0x000000000000074f
    bne s6, t2, fail
    li t2, 0x0000000000000000
    bne s7, t2, fail
    li t2, 0x0000000000000566
    bne s8, t2, fail
    li t2, 0x0000000000000566
    bne s9, t2, fail
    li t2, 0x00000000579b8906
    bne s10, t2, fail
    li t2, 0xffffffffffffffff
    bne s11, t2, fail
    li t2, 0x0000000000000001
    bne a2, t2, fail
    li t2, 0x0000000000000000
    bne a3, t2, fail
    li t2, 0x0000000000000000
    bne a4, t2, fail
    li t2, 0x0000000000000000
    bne a5, t2, fail

    // ---- 2: dependent chain, distances 2 and 3 (MEM/WB forwarding)
    li t0, 2
    li a0, 0xfedcba9876543210
    li a1, 0x13579bdf2468ace1
    mul s2, a0, a1
    nop
    divu s3, a0, s2
    nop
    nop
    rem s4, s2, s3
    addi s5, s4, 1
    div s6, a0, s5
    nop
    mulh s7, s6, s5
    li t2, 0xcd09a4af2822c010
    bne s2, t2, fail
    li t2, 0x0000000000000001
    bne s3, t2, fail
    li t2, 0x0000000000000000
    bne s4, t2, fail
    li t2, 0xfedcba9876543210
    bne s6, t2, fail
    li t2, 0xffffffffffffffff
    bne s7, t2, fail

    // ---- 3: load-use into divide, divide result to store, branch, jalr
    li t0, 3
    la a6, buf
    li a0, 0x7fffffffffffff01
    sd a0, 0(a6)
    li a1, 0x0000000000003ffd
    sd a1, 8(a6)
    ld s2, 0(a6)
    ld s3, 8(a6)
    divu s4, s2, s3
    sd s4, 16(a6)
    remu s5, s2, s3
    sd s5, 24(a6)
    ld s6, 16(a6)
    ld s7, 24(a6)
    li t2, 0x0002001801200d80
    bne s6, t2, fail
    li t2, 0x0000000000002781
    bne s7, t2, fail
    div s8, s2, s3
    li t2, 0x0002001801200d80
    bne s8, t2, fail
    li a2, 0x0000000000000003
    divu s9, s2, s2
    slli s9, s9, 3
    la s10, 3f
    add s10, s10, s9
    addi s10, s10, -8
    jalr x0, 0(s10)
3:  j 4f
    j fail
4:

    // ---- 4: divide by zero and signed overflow, every form, back-to-back
    li t0, 4
    li a0, 0x8000000000000000
    li a1, 0x0000000000000000
    li a2, 0xffffffffffffffff
    li a3, 0xffffffff80000000
    li a4, 0x0123456789abcdef
    div s2, a4, a1
    divu s3, a4, a1
    rem s4, a4, a1
    remu s5, a4, a1
    divw s6, a4, a1
    divuw s7, a4, a1
    remw s8, a4, a1
    remuw s9, a4, a1
    div s10, a0, a2
    rem s11, a0, a2
    divw a5, a3, a2
    remw a6, a3, a2
    divu a7, a0, a2
    remu t3, a0, a2
    divw t4, a0, a2
    remuw t5, a3, a2
    li t2, 0xffffffffffffffff
    bne s2, t2, fail
    li t2, 0xffffffffffffffff
    bne s3, t2, fail
    li t2, 0x0123456789abcdef
    bne s4, t2, fail
    li t2, 0x0123456789abcdef
    bne s5, t2, fail
    li t2, 0xffffffffffffffff
    bne s6, t2, fail
    li t2, 0xffffffffffffffff
    bne s7, t2, fail
    li t2, 0xffffffff89abcdef
    bne s8, t2, fail
    li t2, 0xffffffff89abcdef
    bne s9, t2, fail
    li t2, 0x8000000000000000
    bne s10, t2, fail
    li t2, 0x0000000000000000
    bne s11, t2, fail
    li t2, 0xffffffff80000000
    bne a5, t2, fail
    li t2, 0x0000000000000000
    bne a6, t2, fail
    li t2, 0x0000000000000000
    bne a7, t2, fail
    li t2, 0x8000000000000000
    bne t3, t2, fail
    li t2, 0x0000000000000000
    bne t4, t2, fail
    li t2, 0xffffffff80000000
    bne t5, t2, fail
    divu s2, a4, a1
    divu s3, s2, a4
    rem s4, s3, a1
    li t2, 0xffffffffffffffff
    bne s2, t2, fail
    li t2, 0x00000000000000e1
    bne s3, t2, fail
    li t2, 0x00000000000000e1
    bne s4, t2, fail

    // ---- 5: WAW on one rd and x0 destinations
    li t0, 5
    li a0, 0x0fffffffffffffff
    li a1, 0x0000000000000007
    divu s2, a0, a1
    mul s2, a0, a1
    li t2, 0x6ffffffffffffff9
    bne s2, t2, fail
    mul s3, a0, a1
    divu s3, a0, a1
    li t2, 0x0249249249249249
    bne s3, t2, fail
    divu zero, a0, a1
    mul zero, a0, a0
    bnez zero, fail
    divu s4, a0, a1
    add s4, zero, zero
    bnez s4, fail

    // ---- 6: interleaving with multi-cycle FP ops
    li t0, 6
    li a0, 0x4024000000000000
    li a1, 0x4008000000000000
    fmv.d.x f1, a0
    fmv.d.x f2, a1
    li a2, 0x7654321076543210
    li a3, 0x0000000001234567
    fdiv.d f3, f1, f2
    divu s2, a2, a3
    fsqrt.d f4, f3
    mul s3, s2, a3
    fcvt.l.d s4, f3, rtz
    div s5, s2, s4
    fcvt.d.l f5, s5
    fdiv.d f6, f5, f2
    fcvt.l.d s6, f6, rtz
    li t2, 0x00000068000031a0
    bne s2, t2, fail
    li t2, 0x7654321076541760
    bne s3, t2, fail
    li t2, 0x00000022aaaabb35
    bne s5, t2, fail
    fmv.x.d t3, f3
    li t2, 0x400aaaaaaaaaaaab
    bne t3, t2, fail
    li t2, 0x0000000b8e38e911
    bne s6, t2, fail

    // ---- 7: interleaving with element-serial vector ops
    li t0, 7
    la a6, vbuf
    li a0, 0x0000000100000003
    li a1, 0x00000000000000ff
    li t1, 2
    vsetvli t1, t1, e64, m1, ta, ma
    mul s2, a0, a1
    vmv.v.x v1, s2
    divu s3, s2, a1
    vmul.vx v2, v1, s3
    vmv.x.s s4, v2
    mulhu s5, s4, s4
    vdivu.vx v3, v2, a1
    divu s6, s4, a1
    vmv.x.s s7, v3
    li t2, 0x000000ff000002fd
    bne s2, t2, fail
    li t2, 0x0000000100000003
    bne s3, t2, fail
    li t2, 0x000005fa000008f7
    bne s4, t2, fail
    li t2, 0x000000000023b824
    bne s5, t2, fail
    li t2, 0x0000000600000009
    bne s6, t2, fail
    li t2, 0x0000000600000009
    bne s7, t2, fail
    vse64.v v2, (a6)
    vle64.v v4, (a6)
    mul s8, s6, a1
    divu s9, s8, a1
    vmv.x.s s10, v4
    rem s11, s10, a1
    li t2, 0x000005fa000008f7
    bne s8, t2, fail
    li t2, 0x0000000600000009
    bne s9, t2, fail
    li t2, 0x000005fa000008f7
    bne s10, t2, fail
    li t2, 0x0000000000000000
    bne s11, t2, fail

pass:
    li t1, 0x10000000
    sd x0, 0(t1)
1:  j 1b
fail:
    li t1, 0x10000000
    sd t0, 0(t1)
1:  j 1b

    .data
    .balign 8
buf:  .skip 64
vbuf: .skip 64
