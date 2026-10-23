# Directed program for the riscv-dv flow (issue #8): HINT encodings, which
# riscv-dv's riscv_hint_instr_test should generate but pygen cannot (its
# HINT constraint fails to solve). Each of N_ITER iterations writes a
# block of N_INSN random HINTs (and FENCEs with random ignored fields)
# into a code buffer, then FENCE.I and a call into it; the block ends
# with c.jr ra. Seeded with RDV_SEED (-DRDV_SEED=<gen_seed>). Every
# register holds PRNG data while the block runs, so a HINT decoded as
# something that writes a register, traps or jumps diverges from Spike.
# M-mode, no translation.
#
# 32-bit HINTs (rd = x0): LUI, AUIPC, OP-IMM (ADDI, SLTI, SLTIU, XORI,
# ORI incl. the Zicbop prefetch encodings, ANDI, SLLI, SRLI, SRAI),
# OP (all funct3 with funct7 0, ADD/SUB/SRL/SRA with funct7 0x20, the M
# extension with funct7 1), OP-IMM-32 and OP-32 likewise. FENCE with
# random pred/succ (0 included: a HINT; FENCE w,0 is PAUSE), fm 0 or
# 1000, and random rs1/rd (reserved: implementations shall ignore them).
# 16-bit HINTs: C.NOP with nzimm != 0, C.ADDI with imm 0, C.LI and
# C.LUI with rd = x0, C.MV and C.ADD with rd = x0, C.SLLI with rd = x0
# or shamt 0, C.SRLI and C.SRAI with shamt 0.
#ifndef RDV_SEED
#define RDV_SEED 0
#endif
#define N_ITER 200
#define N_INSN 24

.macro RAND rd
        slli    t6, s0, 13
        xor     s0, s0, t6
        srli    t6, s0, 7
        xor     s0, s0, t6
        slli    t6, s0, 17
        xor     s0, s0, t6
        mv      \rd, s0
.endm

        .section .text
        .globl _start
_start:
        li      t0, 0
        li      a0, 0
        li      a1, 0
        li      s0, 0x9e3779b97f4a7c15
        li      t0, RDV_SEED
        xor     s0, s0, t0
        li      s1, N_ITER
        li      s9, 0
iter:
        la      s2, codebuf             # write pointer (halfwords)
        li      s3, N_INSN
gen:    RAND    s4
        andi    t0, s4, 1
        bnez    t0, rvc
        # ---- one 32-bit HINT: s5 = encoding ----
        srli    t0, s4, 1
        li      t1, 9
        remu    t0, t0, t1              # family
        srli    s6, s4, 8               # field bits
        li      t2, 0x1f
        srli    t3, s6, 0
        and     t3, t3, t2              # rs1
        srli    t4, s6, 5
        and     t4, t4, t2              # rs2
        srli    a2, s6, 10
        li      t2, 0xfff
        and     a2, a2, t2              # imm[11:0]
        srli    a3, s6, 22
        andi    a3, a3, 7               # funct3
        slli    t3, t3, 15
        slli    t4, t4, 20
        slli    a4, a3, 12
        la      t1, fam32
        slli    t0, t0, 2
        add     t1, t1, t0
        lw      t0, 0(t1)
        la      t1, fam32
        add     t0, t0, t1
        jr      t0
        .align 2
fam32:  .word f_lui - fam32, f_auipc - fam32, f_opimm - fam32, f_shimm - fam32
        .word f_op - fam32, f_opimm32 - fam32, f_shimm32 - fam32, f_op32 - fam32
        .word f_fence - fam32
f_lui:  li      s5, 0x37
        slli    t0, s6, 12              # random imm[31:12]
        li      t1, -4096
        and     t0, t0, t1
        slli    t0, t0, 32
        srli    t0, t0, 32
        or      s5, s5, t0
        j       put32
f_auipc:
        li      s5, 0x17
        slli    t0, s6, 12
        li      t1, -4096
        and     t0, t0, t1
        slli    t0, t0, 32
        srli    t0, t0, 32
        or      s5, s5, t0
        j       put32
f_opimm:                                # ADDI SLTI SLTIU XORI ORI ANDI
        li      t0, 6
        remu    t0, a3, t0
        la      t1, opimm_f3
        add     t1, t1, t0
        lbu     t0, 0(t1)
        slli    t0, t0, 12
        li      s5, 0x13
        or      s5, s5, t0
        or      s5, s5, t3
        slli    t0, a2, 20
        or      s5, s5, t0
        j       put32
f_shimm:                                # SLLI, SRLI, SRAI, shamt 0-63
        andi    t0, a2, 0x3f
        slli    t0, t0, 20
        li      s5, 0x13
        or      s5, s5, t0
        or      s5, s5, t3
        andi    t0, a3, 3
        beqz    t0, 1f
        li      t1, 1
        beq     t0, t1, 2f
        li      t1, 0x5000              # SRLI
        or      s5, s5, t1
        j       put32
2:      li      t1, 0x40005000          # SRAI
        or      s5, s5, t1
        j       put32
1:      li      t1, 0x1000              # SLLI
        or      s5, s5, t1
        j       put32
f_op:   # funct7 0: any funct3; 1 (M): any funct3; 0x20 with funct3 0, 4,
        # 5, 6, 7: SUB, XNOR, SRA, ORN, ANDN (Zbb); else funct7 0
        li      s5, 0x33
        or      s5, s5, t3
        or      s5, s5, t4
        or      s5, s5, a4
        srli    t0, s6, 26
        andi    t0, t0, 3
        beqz    t0, put32               # funct7 0 (also for 3)
        li      t1, 3
        beq     t0, t1, put32
        li      t1, 1
        beq     t0, t1, 1f
        li      t1, 0x02000000          # funct7 1: MUL..REMU
        or      s5, s5, t1
        j       put32
1:      addi    t0, a3, -1              # funct3 1-3: keep funct7 0
        li      t1, 3
        bltu    t0, t1, put32
        li      t1, 0x40000000
        or      s5, s5, t1
        j       put32
f_opimm32:                              # ADDIW
        li      s5, 0x1b
        or      s5, s5, t3
        slli    t0, a2, 20
        or      s5, s5, t0
        j       put32
f_shimm32:                              # SLLIW, SRLIW, SRAIW, shamt 0-31
        andi    t0, a2, 0x1f
        slli    t0, t0, 20
        li      s5, 0x1b
        or      s5, s5, t0
        or      s5, s5, t3
        andi    t0, a3, 3
        beqz    t0, 1f
        li      t1, 1
        beq     t0, t1, 2f
        li      t1, 0x5000
        or      s5, s5, t1
        j       put32
2:      li      t1, 0x40005000
        or      s5, s5, t1
        j       put32
1:      li      t1, 0x1000
        or      s5, s5, t1
        j       put32
f_op32:                                 # (funct3, funct7) from op32_tab
        li      t0, 10
        remu    t0, a2, t0
        slli    t0, t0, 2
        la      t1, op32_tab
        add     t1, t1, t0
        lw      s5, 0(t1)
        or      s5, s5, t3
        or      s5, s5, t4
        j       put32
f_fence:                                # pred/succ random, fm 0 or 1000, rs1/rd random
        li      s5, 0x0f
        or      s5, s5, t3              # rs1
        srli    t0, s6, 3
        andi    t0, t0, 0x1f
        slli    t0, t0, 7               # rd
        or      s5, s5, t0
        andi    t0, a2, 0xff            # pred, succ
        slli    t0, t0, 20
        or      s5, s5, t0
        andi    t0, a2, 0x100
        beqz    t0, put32
        li      t1, 0x80000000          # fm = 1000
        or      s5, s5, t1
put32:  sh      s5, 0(s2)
        srli    s5, s5, 16
        sh      s5, 2(s2)
        addi    s2, s2, 4
        j       next
        # ---- one 16-bit HINT ----
rvc:    srli    t0, s4, 1
        li      t1, 9
        remu    t0, t0, t1
        srli    s6, s4, 8
        andi    t3, s6, 0x1f            # 5-bit field
        srli    t4, s6, 5
        andi    t4, t4, 0x1f            # second 5-bit field
        srli    a2, s6, 10
        andi    a2, a2, 1               # imm[5]
        la      t1, fam16
        slli    t0, t0, 2
        add     t1, t1, t0
        lw      t0, 0(t1)
        la      t1, fam16
        add     t0, t0, t1
        jr      t0
        .align 2
fam16:  .word c_nop - fam16, c_addi0 - fam16, c_li - fam16, c_lui - fam16, c_mv - fam16
        .word c_add - fam16, c_slli - fam16, c_srli - fam16, c_srai - fam16
c_nop:  bnez    t3, 1f                  # C.NOP, nzimm != 0
        li      t3, 1
1:      slli    t0, t3, 2
        slli    t1, a2, 12
        or      s5, t0, t1
        ori     s5, s5, 0x0001
        j       put16
c_addi0:                                # C.ADDI rd != 0, imm 0
        bnez    t3, 1f
        li      t3, 5
1:      slli    s5, t3, 7
        ori     s5, s5, 0x0001
        j       put16
c_li:   slli    t0, t3, 2               # C.LI x0, imm
        slli    t1, a2, 12
        or      s5, t0, t1
        li      t1, 0x4001
        or      s5, s5, t1
        j       put16
c_lui:  bnez    t3, 1f                  # C.LUI x0, nzimm != 0
        bnez    a2, 1f
        li      t3, 1
1:      slli    t0, t3, 2
        slli    t1, a2, 12
        or      s5, t0, t1
        li      t1, 0x6001
        or      s5, s5, t1
        j       put16
c_mv:   bnez    t4, 1f                  # C.MV x0, rs2 != 0
        li      t4, 7
1:      slli    s5, t4, 2
        li      t1, 0x8002
        or      s5, s5, t1
        j       put16
c_add:  bnez    t4, 1f                  # C.ADD x0, rs2 != 0
        li      t4, 9
1:      slli    s5, t4, 2
        li      t1, 0x9002
        or      s5, s5, t1
        j       put16
c_slli: andi    t0, s6, 0x400           # C.SLLI: rd = x0 (any shamt) or shamt 0
        beqz    t0, 1f
        slli    t0, t3, 2               # rd = x0
        slli    t1, a2, 12
        or      s5, t0, t1
        ori     s5, s5, 0x0002
        j       put16
1:      bnez    t4, 2f                  # shamt 0, rd != 0
        li      t4, 11
2:      slli    s5, t4, 7
        ori     s5, s5, 0x0002
        j       put16
c_srli: andi    t0, t3, 7               # C.SRLI rd', shamt 0
        slli    t0, t0, 7
        li      t1, 0x8001
        or      s5, t0, t1
        j       put16
c_srai: andi    t0, t3, 7               # C.SRAI rd', shamt 0
        slli    t0, t0, 7
        li      t1, 0x8401
        or      s5, t0, t1
put16:  sh      s5, 0(s2)
        addi    s2, s2, 2
next:   addi    s3, s3, -1
        bnez    s3, gen
        li      t0, 0x8082              # c.jr ra
        sh      t0, 0(s2)
        fence.i
        # PRNG data in every register the block can name (not s0-s3,
        # ra, sp, gp, tp, the loop state).
        RAND    t0
        RAND    t1
        RAND    t2
        RAND    t3
        RAND    t4
        RAND    t5
        RAND    a0
        RAND    a1
        RAND    a2
        RAND    a3
        RAND    a4
        RAND    a5
        RAND    a6
        RAND    a7
        RAND    s4
        RAND    s5
        RAND    s6
        RAND    s7
        RAND    s8
        RAND    s10
        RAND    s11
        la      t6, codebuf
        jalr    ra, 0(t6)
        # Fold registers into the digest (compared as register writes).
        xor     s9, s9, t0
        xor     s9, s9, a0
        xor     s9, s9, s4
        xor     s9, s9, s11
        addi    s1, s1, -1
        bnez    s1, iter

        la      t0, result
        sd      s9, 0(t0)
        sd      s0, 8(t0)
        li      gp, 1
        la      t5, tohost
        sw      gp, 0(t5)
1:      j       1b

        .section .data
        .align 6; .global tohost; tohost: .dword 0
        .align 6; .global fromhost; fromhost: .dword 0
opimm_f3: .byte 0, 2, 3, 4, 6, 7
        .align 2
# OP-32 (opcode 0x3b, rd 0): ADDW SUBW SLLW SRLW SRAW MULW DIVW DIVUW REMW REMUW
op32_tab: .word 0x0000003b, 0x4000003b, 0x0000103b, 0x0000503b, 0x4000503b
          .word 0x0200003b, 0x0200403b, 0x0200503b, 0x0200603b, 0x0200703b
        .align 3
result: .zero 16
        .align 6
codebuf: .zero 4*N_INSN + 64
