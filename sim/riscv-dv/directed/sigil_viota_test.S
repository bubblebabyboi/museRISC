# viota.m program for the riscv-dv flow (issue #8), self-checking.
#
# Every iteration loads all 32 vector registers with PRNG data (seeded
# with RDV_SEED), picks a random legal vtype (SEW 8..64, LMUL mf8..m8,
# random vta/vma), an AVL from {0, 1, 2, VLMAX-1, VLMAX, >= 2*VLMAX,
# random in [0, VLMAX]}, masked or unmasked, a destination group vd
# (aligned to LMUL; v0 only when unmasked) and a source mask register
# vs2 anywhere outside the vd group (v0 with probability 1/8, so also
# vs2 = v0 under v0.t), with the vs2 and v0 contents random, all ones,
# sparse or dense. It runs viota.m vd, vs2[, v0.t] from a table of all
# 2048 encodings, stores the register file and checks in scalar code:
#   - active elements below vl hold the count of set vs2 bits in the
#     active elements before them (mod 2^SEW);
#   - masked-off elements are unchanged (mu) or unchanged/all ones (ma);
#   - tail elements up to the end of the vd group (for fractional LMUL
#     the whole register) are unchanged (tu) or unchanged/all ones (ta);
#     with vl = 0 they are unchanged under ta too (RVV 1.0 sec. 5.4:
#     no element is updated when vstart >= vl);
#   - every register outside the vd group is unchanged;
#   - vstart reads 0 afterwards, and no trap was taken.
# One iteration in 16 each runs an encoding RVV 1.0 makes illegal
# instead (vd not aligned to LMUL; v0.t with vd = v0; vtype.vill set);
# it must trap as an illegal instruction and change no register.
# The riscv-dv flow compares every scalar read of the stored register
# file, the vstart read and the traps with Spike as well.
#
# Two optional modes, for the reserved / must-trap cases Sigil does not
# reject yet (assemble with -D...; not in the regression list):
#   VIOTA_VSTART=1   half the iterations run viota.m with vstart != 0,
#                    which RVV 1.0 (sec. 15.8) requires to raise an
#                    illegal-instruction exception (Spike does);
#   VIOTA_OVERLAP=1  half the iterations use a vs2 inside the vd group
#                    (reserved by RVV 1.0; Spike raises an illegal-
#                    instruction exception).
#
# VIOTA_SWEEP=1 replaces the random choice of vtype, policy, AVL and
# masking by a sweep of all 1408 combinations: the 22 legal vtypes
# (SEW 8..64 x LMUL mf8..m8) x {tu,ta} x {mu,ma} x {unmasked, v0.t} x
# eight AVL classes (0, 1, 2, VLMAX-1, VLMAX, all ones, VLMAX+1,
# random in [0, VLMAX]); only legal encodings, with vs2 an odd register
# (so off every LMUL > 1 boundary) in 6 of 8 iterations, v0 in 1 of 8,
# any register in 1 of 8. Iteration i runs combination
# (SWEEP_START + i) mod 1408; by default ITERS = 88 and SWEEP_START =
# (RDV_SEED mod 16) * 88, one of 16 chunks, each every vtype under four
# AVL classes and one policy/masking pair.
#
# With SIGIL_CORE_TEST defined it builds as a directed core test
# (sw/core-tests/viota_directed.S: exit store to 0x1000_0000, 0 = pass).
# Failure code (tohost = ((iteration << 8 | code) << 1) | 1):
#   1 expected trap not taken, 2 trap cause not 2, 3 unexpected trap,
#   4 masked-off element, 5 active element (count), 6 tail element,
#   7 register outside vd changed, 8 vstart not 0 afterwards.

#ifndef RDV_SEED
#define RDV_SEED 1
#endif
#ifndef VIOTA_SWEEP
#define VIOTA_SWEEP 0
#endif
#ifndef ITERS
#if VIOTA_SWEEP
#define ITERS 88
#else
#define ITERS 96
#endif
#endif
#ifndef SWEEP_START
#define SWEEP_START ((RDV_SEED % 16) * 88)
#endif
#ifndef VIOTA_VSTART
#define VIOTA_VSTART 0
#endif
#ifndef VIOTA_OVERLAP
#define VIOTA_OVERLAP 0
#endif

#define K_LEGAL    0
#define K_MISALIGN 1
#define K_MASKV0   2
#define K_VILL     3
#define K_VSTART   4
#define K_OVERLAP  5

#ifdef SIGIL_CORE_TEST
        .option arch, +v
        .option norvc
#endif

# s0 PRNG state, s1 iterations left, s2 register image in (2 KiB),
# s3 register image out, s4 vtype, s5 SEW code, s6 vlmul, s7 registers
# in the vd group, s8 vl, s9 VLMAX, s10 vd, s11 vs2, tp 1 = masked,
# gp case kind (K_*). t0 is the PRNG's temporary; t5/t6 belong to the
# trap handler.

        .macro RND rd
        slli    t0, s0, 13
        xor     s0, s0, t0
        srli    t0, s0, 7
        xor     s0, s0, t0
        slli    t0, s0, 17
        xor     s0, s0, t0
        mv      \rd, s0
        .endm

        # rd = this iteration's sweep combination (VIOTA_SWEEP).
        .macro COMBO rd
        li      \rd, ITERS + SWEEP_START
        sub     \rd, \rd, s1
        li      t0, 1408
        remu    \rd, \rd, t0
        .endm

        .macro FILL base, n
        mv      a6, \base
        li      a7, \n
1:      RND     a5
        sd      a5, 0(a6)
        addi    a6, a6, 8
        addi    a7, a7, -1
        bnez    a7, 1b
        .endm

        # rd = zero-extended SEW-wide element at addr (SEW code in s5).
        .macro LDEL rd, addr
        beqz    s5, .Lb\@
        li      t3, 1
        beq     s5, t3, .Lh\@
        li      t3, 2
        beq     s5, t3, .Lw\@
        ld      \rd, 0(\addr)
        j       .Le\@
.Lb\@:  lbu     \rd, 0(\addr)
        j       .Le\@
.Lh\@:  lhu     \rd, 0(\addr)
        j       .Le\@
.Lw\@:  lwu     \rd, 0(\addr)
.Le\@:
        .endm

        .section .text
        .globl _start
_start:
        la      t1, trap
        csrw    mtvec, t1
        li      t1, (3 << 13) | (3 << 9)   # mstatus.FS and .VS = Dirty
        csrs    mstatus, t1
        li      s0, 0x9e3779b97f4a7c15
        li      t1, RDV_SEED
        xor     s0, s0, t1
        li      s1, ITERS
        la      s2, regs_in
        la      s3, regs_out

iter:
        FILL    s2, 256

#if VIOTA_SWEEP
        # --- sweep: combination = vtype + 22 * (AVL class + 8 *
        #     (policy + 4 * masked)), VLMAX in s9
        COMBO   a1
        li      t1, 22
        remu    a2, a1, t1
        divu    a1, a1, t1
        la      a3, vtypes
        add     a3, a3, a2
        lbu     a4, 0(a3)
        srli    a5, a1, 3
        andi    a5, a5, 3               # vta (bit 0), vma (bit 1)
        slli    a5, a5, 6
        or      s4, a4, a5
        vsetvl  s9, x0, s4
        andi    a2, a1, 7               # AVL class
        RND     a1
#else
        # --- random legal vtype with random vta/vma, VLMAX in s9
        RND     a1
        andi    a2, a1, 31
        la      a3, vtypes
        add     a3, a3, a2
        lbu     a4, 0(a3)
        srli    a5, a1, 8
        andi    a5, a5, 0xc0
        or      s4, a4, a5
        vsetvl  s9, x0, s4
        # --- AVL: 0, 1, 2, VLMAX-1, VLMAX, all ones, or [0, VLMAX]
        srli    a1, a1, 16
        andi    a2, a1, 7
        srli    a1, a1, 3
#endif
        li      a7, 0
        beqz    a2, avl_set
        li      a7, 1
        li      t1, 1
        beq     a2, t1, avl_set
        li      a7, 2
        li      t1, 2
        beq     a2, t1, avl_set
        addi    a7, s9, -1
        li      t1, 3
        beq     a2, t1, avl_set
        mv      a7, s9
        li      t1, 4
        beq     a2, t1, avl_set
        li      a7, -1
        li      t1, 5
        beq     a2, t1, avl_set
#if VIOTA_SWEEP
        addi    a7, s9, 1               # class 7: VLMAX+1 (vl = VLMAX)
        li      t1, 7
        beq     a2, t1, avl_set
#endif
        addi    t1, s9, 1
        remu    a7, a1, t1
avl_set:
        vsetvl  s8, a7, s4
        srli    s5, s4, 3
        andi    s5, s5, 7
        andi    s6, s4, 7
        li      s7, 1
        li      t1, 4
        bgeu    s6, t1, 1f
        sll     s7, s7, s6
1:
        # --- masked or not, case kind
        RND     a1
        andi    tp, a1, 1
        srli    a1, a1, 1
        andi    a2, a1, 15
        li      gp, K_LEGAL
#if VIOTA_SWEEP
        COMBO   t2                      # masked: combination >= 704
        li      t1, 704
        sltu    tp, t2, t1
        xori    tp, tp, 1
        j       3f                      # legal encodings only
#endif
#if VIOTA_VSTART
        li      t1, 8
        bgeu    a2, t1, 2f
        li      gp, K_VSTART
        j       3f
2:
#elif VIOTA_OVERLAP
        li      t1, 8
        bgeu    a2, t1, 2f
        li      gp, K_OVERLAP
        j       3f
2:
#endif
        li      t1, 8
        bne     a2, t1, 2f
        li      gp, K_MISALIGN
2:      li      t1, 9
        bne     a2, t1, 2f
        li      gp, K_MASKV0
2:      li      t1, 10
        bne     a2, t1, 3f
        li      gp, K_VILL
3:
        # vd misalignment needs LMUL > 1; v0.t with vd = v0 needs v0.t
        li      t1, K_MISALIGN
        bne     gp, t1, 1f
        li      t1, 1
        bne     s7, t1, 1f
        li      gp, K_LEGAL
1:      li      t1, K_MASKV0
        bne     gp, t1, 1f
        li      tp, 1
1:
        # --- vd: an LMUL-aligned group (v0 only when unmasked)
        RND     a1
        li      t1, 32
        divu    t1, t1, s7
        remu    s10, a1, t1
        mul     s10, s10, s7
        li      t1, K_MASKV0
        bne     gp, t1, 1f
        li      s10, 0
        j       vd_done
1:      beqz    tp, vd_done
        bnez    s10, vd_done
        mv      s10, s7
vd_done:
        # --- vs2: inside the vd group (K_OVERLAP), else outside it,
        #     v0 with probability 1/8
        li      t1, K_OVERLAP
        bne     gp, t1, 1f
        RND     a1
        remu    a2, a1, s7
        add     s11, s10, a2
        j       vs2_done
1:      RND     a1
        andi    a2, a1, 7
        li      s11, 0
        beqz    a2, 2f
4:      RND     a1
        andi    s11, a1, 31
#if VIOTA_SWEEP
        li      t1, 1
        beq     a2, t1, 2f              # 1 in 8: any register,
        ori     s11, s11, 1             # else odd (not LMUL-aligned)
#endif
2:      bltu    s11, s10, vs2_done
        add     t1, s10, s7
        bgeu    s11, t1, vs2_done
        j       4b
vs2_done:
        # --- K_MISALIGN: move vd inside its group, off the boundary
        li      t1, K_MISALIGN
        bne     gp, t1, 1f
        RND     a1
        addi    t1, s7, -1
        remu    a2, a1, t1
        addi    a2, a2, 1
        add     s10, s10, a2
1:
        # --- mask data: random, all ones, sparse or dense
        mv      a0, s11
        jal     ra, bias
        li      a0, 0
        jal     ra, bias

        vl8re8.v v0, (s2)
        addi    t1, s2, 512
        vl8re8.v v8, (t1)
        addi    t1, s2, 1024
        vl8re8.v v16, (t1)
        addi    t1, s2, 1536
        vl8re8.v v24, (t1)

        li      t1, K_VILL
        bne     gp, t1, 1f
        li      a1, 4                   # vlmul 4 is reserved: vill
        vsetvl  a2, s9, a1
1:      li      t1, K_VSTART
        bne     gp, t1, 1f
        RND     a1
        andi    a1, a1, 63
        addi    a1, a1, 1
        csrw    vstart, a1
1:
        la      t1, trap_info
        sd      x0, 0(t1)
        sd      x0, 16(t1)

        # --- viota.m vd, vs2[, v0.t]: table entry (vd, vs2, vm)
        slli    a1, s10, 6
        slli    a2, s11, 1
        or      a1, a1, a2
        xori    a2, tp, 1
        or      a1, a1, a2
        slli    a1, a1, 3
        la      a2, viota_tab
        add     a1, a1, a2
        jalr    ra, 0(a1)
        csrr    s6, vstart              # 0 after the instruction or its trap
        csrw    vstart, x0

        vs8r.v  v0, (s3)
        addi    t1, s3, 512
        vs8r.v  v8, (t1)
        addi    t1, s3, 1024
        vs8r.v  v16, (t1)
        addi    t1, s3, 1536
        vs8r.v  v24, (t1)

        # --- check
        la      a0, trap_info
        ld      a1, 16(a0)              # traps taken
        ld      a2, 0(a0)               # last mcause
        beqz    gp, chk_legal
        li      a7, 1
        li      a3, 1
        bne     a1, a3, fail
        li      a7, 2
        li      a3, 2
        bne     a2, a3, fail
        li      a7, 8
        li      t1, K_VSTART
        beq     gp, t1, 1f              # (the trap leaves vstart as it was)
        bnez    s6, fail
1:      li      a5, 0                   # check all 32 registers
        li      a6, 0
        j       chk_regs

chk_legal:
        li      a7, 3
        bnez    a1, fail
        li      a7, 8
        bnez    s6, fail
        li      a0, 0                   # element index
        li      a1, 0                   # count
        slli    a2, s7, 6
        srl     a2, a2, s5              # elements in the vd group
        li      a3, -1                  # SEW-wide all ones
        li      t1, 3
        beq     s5, t1, el_loop
        li      t1, 8
        sll     t1, t1, s5
        li      a3, 1
        sll     a3, a3, t1
        addi    a3, a3, -1
el_loop:
        sll     t1, a0, s5
        slli    t2, s10, 6
        add     t1, t1, t2
        add     t2, s3, t1
        LDEL    a4, t2                  # new value
        add     t2, s2, t1
        LDEL    a5, t2                  # old value
        bgeu    a0, s8, el_tail
        beqz    tp, el_act
        srli    t1, a0, 3               # v0 bit i
        add     t1, t1, s2
        lbu     t1, 0(t1)
        andi    t2, a0, 7
        srl     t1, t1, t2
        andi    t1, t1, 1
        bnez    t1, el_act
        beq     a4, a5, el_next         # masked off: unchanged,
        li      a7, 4
        srli    t1, s4, 7               # or all ones under vma
        andi    t1, t1, 1
        beqz    t1, fail
        bne     a4, a3, fail
        j       el_next
el_act:
        and     t1, a1, a3
        li      a7, 5
        bne     a4, t1, fail
        srli    t1, a0, 3               # vs2 bit i
        slli    t2, s11, 6
        add     t1, t1, t2
        add     t1, t1, s2
        lbu     t1, 0(t1)
        andi    t2, a0, 7
        srl     t1, t1, t2
        andi    t1, t1, 1
        add     a1, a1, t1
        j       el_next
el_tail:
        beq     a4, a5, el_next         # tail: unchanged,
        li      a7, 6
        beqz    s8, fail                # (always when vl = 0)
        srli    t1, s4, 6               # or all ones under vta
        andi    t1, t1, 1
        beqz    t1, fail
        bne     a4, a3, fail
el_next:
        addi    a0, a0, 1
        bltu    a0, a2, el_loop
        mv      a5, s10                 # vd group checked above
        add     a6, s10, s7

chk_regs:
        li      a0, 0
1:      bltu    a0, a5, 2f
        bltu    a0, a6, 4f
2:      slli    t1, a0, 6
        add     t2, s2, t1
        add     t1, s3, t1
        li      a1, 8
3:      ld      a2, 0(t1)
        ld      a3, 0(t2)
        li      a7, 7
        bne     a2, a3, fail
        addi    t1, t1, 8
        addi    t2, t2, 8
        addi    a1, a1, -1
        bnez    a1, 3b
4:      addi    a0, a0, 1
        li      t1, 32
        bltu    a0, t1, 1b

        addi    s1, s1, -1
        bnez    s1, iter

pass:
#ifdef SIGIL_CORE_TEST
        li      t1, 0x10000000
        sd      x0, 0(t1)
#else
        li      t1, 1
        la      t2, tohost
        sd      t1, 0(t2)
#endif
1:      j       1b

fail:
        li      t1, ITERS
        sub     t1, t1, s1
        slli    t1, t1, 8
        or      t1, t1, a7
#ifdef SIGIL_CORE_TEST
        li      t2, 0x10000000
        sd      t1, 0(t2)
#else
        slli    t1, t1, 1
        ori     t1, t1, 1
        la      t2, tohost
        sd      t1, 0(t2)
#endif
1:      j       1b

        # Overwrite register a0's image: kept random, all ones,
        # sparse (AND of three) or dense (OR of two).
bias:
        slli    a1, a0, 6
        add     a1, a1, s2
        RND     a2
        andi    a3, a2, 3
        beqz    a3, 9f
        li      a4, 8
1:      RND     a5
        li      t1, 1
        bne     a3, t1, 2f
        li      a5, -1
        j       3f
2:      li      t1, 2
        bne     a3, t1, 2f
        RND     t1
        and     a5, a5, t1
        RND     t1
        and     a5, a5, t1
        j       3f
2:      RND     t1
        or      a5, a5, t1
3:      sd      a5, 0(a1)
        addi    a1, a1, 8
        addi    a4, a4, -1
        bnez    a4, 1b
9:      ret

        # Trap handler: record mcause/mtval, count, skip the 4-byte
        # trapping instruction (only table entries trap).
        .align 2
trap:
        la      t5, trap_info
        csrr    t6, mcause
        sd      t6, 0(t5)
        csrr    t6, mtval
        sd      t6, 8(t5)
        ld      t6, 16(t5)
        addi    t6, t6, 1
        sd      t6, 16(t5)
        csrr    t6, mepc
        addi    t6, t6, 4
        csrw    mepc, t6
        mret

        # viota.m vd, vs2[, v0.t] for every vd, vs2, vm: entry
        # (vd << 6 | vs2 << 1 | vm) at 8 bytes each, the instruction
        # then a return. Raw encodings: the assembler rejects the
        # reserved ones (vd = vs2, v0.t with vd = v0). (Aligned before
        # norvc, so the linker's relaxation has room to pad.)
        .align 3
        .option push
        .option norvc
viota_tab:
        .irp d, 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
        .irp s, 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
        .word   (0x14 << 26) | (0 << 25) | (\s << 20) | (0x10 << 15) | (2 << 12) | (\d << 7) | 0x57
        jalr    x0, 0(ra)
        .word   (0x14 << 26) | (1 << 25) | (\s << 20) | (0x10 << 15) | (2 << 12) | (\d << 7) | 0x57
        jalr    x0, 0(ra)
        .endr
        .endr
        .option pop

        .section .data
#ifndef SIGIL_CORE_TEST
        .align 6; .global tohost; tohost: .dword 0
        .align 6; .global fromhost; fromhost: .dword 0
#endif
        # Legal vtypes (vsew << 3 | vlmul), 32 entries: every SEW with
        # LMUL 1, 2, 4, 8 and the fractional LMULs with SEW <= LMUL*64,
        # then LMUL 2/4/8 again (where vs2 is narrower than the group).
vtypes:
        .byte 0x00, 0x01, 0x02, 0x03, 0x05, 0x06, 0x07     # e8  m1 m2 m4 m8 mf8 mf4 mf2
        .byte 0x08, 0x09, 0x0a, 0x0b, 0x0e, 0x0f           # e16 m1 m2 m4 m8 mf4 mf2
        .byte 0x10, 0x11, 0x12, 0x13, 0x17                 # e32 m1 m2 m4 m8 mf2
        .byte 0x18, 0x19, 0x1a, 0x1b                       # e64 m1 m2 m4 m8
        .byte 0x01, 0x02, 0x03, 0x09, 0x0a, 0x0b, 0x11, 0x12, 0x13, 0x1b
        .align 3
trap_info:
        .dword 0, 0, 0                  # mcause, mtval, count
        .align 6
regs_in:
        .zero 2048
regs_out:
        .zero 2048
