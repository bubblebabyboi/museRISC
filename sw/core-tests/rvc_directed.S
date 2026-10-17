// Directed C-extension tests (issue #18 stage 5): mixed
// 16/32-bit streams, a 32-bit instruction straddling a
// 32-bit fetch-word boundary, compressed control flow
// (link = pc+2), Zcb/Zcd ops, and the reserved-encoding
// trap with a 16-bit tval. t0 = test number.
    .text
    .globl _start
_start:
    // ---- 1: compressed arithmetic chain ---------------------
    li t0, 1
    c.li a0, 5
    c.addi a0, 3
    c.li a1, -2
    c.add a0, a1              // 6
    li a2, 6
    bne a0, a2, fail
    c.slli a0, 4              // 96
    c.srli a0, 1              // 48
    li a2, 48
    bne a0, a2, fail

    // ---- 2: straddling 32-bit instruction -------------------
    // One compressed nop puts the following 32-bit addi at
    // address % 4 == 2, so its halves come from two fetch
    // words (the straddle path).
    li t0, 2
    c.nop
    .insn i 0x13, 0, a0, zero, 777
    li a2, 777
    bne a0, a2, fail
    // and a straddling jump target: land on a 32-bit insn
    // at %4==2 via c.j
    c.j 1f
    j fail
    .balign 4
    nop
1:  .insn i 0x13, 0, a0, zero, 55
    li a2, 55
    bne a0, a2, fail

    // ---- 3: compressed loop + ld/st --------------------------
    li t0, 3
    la a5, cell
    c.li a1, 0                // sum
    c.li a2, 10               // i
1:  c.add a1, a2
    c.addi a2, -1
    c.bnez a2, 1b
    li a3, 55
    bne a1, a3, fail
    c.sd a1, 0(a5)
    c.ld a3, 0(a5)
    bne a3, a1, fail
    c.sw a1, 8(a5)
    c.lw a3, 8(a5)
    bne a3, a1, fail
    c.sb a1, 1(a5)            // Zcb (2-bit offset)
    lb a3, 1(a5)
    c.lbu a3, 1(a5)
    bne a3, a1, fail

    // ---- 4: c.jalr link must be pc+2 --------------------------
    li t0, 4
    la a1, jalr_target
    c.jalr a1
after_jalr:
    j fail
jalr_target:
    la a2, after_jalr         // c.jalr is 2 bytes: ra = its pc + 2
    bne ra, a2, fail
    c.j 3f
3:
    // ---- 5: Zcd + compressed FP ------------------------------
    li t0, 5
    li t1, (1 << 13)
    csrs mstatus, t1          // FS = Initial
    la a5, cell
    li a1, 0x3FF8000000000000 // 1.5
    sd a1, 0(a5)
    c.fld fa0, 0(a5)
    fadd.d fa0, fa0, fa0
    c.fsd fa0, 0(a5)
    ld a3, 0(a5)
    li a4, 0x4008000000000000 // 3.0
    bne a3, a4, fail
    la sp, cell               // sp is never set by the harness
    c.fldsp fa0, 0(sp)        // just execute (value unchecked)
    c.fsdsp fa0, 0(sp)

    // ---- 6: reserved encoding traps with 16-bit tval ---------
    li t0, 6
    la t1, handler
    csrw mtvec, t1
    li s0, 0                  // handler verifies cause/tval
    .2byte 0x0000             // c.addi4spn with imm=0: illegal
    li t1, 1
    bne s0, t1, fail

    // ---- 7: c.ebreak -> breakpoint cause ----------------------
    li t0, 7
    li s0, 0
    c.ebreak
    li t1, 2
    bne s0, t1, fail

pass:
    li t1, 0x10000000
    li t2, 0
    sd t2, 0(t1)
    j pass
fail:
    li t1, 0x10000000
    sd t0, 0(t1)
    j fail

    .balign 4
handler:
    c.nop                     // pad so the csrr below straddles
    csrr t3, mcause
    li t4, 2
    beq t3, t4, 1f
    li t4, 3
    beq t3, t4, 2f
    j fail
1:  // illegal: tval must be the zero-extended 16-bit parcel
    csrr t3, mtval
    bnez t3, fail             // parcel was 0x0000
    li s0, 1
    j 3f
2:  li s0, 2                  // breakpoint
3:  csrr t3, mepc
    addi t3, t3, 2            // skip the 2-byte instruction
    csrw mepc, t3
    mret

    .data
    .balign 8
cell:
    .dword 0, 0, 0
