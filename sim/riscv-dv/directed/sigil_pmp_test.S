# Directed program for the riscv-dv flow (issue #8): PMP matching against
# Spike. The privileged spec ("Priority and Matching Logic") makes the
# lowest-numbered entry that matches any byte of an access decide, and an
# entry that matches only part of the access fails it, whatever the
# privilege mode (M included, L=0 included) and L/R/W/X. With 16 entries
# and a 4-byte grain an NA4 entry or a TOR boundary splits an 8-byte
# access. This program drives the PMP with accesses of every size and
# kind in M (MPRV off, MPRV with MPP = S and U), S and U and compares
# every trap (cause, epc, tval), register write, store and vector
# register with Spike:
#   - scalar loads/stores of 1/2/4/8 bytes (also compressed), AMO .w/.d,
#     LR/SC pairs, a lone SC, FP loads/stores, HLV/HLVX/HSV;
#   - vector unit-stride (EEW 8..64), strided, indexed, segment,
#     fault-only-first, masked, whole-register loads (EEW 8/32/64) and
#     stores (fault: vstart is logged; the destination is copied to v3,
#     and so compared, after every load, but after segment and
#     whole-register loads only when they did not trap: how much of a
#     faulting segment or element is written is implementation-defined);
#   - instruction fetch from a code window of 16-bit c.nop parcels and
#     32-bit NOPs at random 2-byte offsets (32-bit ones straddle 4-byte
#     words), entered at every 2-byte offset;
#   - misaligned scalar and vector element addresses (they trap as
#     misaligned on both, before PMP).
# Phases (all seeds):
#   1. sweep: fixed configurations around a dword D (NA4 on either word,
#      TOR ending/starting inside it, NA4 over a covering NAPOT, two NA4
#      halves, empty TOR, exact TOR, no-permission NA4, TOR splitting two
#      dwords) and around the code window; every operation at D-8, D-4,
#      D, D+4 (whole-register loads at D-8 and D only) in all five modes;
#   2. walker: Sv39 PTE reads and A/D write-backs (8 bytes, checked as S)
#      with NA4/TOR/NAPOT entries over the root, level-1 and leaf PTEs,
#      through M with MPRV (MPP = S) and in S;
#   3. random: N_ITER iterations of random entries 0-7 (OFF, NA4, NAPOT 8
#      to 64 bytes, TOR; -, R, X, RX, RW, RWX) over the window, random
#      hstatus.SPVP, K_OPS random operations in each of the five modes;
#      odd seeds end with one more iteration whose entries are randomly
#      locked (L applies to M; fetches in M can fail).
# Entry 15 (NAPOT over everything, RWX, never locked) opens the rest of
# memory to S/U. The trap handler (M, nothing delegated) logs mcause,
# mepc, mtval and vstart (register writes, so compared), clears vstart,
# skips the faulting instruction (2 or 4 bytes) or, after a failed fetch,
# returns to ra.
#
# Whole-register loads with EEW=64 (vl1re64.v/vl2re64.v) are left out
# unless assembled with -DPMP_WHOLE64 (testlist entry
# sigil_pmp_whole64_test): Spike, like Sail, performs them as 8-byte
# element accesses, so an entry splitting an element fails it, while the
# core's sequencer transfers whole registers byte by byte and checks
# each byte on its own (no fault in M, tval at the failing byte in S/U).
#
# Kept architecturally defined: no W-without-R encodings, no misaligned
# whole-register base (an implementation may or may not raise
# misaligned there), LR is always followed by its SC in the same slot,
# FS and VS are Dirty from the start, no interrupts, sfence.vma after
# every PMP change in the walker phase.
#ifndef RDV_SEED
#define RDV_SEED 0
#endif
#define N_ITER    24
#define K_OPS     16
#define K_LOCK    40
#define MAX_TRAPS 400
#define TEST_VA   0xC0000000
#define MPRV      (1 << 17)
#define MPP_MASK  (3 << 11)
#define N_OPS     50
#define OP_FETCH  47
#ifdef PMP_WHOLE64
#define N_RAND_OPS 56
#else
#define N_RAND_OPS 54
#endif

# xorshift64 step: s0 = next state, rd = s0. Clobbers t6.
.macro RAND rd
        slli    t6, s0, 13
        xor     s0, s0, t6
        srli    t6, s0, 7
        xor     s0, s0, t6
        slli    t6, s0, 17
        xor     s0, s0, t6
        mv      \rd, s0
.endm

# Write pmpaddr\n from a5 (used by the table-driven configurations).
.macro SETADDR n
        ld      a5, (\n*8)(a6)
        add     a5, a5, a7
        csrw    pmpaddr\n, a5
.endm

# Random entry \n (random phase): pmpaddr\n and its cfg byte ORed into s6.
# a7 = 1: lock at random. Clobbers t0-t3, t6, a5.
.macro PMP_RAND_ENTRY n
        RAND    t0
        srli    t1, t0, 16
        li      t2, 72
        remu    t1, t1, t2
        slli    t1, t1, 2
        add     t1, t1, s2
        addi    t1, t1, -16             # t1: address in [WIN-16, WIN+272)
        srli    t2, t0, 2
        andi    t2, t2, 3               # mode: 0 OFF, 1 TOR, 2 NA4, 3 NAPOT
.if \n == 0
        li      t3, 1
        bne     t2, t3, 1f
        li      t2, 2                   # entry 0: no TOR (its base is 0)
1:
.endif
        srli    a5, t1, 2
        li      t3, 3
        bne     t2, t3, 2f
        srli    t3, t0, 8
        andi    t3, t3, 3               # NAPOT 8 << k bytes
        li      a5, 8
        sll     a5, a5, t3
        neg     t3, a5
        and     t1, t1, t3              # base aligned to the size
        srli    a5, a5, 3
        addi    a5, a5, -1              # trailing ones
        srli    t1, t1, 2
        or      a5, a5, t1
2:      csrw    pmpaddr\n, a5
        srli    t1, t0, 4
        li      t3, 6
        remu    t1, t1, t3
        la      t3, pmp_perm
        add     t3, t3, t1
        lbu     t1, 0(t3)               # permissions
        slli    t2, t2, 3
        or      t1, t1, t2
        beqz    a7, 3f
        srli    t2, t0, 12
        andi    t2, t2, 1
        slli    t2, t2, 7
        or      t1, t1, t2              # L
3:      slli    t1, t1, (8*\n)
        or      s6, s6, t1
.endm

        .section .text
        .option norvc
        .globl _start
_start:
        # Spike's boot ROM leaves t0/a0/a1 set; the core starts with zeros.
        li      t0, 0
        li      a0, 0
        li      a1, 0
        li      s0, 0x9e3779b97f4a7c15
        li      t0, RDV_SEED
        xor     s0, s0, t0
        RAND    t0
        la      t0, mtrap
        csrw    mtvec, t0
        # CLINT mtimecmp (hart 0) to the maximum (Spike's timer).
        li      t0, 0x2004000
        li      t1, -1
        sd      t1, 0(t0)
        li      t0, 1
        slli    t0, t0, 61              # menvcfg.ADUE: hardware A/D updates
        csrw    menvcfg, t0
        li      t0, (3 << 13) | (3 << 9)  # FS = VS = Dirty
        csrs    mstatus, t0
        # Entry 15: NAPOT over everything, RWX, unlocked.
        li      t0, -1
        csrw    pmpaddr15, t0
        li      t0, 0x1f
        slli    t0, t0, 56
        csrw    pmpcfg2, t0
        la      s2, win
        la      s11, trap_log
        li      s9, 0
        # Vector and FP state: v2 = indices {8,0,24,16,40,32,56,48},
        # v0 = mask 0b01011010, v8 = data, v1/v3-v7 = 0, f8 = data.
        vsetivli zero, 8, e64, m1, tu, mu
        vid.v   v2
        vsll.vi v2, v2, 3
        vxor.vi v2, v2, 8
        li      t0, 0x5a
        vmv.s.x v0, t0
        RAND    t0
        vmv.v.x v8, t0
        RAND    t0
        vadd.vx v8, v8, t0
        vid.v   v9
        vmul.vx v8, v8, t0
        vadd.vv v8, v8, v9
        vmv.v.i v1, 0
        vmv.v.i v3, 0
        vmv.v.i v4, 0
        vmv.v.i v5, 0
        vmv.v.i v6, 0
        vmv.v.i v7, 0
        vmv.v.i v10, 0
        vmv.v.i v11, 0
        vmv.v.i v12, 0
        vmv.v.i v13, 0
        RAND    t0
        fmv.d.x f8, t0
        # Random data in the window's data half and padding.
        addi    t1, s2, -512
        li      t2, (512 + 128) / 8
1:      RAND    t0
        sd      t0, 0(t1)
        addi    t1, t1, 8
        addi    t2, t2, -1
        bnez    t2, 1b
        # Code half [WIN+128, WIN+256): parcels 0x0001 (c.nop) and pairs
        # 0x0013, 0x0001 (addi x0, x2, 0, a 32-bit NOP at any 2-byte
        # offset), ending with c.jr ra. Every parcel starts a valid
        # instruction: a 0x0013 parcel is always followed by 0x0001.
        addi    t1, s2, 128
        li      t2, 0                   # offset
        li      t3, 0x0001
        li      t4, 0x0013
2:      li      t5, 120
        bgtu    t2, t5, 3f              # no room for a pair: c.nop
        RAND    t0
        andi    t0, t0, 1
        beqz    t0, 3f
        add     t5, t1, t2
        sh      t4, 0(t5)
        sh      t3, 2(t5)
        addi    t2, t2, 4
        j       4f
3:      add     t5, t1, t2
        sh      t3, 0(t5)
        addi    t2, t2, 2
4:      li      t5, 126
        bltu    t2, t5, 2b
        add     t5, t1, t2              # t2 = 126 (always reached exactly)
        li      t3, 0x8082              # c.jr ra
        sh      t3, 0(t5)
        fence.i

        # ---------------- phase 1: sweep ----------------
        call    gen_sweep
        la      a6, sweep_cfgs
sweep_loop:
        ld      t0, 32(a6)
        li      t1, -1
        beq     t0, t1, sweep_done
        csrw    pmpcfg0, zero
        srli    a7, s2, 2               # pmpaddr = WIN >> 2 + table value
        SETADDR 0
        SETADDR 1
        SETADDR 2
        SETADDR 3
        ld      t0, 32(a6)
        csrw    pmpcfg0, t0
        li      a7, 0
5:      ld      s5, sweep_n
        jal     tp, do_run
        call    readback
        addi    a7, a7, 1
        li      t0, 5
        bltu    a7, t0, 5b
        addi    a6, a6, 40
        j       sweep_loop
sweep_done:
        csrw    pmpcfg0, zero

        # ---------------- phase 2: walker ----------------
        # root[2]: 1 GiB identity leaf for the program (V R W X A D);
        # root[3] -> pt_l1, l1[0] -> pt_l0, l0[k] -> dpage + k*4 KiB.
        la      t1, pt_root
        li      t0, (0x80000 << 10) | 0xcf
        sd      t0, 16(t1)
        la      t2, pt_l1
        srli    t2, t2, 12
        slli    t2, t2, 10
        ori     t2, t2, 1
        sd      t2, 24(t1)
        la      t1, pt_l1
        la      t2, pt_l0
        srli    t2, t2, 12
        slli    t2, t2, 10
        ori     t2, t2, 1
        sd      t2, 0(t1)
        call    gen_walk
        la      t0, pt_root
        srli    t0, t0, 12
        li      t1, 8
        slli    t1, t1, 60
        or      t0, t0, t1
        csrw    satp, t0
        la      a6, walk_cfgs
walk_loop:
        ld      t0, 32(a6)
        li      t1, -1
        beq     t0, t1, walk_done
        csrw    pmpcfg0, zero
        # leaves: flags from the table (word 5)
        la      t1, pt_l0
        la      t2, dpage
        srli    t2, t2, 12
        slli    t2, t2, 10
        ld      t3, 40(a6)
        li      t4, 4
6:      or      t5, t2, t3
        sd      t5, 0(t1)
        addi    t1, t1, 8
        addi    t2, t2, 1 << 10         # next 4 KiB page
        addi    t4, t4, -1
        bnez    t4, 6b
        ld      a7, 48(a6)              # base symbol selector
        slli    a7, a7, 3
        la      t0, walk_bases
        add     a7, a7, t0
        ld      a7, 0(a7)
        srli    a7, a7, 2
        SETADDR 0
        SETADDR 1
        SETADDR 2
        SETADDR 3
        ld      t0, 32(a6)
        csrw    pmpcfg0, t0
        sfence.vma
        li      a7, 1                   # MS
        ld      s5, walk_n
        jal     tp, do_run
        call    read_ptes
        # the same configuration again in S (fresh leaves)
        la      t1, pt_l0
        la      t2, dpage
        srli    t2, t2, 12
        slli    t2, t2, 10
        ld      t3, 40(a6)
        li      t4, 4
7:      or      t5, t2, t3
        sd      t5, 0(t1)
        addi    t1, t1, 8
        addi    t2, t2, 1 << 10
        addi    t4, t4, -1
        bnez    t4, 7b
        sfence.vma
        li      a7, 3                   # S
        ld      s5, walk_n
        jal     tp, do_run
        call    read_ptes
        addi    a6, a6, 56
        j       walk_loop
walk_done:
        csrw    pmpcfg0, zero
        csrw    satp, zero
        sfence.vma

        # ---------------- phase 3: random ----------------
        li      s1, N_ITER
rand_iter:
        li      t0, 1 << 8
        csrc    hstatus, t0             # SPVP: HLV/HSV as VU or VS
        RAND    t1
        andi    t1, t1, 1
        beqz    t1, 1f
        csrs    hstatus, t0
1:      li      a7, 0
        call    gen_pmp
        li      a7, 0
2:      li      s5, K_OPS
        call    gen_rand
        li      s5, K_OPS
        jal     tp, do_run
        addi    a7, a7, 1
        li      t0, 5
        bltu    a7, t0, 2b
        call    readback
        addi    s1, s1, -1
        bnez    s1, rand_iter
#if (RDV_SEED & 1)
        # Odd seeds: one iteration with randomly locked entries.
        li      a7, 1
        call    gen_pmp
        li      a7, 0
3:      li      s5, K_LOCK
        call    gen_rand
        li      s5, K_LOCK
        jal     tp, do_run
        addi    a7, a7, 1
        li      t0, 5
        bltu    a7, t0, 3b
#else
        csrw    pmpcfg0, zero
#endif
        la      t0, result
        sd      s9, 0(t0)
        sd      s0, 8(t0)
        li      gp, 1
        la      t5, tohost
        sw      gp, 0(t5)
1:      j       1b

# ---- run the op table in mode a7 (0 M, 1 M+MPRV/MPP=S, 2 M+MPRV/MPP=U,
#      3 S, 4 U) with s5 entries; returns through tp ----
do_run:
        la      s3, optab
        li      s10, 0
        li      t0, MPRV | MPP_MASK
        csrc    mstatus, t0             # MPRV = 0, MPP = U
        li      t0, 3
        bgeu    a7, t0, 2f
        li      s7, 1
        li      s8, 0
        beqz    a7, 1f
        li      s8, MPRV | (1 << 11)
        li      t0, 1
        beq     a7, t0, 1f
        li      s8, MPRV
1:      j       stub
2:      li      s7, 0
        li      t1, 3
        bne     a7, t1, 3f
        li      t0, 1 << 11
        csrs    mstatus, t0             # MPP = S
3:      la      t0, stub
        csrw    mepc, t0
        mret
run_end:
        li      t0, MPRV
        csrc    mstatus, t0
        jr      tp

# Read back the window (4-byte loads: never split; M with no lock).
readback:
        mv      t1, s2
        li      t2, 64
1:      lw      t0, 0(t1)
        slli    t3, s9, 7
        srli    s9, s9, 57
        or      s9, s9, t3
        xor     s9, s9, t0
        addi    t1, t1, 4
        addi    t2, t2, -1
        bnez    t2, 1b
        ret

# Read back the leaf PTEs (A/D written by the walker).
read_ptes:
        la      t1, pt_l0
        li      t2, 4
1:      ld      t0, 0(t1)
        slli    t3, s9, 7
        srli    s9, s9, 57
        or      s9, s9, t3
        xor     s9, s9, t0
        addi    t1, t1, 8
        addi    t2, t2, -1
        bnez    t2, 1b
        ret

# One op table entry: op t1, address t2, data t3 at s4; s4 += 32.
put_op:
        sd      t1, 0(s4)
        sd      t2, 8(s4)
        sd      t3, 16(s4)
        addi    s4, s4, 32
        ret

# Data for op t1: a stride (strided classes) or random. Clobbers t0, t4-t6.
op_data:
        la      t4, op_cls
        add     t4, t4, t1
        lbu     t4, 0(t4)
        srli    t4, t4, 2
        andi    t4, t4, 7
        li      t5, 4
        bltu    t4, t5, 1f
        RAND    t0
        andi    t0, t0, 7
        slli    t0, t0, 3
        la      t4, strides
        add     t4, t4, t0
        ld      t3, 0(t4)
        ret
1:      RAND    t3
        ret

# Sweep op table: every op at D-8, D-4, D, D+4 (D = WIN+16; whole-register
# loads at D-8 and D only), fetches at C+{0,2,4,6,8,10,60,62} (C = WIN+128).
gen_sweep:
        mv      a6, ra
        la      s4, optab
        li      t1, 0
1:      la      t4, op_cls
        add     t4, t4, t1
        lbu     t4, 0(t4)
#ifndef PMP_WHOLE64
        andi    t5, t4, 0x20
        bnez    t5, 4f
#endif
        srli    t4, t4, 2
        andi    t4, t4, 7
        li      t5, 2
        beq     t4, t5, 3f              # fetch
        li      a5, -8
2:      li      t5, 3
        bne     t4, t5, 21f
        andi    t5, a5, 7
        bnez    t5, 22f                 # whole register: aligned only
21:     addi    t2, s2, 16
        add     t2, t2, a5
        mv      a4, t1
        call    op_data
        mv      t1, a4
        call    put_op
        la      t4, op_cls
        add     t4, t4, t1
        lbu     t4, 0(t4)
        srli    t4, t4, 2
        andi    t4, t4, 7
22:     addi    a5, a5, 4
        li      t5, 8
        blt     a5, t5, 2b
        j       4f
3:      la      a5, fetch_offs
31:     lbu     t2, 0(a5)
        li      t5, 0xff
        beq     t2, t5, 4f
        add     t2, t2, s2
        addi    t2, t2, 128
        li      t3, 0
        call    put_op
        addi    a5, a5, 1
        j       31b
4:      addi    t1, t1, 1
        li      t5, N_OPS
        bltu    t1, t5, 1b
        la      t0, optab
        sub     t0, s4, t0
        srli    t0, t0, 5
        la      t1, sweep_n
        sd      t0, 0(t1)
        mv      ra, a6
        ret

# Walker op table: walk_ops at TEST_VA + k*4 KiB + {64, 72}, k = 0..3.
gen_walk:
        mv      a6, ra
        la      s4, optab
        li      a5, 0                   # k*4096 + off index
1:      la      a4, walk_ops
2:      lbu     t1, 0(a4)
        li      t5, 0xff
        beq     t1, t5, 3f
        li      t2, TEST_VA + 64
        srli    t5, a5, 1
        slli    t5, t5, 12
        add     t2, t2, t5
        andi    t5, a5, 1
        slli    t5, t5, 3
        add     t2, t2, t5
        RAND    t3
        call    put_op
        addi    a4, a4, 1
        j       2b
3:      addi    a5, a5, 1
        li      t5, 8
        bltu    a5, t5, 1b
        la      t0, optab
        sub     t0, s4, t0
        srli    t0, t0, 5
        la      t1, walk_n
        sd      t0, 0(t1)
        mv      ra, a6
        ret

# Random op table: s5 entries.
gen_rand:
        mv      a6, ra
        la      s4, optab
        mv      a4, s5
1:      RAND    t0
        srli    t1, t0, 8
        li      t2, N_RAND_OPS
        remu    t1, t1, t2
        la      t2, rand_ops
        add     t2, t2, t1
        lbu     t1, 0(t2)               # op
        la      t2, op_cls
        add     t2, t2, t1
        lbu     t3, 0(t2)
        andi    a5, t3, 3               # log2 size
        srli    t3, t3, 2
        andi    t3, t3, 7               # kind
        srli    t2, t0, 20
        li      t4, 2
        beq     t3, t4, 4f              # fetch
        li      t4, 1
        beq     t3, t4, 2f              # store range
        li      t4, 5
        beq     t3, t4, 2f
        li      t4, 208                 # loads: [WIN-16, WIN+192)
        j       3f
2:      li      t4, 56                  # stores: [WIN-16, WIN+40)
3:      remu    t2, t2, t4
        add     t2, t2, s2
        addi    t2, t2, -16
        li      t4, -1
        sll     t4, t4, a5
        and     t2, t2, t4              # aligned to the size
        li      t4, 3
        beq     t3, t4, 5f              # whole register: stays aligned
        srli    t4, t0, 40
        andi    t4, t4, 15
        bnez    t4, 5f                  # 1 in 16: misaligned
        srli    t4, t0, 44
        li      t5, 1
        sll     t5, t5, a5
        addi    t5, t5, -1
        and     t4, t4, t5
        add     t2, t2, t4
        j       5f
4:      andi    t2, t2, 63              # fetch: [C, C+128), 2-aligned
        slli    t2, t2, 1
        add     t2, t2, s2
        addi    t2, t2, 128
5:      mv      s6, t2
        call    op_data
        mv      t2, s6
        call    put_op
        addi    a4, a4, -1
        bnez    a4, 1b
        mv      ra, a6
        ret

# Random entries 0-7 (a7 = 1: random L bits), entries 8-14 off.
gen_pmp:
        csrw    pmpcfg0, zero
        li      s6, 0
        PMP_RAND_ENTRY 0
        PMP_RAND_ENTRY 1
        PMP_RAND_ENTRY 2
        PMP_RAND_ENTRY 3
        PMP_RAND_ENTRY 4
        PMP_RAND_ENTRY 5
        PMP_RAND_ENTRY 6
        PMP_RAND_ENTRY 7
        csrw    pmpcfg0, s6
        ret

# ---- M-mode trap handler (a0-a5 only) ----
        .align 4
mtrap:
        csrr    a0, mcause
        csrr    a1, mepc
        csrr    a2, mtval
        csrr    a3, vstart
        sd      a0, 0(s11)
        sd      a1, 8(s11)
        sd      a2, 16(s11)
        sd      a3, 24(s11)
        addi    s11, s11, 32
        la      a4, trap_log_end
        bltu    s11, a4, 1f
        la      s11, trap_log
1:      csrw    vstart, zero
        addi    s10, s10, 1
        li      a4, MAX_TRAPS
        bgeu    s10, a4, 5f
        li      a4, 8
        beq     a0, a4, 5f              # ECALL from U
        li      a4, 9
        beq     a0, a4, 5f              # ECALL from S
        li      a4, 11
        beq     a0, a4, 5f              # ECALL from M
        li      a4, 1
        beq     a0, a4, 4f
        li      a4, 12
        beq     a0, a4, 4f
        lhu     a4, 0(a1)               # skip the instruction: 2 or 4 bytes
        andi    a4, a4, 3
        li      a5, 3
        addi    a1, a1, 2
        bne     a4, a5, 2f
        addi    a1, a1, 2
2:      csrw    mepc, a1
        mret
4:      csrw    mepc, ra                # failed fetch: back after the jump
        mret
5:      la      a4, run_end             # end of the run: back to M
        csrw    mepc, a4
        li      a4, MPP_MASK
        csrs    mstatus, a4
        mret

# ---- the stub: runs the op table in M (s7 = 1, mstatus MPRV/MPP from
#      s8 before every op), S or U; ends with ECALL ----
        .align 3
stub:
        beqz    s7, 1f
        li      t4, MPRV | MPP_MASK
        csrc    mstatus, t4
        csrs    mstatus, s8
1:      beqz    s5, 2f
        ld      t0, 0(s3)
        ld      t1, 8(s3)
        ld      t2, 16(s3)
        addi    s3, s3, 32
        addi    s5, s5, -1
        la      t4, ops
        slli    t5, t0, 5
        add     t4, t4, t5
        jr      t4
2:      ecall
        j       2b

# 32-byte slots, op number = slot index (t1 address, t2 data/stride).
        .balign 32
ops:
        lb      t6, 0(t1);  j stub                          # 0
        .balign 32
        lh      t6, 0(t1);  j stub
        .balign 32
        lw      t6, 0(t1);  j stub
        .balign 32
        ld      t6, 0(t1);  j stub
        .balign 32
        lbu     t6, 0(t1);  j stub
        .balign 32
        lhu     t6, 0(t1);  j stub                          # 5
        .balign 32
        lwu     t6, 0(t1);  j stub
        .balign 32
        sb      t2, 0(t1);  j stub
        .balign 32
        sh      t2, 0(t1);  j stub
        .balign 32
        sw      t2, 0(t1);  j stub
        .balign 32
        sd      t2, 0(t1);  j stub                          # 10
        .balign 32
        amoadd.w t6, t2, (t1);  j stub
        .balign 32
        amoadd.d t6, t2, (t1);  j stub
        .balign 32
        amoswap.d t6, t2, (t1);  j stub
        .balign 32
        amomaxu.d t6, t2, (t1);  j stub
        .balign 32
        lr.w    t6, (t1);  sc.w t5, t2, (t1);  j stub       # 15
        .balign 32
        lr.d    t6, (t1);  sc.d t5, t2, (t1);  j stub
        .balign 32
        sc.d    t5, t2, (t1);  j stub
        .balign 32
        fld     f1, 0(t1);  j stub
        .balign 32
        flw     f2, 0(t1);  j stub
        .balign 32
        fsd     f8, 0(t1);  j stub                          # 20
        .balign 32
        fsw     f8, 0(t1);  j stub
        .balign 32
        mv      a5, t1
        .option push
        .option rvc
        c.ld    a4, 0(a5)
        .option pop
        j       stub
        .balign 32
        mv      a5, t1
        mv      a4, t2
        .option push
        .option rvc
        c.sd    a4, 0(a5)
        .option pop
        j       stub
        .balign 32
        mv      a5, t1
        .option push
        .option rvc
        c.lw    a4, 0(a5)
        .option pop
        j       stub
        .balign 32
        mv      a5, t1                                      # 25
        .option push
        .option rvc
        c.fld   f9, 0(a5)
        .option pop
        j       stub
        .balign 32
        vsetivli zero, 4, e64, m1, tu, mu
        vle64.v v1, (t1);  vmv1r.v v3, v1;  j stub
        .balign 32
        vsetivli zero, 8, e32, m1, tu, mu
        vle32.v v1, (t1);  vmv1r.v v3, v1;  j stub
        .balign 32
        vsetivli zero, 8, e16, m1, tu, mu
        vle16.v v1, (t1);  vmv1r.v v3, v1;  j stub
        .balign 32
        vsetivli zero, 16, e8, m1, tu, mu
        vle8.v  v1, (t1);  vmv1r.v v3, v1;  j stub
        .balign 32
        vsetivli zero, 4, e64, m1, tu, mu                   # 30
        vse64.v v8, (t1);  j stub
        .balign 32
        vsetivli zero, 4, e32, m1, tu, mu
        vse32.v v8, (t1);  j stub
        .balign 32
        vsetivli zero, 3, e64, m1, tu, mu
        vlse64.v v1, (t1), t2;  vmv1r.v v3, v1;  j stub
        .balign 32
        vsetivli zero, 4, e64, m1, tu, mu
        vloxei64.v v1, (t1), v2;  vmv1r.v v3, v1;  j stub
        .balign 32
        vsetivli zero, 4, e64, m1, tu, mu
        vle64ff.v v1, (t1);  csrr t6, vl;  vmv1r.v v3, v1;  j stub
        .balign 32
        vsetivli zero, 2, e64, m1, tu, mu                   # 35
        mv      t3, s10;  vlseg2e64.v v4, (t1);  bne s10, t3, 1f
        vmv1r.v v3, v4;  vmv1r.v v6, v5
1:      j       stub
        .balign 32
        vsetivli zero, 4, e32, m1, tu, mu
        mv      t3, s10;  vlseg2e32.v v4, (t1);  bne s10, t3, 1f
        vmv1r.v v3, v4;  vmv1r.v v6, v5
1:      j       stub
        .balign 32
        vsetivli zero, 4, e64, m1, tu, mu
        vle64.v v1, (t1), v0.t;  vmv1r.v v3, v1;  j stub
        .balign 32
        mv      t3, s10;  vl1re64.v v10, (t1);  bne s10, t3, 1f
        vmv1r.v v3, v10
1:      j       stub
        .balign 32
        mv      t3, s10;  vl2re64.v v12, (t1);  bne s10, t3, 1f
        vmv1r.v v3, v12;  vmv1r.v v11, v13
1:      j       stub
        .balign 32
        mv      t3, s10;  vl1re32.v v10, (t1);  bne s10, t3, 1f   # 40
        vmv1r.v v3, v10
1:      j       stub
        .balign 32
        mv      t3, s10;  vl1re8.v v10, (t1);  bne s10, t3, 1f
        vmv1r.v v3, v10
1:      j       stub
        .balign 32
        vs1r.v  v8, (t1);  j stub
        .balign 32
        hlv.d   t6, (t1);  j stub
        .balign 32
        hlv.w   t6, (t1);  j stub
        .balign 32
        hsv.d   t2, (t1);  j stub                           # 45
        .balign 32
        hlvx.wu t6, (t1);  j stub
        .balign 32
        jalr    ra, 0(t1);  j stub                          # 47: fetch
        .balign 32
        vsetivli zero, 4, e64, m1, tu, mu
        vsse64.v v8, (t1), t2;  j stub
        .balign 32
        amoswap.w t6, t2, (t1);  j stub
        .balign 32

        .section .data
        .align 6; .global tohost; tohost: .dword 0
        .align 6; .global fromhost; fromhost: .dword 0
        .align 3
sweep_n:  .dword 0
walk_n:   .dword 0
result:   .zero 64
# Strides for vlse64/vsse64 (8-byte elements; 4 makes element 1 misaligned).
strides:  .dword 8, 16, 24, -8, 0, 8, 16, 4
pmp_perm: .byte 0, 1, 4, 5, 3, 7               # -, R, X, RX, RW, RWX
# Operation classes: kind << 2 | log2(size); kind 0 load, 1 store, 2
# fetch, 3 whole-register load (base stays aligned), 4 strided load, 5
# strided store; 0x20 marks the EEW=64 whole-register loads.
op_cls:
        .byte 0x00, 0x01, 0x02, 0x03, 0x00, 0x01, 0x02          # 0-6 loads
        .byte 0x04, 0x05, 0x06, 0x07                            # 7-10 stores
        .byte 0x06, 0x07, 0x07, 0x07, 0x06, 0x07, 0x07          # 11-17 AMO/LR/SC
        .byte 0x03, 0x02, 0x07, 0x06                            # 18-21 FP
        .byte 0x03, 0x07, 0x02, 0x03                            # 22-25 compressed
        .byte 0x03, 0x02, 0x01, 0x00, 0x07, 0x06                # 26-31 vector unit
        .byte 0x13, 0x03, 0x03, 0x03, 0x02, 0x03                # 32-37
        .byte 0x2f, 0x2f, 0x0e, 0x0c, 0x04                      # 38-42 whole
        .byte 0x03, 0x02, 0x07, 0x02                            # 43-46 HLV/HSV
        .byte 0x09                                              # 47 fetch
        .byte 0x17, 0x06                                        # 48-49
# Operations the random phase draws from.
rand_ops:
        .byte 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17
        .byte 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33
        .byte 34, 35, 36, 37
#ifdef PMP_WHOLE64
        .byte 38, 39
#endif
        .byte 40, 41, 42, 43, 44, 45, 46, 47, 47, 47, 48, 49, 3, 10, 12, 16
fetch_offs: .byte 0, 2, 4, 6, 8, 10, 60, 62, 0xff
# Walker operations.
walk_ops: .byte 3, 2, 10, 12, 16, 18, 22, 26, 41, 30, 0xff
        .align 3
# Sweep configurations: pmpaddr0-3 as word offsets from WIN (NAPOT
# trailing ones included), then pmpcfg0 (entries 0-3); -1 ends.
# D = WIN+16 is word 4; the code window C = WIN+128 is word 32.
#define NA4(p)   (0x10 | (p))
#define TOR(p)   (0x08 | (p))
#define NAPOT(p) (0x18 | (p))
#define CFG(a, b, c, d) ((a) | ((b) << 8) | ((c) << 16) | ((d) << 24))
sweep_cfgs:
        .dword 5, 0, 0, 0, CFG(NA4(7), 0, 0, 0)                 # NA4 on D's upper word
        .dword 4, 0, 0, 0, CFG(NA4(7), 0, 0, 0)                 # NA4 on D's lower word
        .dword 0, 5, 0, 0, CFG(0, TOR(7), 0, 0)                 # TOR [WIN, D+4)
        .dword 5, 16, 0, 0, CFG(0, TOR(7), 0, 0)                # TOR [D+4, WIN+64)
        .dword 5, 7, 0, 0, CFG(NA4(1), NAPOT(7), 0, 0)          # NA4 R over NAPOT 64 RWX
        .dword 4, 5, 0, 0, CFG(NAPOT(3), NA4(4), 0, 0)          # NAPOT 8 RW on D, NA4 X
        .dword 4, 5, 0, 0, CFG(NA4(7), NA4(7), 0, 0)            # two NA4 halves
        .dword 3, 5, 0, 0, CFG(0, TOR(3), 0, 0)                 # TOR [D-4, D+4) RW
        .dword 6, 4, 5, 0, CFG(0, TOR(7), NA4(1), 0)            # empty TOR, NA4 R
        .dword 5, 0, 0, 0, CFG(NA4(0), 0, 0, 0)                 # NA4 no permission
        .dword 4, 6, 0, 0, CFG(0, TOR(1), 0, 0)                 # TOR [D, D+8) R (exact)
        .dword 5, 3, 0, 0, CFG(NAPOT(4), NA4(3), 0, 0)          # NAPOT 16 X at D, NA4 RW D-4
        .dword 33, 0, 0, 0, CFG(NA4(3), 0, 0, 0)                # code: NA4 C+4 RW (no X)
        .dword 34, 48, 47, 0, CFG(0, TOR(7), NAPOT(3), 0)       # code: RWX [C+8, C+64) over RW [C, C+128)
        .dword 0, 0, 0, 0, -1
# Walker configurations: pmpaddr0-3 (word offsets from the selected
# base), pmpcfg0, leaf flags, base (0 pt_root, 1 pt_l1, 2 pt_l0).
walk_cfgs:
        .dword 7, 0, 0, 0, CFG(NA4(7), 0, 0, 0), 0xc7, 0        # root[3] upper word
        .dword 6, 0, 0, 0, CFG(NA4(7), 0, 0, 0), 0xc7, 0        # root[3] lower word
        .dword 6, 0, 0, 0, CFG(NAPOT(7), 0, 0, 0), 0xc7, 0      # root[3] whole: fine
        .dword 6, 0, 0, 0, CFG(NAPOT(4), 0, 0, 0), 0xc7, 0      # root[3] X only
        .dword 1, 0, 0, 0, CFG(NA4(7), 0, 0, 0), 0xc7, 1        # l1[0] upper word
        .dword 0, 1, 0, 0, CFG(0, TOR(7), 0, 0), 0xc7, 1        # TOR l1[0] lower word
        .dword 2, 3, 0, 0, CFG(0, TOR(7), 0, 0), 0x07, 2        # l0[1] lower word, A=D=0
        .dword 3, 6, 0, 0, CFG(0, TOR(7), 0, 0), 0x47, 2        # l0[1] upper + l0[2], D=0
        .dword 3, 0, 0, 0, CFG(NAPOT(1), 0, 0, 0), 0x47, 2      # l0[0-3] R only, D=0
        .dword 3, 0, 0, 0, CFG(NAPOT(1), 0, 0, 0), 0x07, 2      # l0[0-3] R only, A=D=0
        .dword 1, 0, 0, 0, CFG(NA4(7), 0, 0, 0), 0x07, 2        # l0[0] upper word, A=0
        .dword 0, 7, 0, 0, CFG(0, TOR(7), 0, 0), 0x07, 2        # TOR [l0, l0+28): l0[3] split
        .dword 0, 0, 0, 0, -1, 0, 0
walk_bases: .dword pt_root, pt_l1, pt_l0
        .align 12
pt_root:      .zero 4096
pt_l1:        .zero 4096
pt_l0:        .zero 4096
dpage:        .zero 4*4096
        .align 9
pad_lo:       .zero 512
win:          .zero 256                 # data [WIN, WIN+128), code [WIN+128, WIN+256)
pad_hi:       .zero 512
optab:        .zero 32*512
trap_log:     .zero 16384
trap_log_end:
