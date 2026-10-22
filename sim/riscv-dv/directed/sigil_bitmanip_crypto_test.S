# Directed program for the riscv-dv flow (issue #8): instructions that
# riscv-dv's pygen cannot generate, run through the same Spike vs DUT
# commit-trace comparison as the generated tests. A xorshift64 PRNG
# feeds 300 iterations of RV64 Zba/Zbb/Zbs W-forms, Zbkb/Zbkc/Zbkx,
# Zkne/Zknd/Zknh and Zicond, so every result register write is
# compared; the stores at the end are compared too. Assembled with
# Zcb, so the assembler emits Zcb encodings where it can.
        .section .text
        .globl _start
_start:
        li      s0, 0x9e3779b97f4a7c15   # PRNG state
        li      s1, 300                  # iterations
        li      s2, 0                    # running digest
loop:
        slli    t0, s0, 13
        xor     s0, s0, t0
        srli    t0, s0, 7
        xor     s0, s0, t0
        slli    t0, s0, 17
        xor     s0, s0, t0
        mv      a0, s0
        rori    a1, s0, 29
        xor     a1, a1, s2
        andi    a6, a0, 3              # zero one time in four (Zicond)

        # Zba
        sh1add  a2, a0, a1
        sh2add  a3, a0, a1
        sh3add  a4, a0, a1
        add.uw  a5, a0, a1
        sh1add.uw a2, a1, a2
        sh2add.uw a3, a1, a3
        sh3add.uw a4, a1, a4
        slli.uw a5, a0, 7
        # Zbb (incl. RV64 W forms)
        clz     t1, a5
        ctz     t2, a4
        cpop    t3, a3
        clzw    t4, a2
        ctzw    t5, a0
        cpopw   t6, a1
        max     t1, t1, a0
        minu    t2, t2, a1
        andn    t3, a0, a1
        orn     t4, a0, a1
        xnor    t5, a0, a1
        rol     t6, a0, a1
        ror     t1, a1, a0
        rolw    t2, a0, a1
        rorw    t3, a1, a0
        roriw   t4, a0, 13
        rev8    t5, a0
        orc.b   t6, a1
        sext.b  t1, a0
        sext.h  t2, a1
        zext.h  t3, a0
        # Zbs
        bset    t4, a0, a1
        bclr    t5, a0, a1
        binv    t6, a0, a1
        bext    t1, a0, a1
        bexti   t2, a1, 41
        # Zbkb / Zbkc / Zbkx
        brev8   t3, a0
        pack    t4, a0, a1
        packh   t5, a0, a1
        packw   t6, a0, a1
        clmul   t1, a0, a1
        clmulh  t2, a0, a1
        clmulr  t3, a0, a1
        xperm4  t4, a0, a1
        xperm8  t5, a1, a0
        # Zkne / Zknd
        aes64es  a2, a0, a1
        aes64esm a3, a0, a1
        aes64ds  a4, a0, a1
        aes64dsm a5, a0, a1
        aes64im  a7, a0
        aes64ks1i t6, a0, 4
        aes64ks2 t1, a0, a1
        # Zknh
        sha256sig0 t2, a0
        sha256sig1 t3, a1
        sha256sum0 t4, a0
        sha256sum1 t5, a1
        sha512sig0 t6, a0
        sha512sig1 a7, a1
        sha512sum0 t1, a0
        sha512sum1 t2, a1
        # Zicond
        czero.eqz t3, a0, a6
        czero.nez t4, a1, a6

        # Fold the results into the digest so later rounds depend on them.
        xor     s2, s2, a2
        add     s2, s2, a3
        xor     s2, s2, a4
        add     s2, s2, a5
        xor     s2, s2, a7
        add     s2, s2, t1
        xor     s2, s2, t2
        add     s2, s2, t3
        xor     s2, s2, t4
        add     s2, s2, t5
        xor     s2, s2, t6
        addi    s1, s1, -1
        bnez    s1, loop

        la      t0, result
        sd      s2, 0(t0)
        sd      s0, 8(t0)
        sw      s2, 16(t0)
        sh      s2, 20(t0)
        sb      s2, 22(t0)
        li      gp, 1
        la      t5, tohost
        sw      gp, 0(t5)
1:      j       1b

        .section .data
        .align 6; .global tohost; tohost: .dword 0
        .align 6; .global fromhost; fromhost: .dword 0
        .align 3
result: .zero 32
