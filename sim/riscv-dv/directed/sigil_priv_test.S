# Directed program for the riscv-dv flow (issue #8): the privileged
# architecture that riscv-dv's pygen cannot generate (no page tables, no
# PMP setup, no trap delegation, no interrupts), run through the same
# Spike vs DUT commit-trace comparison as the generated tests. A
# xorshift64 PRNG seeded with RDV_SEED (-DRDV_SEED=<gen_seed>) drives
# N_ITER iterations. Each iteration, in M-mode:
#   - rewrites the Sv39 test mappings: eight 4 KiB leaves at TEST_VA
#     (random V/R/W/X/U/G/D, A set, random backing page, sometimes a
#     reserved PTE bit) or, one iteration in eight, one 64 KiB Svnapot
#     leaf for the whole 16-entry group; and the level-1 entry for
#     MEGA_VA: a random 2 MiB leaf (sometimes with a misaligned PPN) or a
#     pointer to the level-0 table (sometimes with reserved bits set);
#   - programs PMP entries 0-2 at random (OFF, NA4, NAPOT of 8 B to
#     16 KiB or TOR; none/R/X/RX/RW/RWX) over the level-1/level-0 tables
#     (entry 0) and the backing pages; entry 15 opens everything else;
#   - draws medeleg (fetch/load/store page faults, illegal instruction,
#     breakpoint, ecall from U), mideleg, mie and pending
#     mip bits (SSIP/STIP/SEIP), and mstatus (MPP = S or U, TVM, SUM,
#     MXR, FS, SIE, SPIE, SPP, MPIE);
#   - SFENCE.VMA, then MRET into a stub that may first set sstatus.SIE
#     (illegal in U), then does one random access through TEST_VA or
#     MEGA_VA: a load, store, AMO, LR, FP load, a jump into the page
#     (fetch), EBREAK, an S CSR read or SFENCE.VMA (illegal in U), then
#     ECALL back to M.
# Traps go to the M or S handler as delegated. Each handler logs
# xcause/xepc/xtval/xstatus (register writes and stores, so compared),
# skips a faulting instruction, returns from a failed fetch to ra,
# clears an interrupt it can clear (S hands STI/SEI back to M with an
# ECALL), and ends the iteration on ECALL. At the end of every iteration
# M reads back all test PTEs (A/D updates by hardware: menvcfg.ADUE=1,
# Svadu on both sides) and mip.
#
# Kept architecturally defined on purpose: A is preset in every leaf (A
# may be set speculatively), no misaligned accesses (their priority
# against page/access faults is implementation-defined), no SC, no FP
# stores (FS may be dirtied imprecisely), no WFI, ASID 0, NAPOT groups
# are written whole, and the root table is never under random PMP (the
# stub and the handlers translate through it).
#ifndef RDV_SEED
#define RDV_SEED 0
#endif
#define N_ITER    128
#define TEST_VA   0xC0000000
#define MEGA_VA   0xC0200000
#define MEGA_PA   0x80400000
#define NAPOT_PA  0x80500000
#define ALIAS_OFF 0x40000000       /* U alias of the program: VA = PA - ALIAS_OFF */
#define N_OPS     24
#define MAX_TRAPS 24               /* per iteration, then M ends it */

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

# Leaf flags from random \r: V (7 in 8), R, W, X, U, G, D random, A set.
.macro LEAF_FLAGS out, r, tmp
        srli    \out, \r, 2
        andi    \out, \out, 0x3e
        srli    \tmp, \r, 1
        andi    \tmp, \tmp, 0x80
        or      \out, \out, \tmp
        ori     \out, \out, 0x40
        andi    \tmp, \r, 7
        snez    \tmp, \tmp
        or      \out, \out, \tmp
.endm

# Non-leaf PTE pointing at table \sym: (PA >> 12) << 10 | V.
.macro PTR out, sym
        la      \out, \sym
        srli    \out, \out, 12
        slli    \out, \out, 10
        ori     \out, \out, 1
.endm

# PMP entry \n (0-2) at random over the first \pages pages of [pt_l1,
# bpages_end) (entry 0: the two page tables): on half the time, as NA4,
# NAPOT (8 B to 16 KiB; pt_l1 is 32 KiB aligned and the region padded to
# 32 KiB, so a NAPOT region stays inside) or, for entries 1 and 2, TOR
# (base: the previous entry's pmpaddr, which an OFF entry also points
# into the region), with permissions from pmp_perm.
# NA4 and TOR boundaries split 8-byte accesses (PTE reads included).
# Its pmpcfg byte is ORed into s6. Clobbers s4, s5, t0-t3, t6.
.macro PMP_ENTRY n, pages
        RAND    s4
        srli    s5, s4, 16
        li      t2, \pages*4096
        remu    s5, s5, t2
        la      t2, pt_l1
        add     s5, s5, t2              # s5: byte address in the region
        srli    t2, s5, 2
        csrw    pmpaddr\n, t2           # also the next entry's TOR base
        andi    t0, s4, 1
        bnez    t0, 99f                 # off
        srli    t0, s4, 3
        li      t1, 6
        remu    t0, t0, t1
        la      t1, pmp_perm
        add     t1, t1, t0
        lbu     t3, 0(t1)               # permissions
        srli    t0, s4, 8
        li      t1, 12
        remu    t0, t0, t1
        addi    t0, t0, 3               # k: NAPOT size 2^k bytes
        srli    t2, s4, 2
        andi    t2, t2, 3               # 0 NA4, 1-2 NAPOT, 3 TOR
        beqz    t2, 96f
        li      t1, 3
        bne     t2, t1, 98f
.if \n == 0
        j       98f                     # entry 0: no TOR (base 0)
.endif
        srli    t1, s5, 2               # TOR: top = the address
        csrw    pmpaddr\n, t1
        ori     t3, t3, 0x08            # A = TOR
        j       97f
96:     srli    t1, s5, 2               # NA4
        csrw    pmpaddr\n, t1
        ori     t3, t3, 0x10            # A = NA4
        j       97f
98:     li      t2, -1                  # NAPOT of 2^k bytes
        sll     t2, t2, t0
        and     t1, s5, t2              # aligned base
        srli    t1, t1, 2
        addi    t0, t0, -3
        li      t2, 1
        sll     t2, t2, t0
        addi    t2, t2, -1
        or      t1, t1, t2
        csrw    pmpaddr\n, t1
        ori     t3, t3, 0x18            # A = NAPOT
97:     slli    t3, t3, 8*\n
        or      s6, s6, t3
99:
.endm

        .section .text
        .globl _start
_start:
        # Spike's boot ROM leaves t0/a0/a1 set; the core starts with zeros.
        li      t0, 0
        li      a0, 0
        li      a1, 0
        li      s0, 0x9e3779b97f4a7c15
        li      t0, RDV_SEED
        xor     s0, s0, t0
        la      t0, mtrap
        csrw    mtvec, t0
        la      t0, strap
        csrw    stvec, t0
        # CLINT mtimecmp (hart 0, as on the Sigil SoC) to the maximum:
        # Spike's timer would raise MTIP otherwise (mtimecmp resets to
        # 0); core_tb has no CLINT and the store just lands in memory.
        li      t0, 0x2004000
        li      t1, -1
        sd      t1, 0(t0)
        li      t0, 1
        slli    t0, t0, 61              # menvcfg.ADUE: hardware A/D updates
        csrw    menvcfg, t0
        # PMP entry 15: NAPOT over everything, RWX (below entries 0-2).
        li      t0, -1
        csrw    pmpaddr15, t0
        li      t0, 0x1f
        slli    t0, t0, 56
        csrw    pmpcfg2, t0
        # Static entries of the root table.
        la      s2, pt_root
        li      t0, (0x80000 << 10) | 0xdf   # VA 1 GiB: U alias of the program (V R W X U A D)
        sd      t0, 8(s2)
        li      t0, (0x80000 << 10) | 0xcf   # VA 2 GiB: the program for S and M (V R W X A D)
        sd      t0, 16(s2)
        PTR     t0, pt_l1                    # VA 3 GiB: TEST_VA and MEGA_VA
        sd      t0, 24(s2)
        # Random data in the backing pages, then `ret` in the first 64
        # bytes of every page a fetch can reach.
        la      s2, bpages
        li      s3, 4*4096/8
1:      RAND    t0
        sd      t0, 0(s2)
        addi    s2, s2, 8
        addi    s3, s3, -1
        bnez    s3, 1b
        la      a0, bpages
        li      a1, 4
        call    fill_ret
        li      a0, MEGA_PA
        li      a1, 1
        call    fill_ret
        li      a0, NAPOT_PA
        li      a1, 16
        call    fill_ret
        fence.i
        la      t0, pt_root
        srli    t0, t0, 12
        li      t1, 8
        slli    t1, t1, 60
        or      t0, t0, t1              # Sv39, ASID 0
        csrw    satp, t0
        la      s11, trap_log
        li      s1, N_ITER
        li      s9, 0                   # digest of the read-back state

iter:
        li      t0, 0x222
        csrc    mip, t0                 # no S-level interrupt left pending
        li      s10, 0                  # traps in this iteration
        # ---- level-0 test leaves ----
        RAND    s3
        la      s2, pt_l0
        andi    t0, s3, 7
        bnez    t0, 2f
        # One Svnapot 64 KiB leaf for the whole 16-entry group.
        RAND    s4
        LEAF_FLAGS s5, s4, t0
        li      t1, (((NAPOT_PA >> 12) | 8) << 10)
        or      t1, t1, s5
        li      t0, 1
        slli    t0, t0, 63              # N
        or      t1, t1, t0
        li      t2, 16
1:      sd      t1, 0(s2)
        addi    s2, s2, 8
        addi    t2, t2, -1
        bnez    t2, 1b
        j       3f
2:      # Eight 4 KiB leaves; entries 8-15 invalid.
        li      s7, 8
1:      RAND    s4
        LEAF_FLAGS s5, s4, t0
        srli    t1, s4, 40
        andi    t1, t1, 3
        slli    t1, t1, 12
        la      t0, bpages
        add     t1, t1, t0
        srli    t1, t1, 12
        slli    t1, t1, 10              # PPN of a random backing page
        or      s5, s5, t1
        srli    t1, s4, 50
        andi    t1, t1, 7
        bnez    t1, 4f
        # one leaf in eight: a reserved bit (54-58 reserved, 59-60
        # Svrsw60t59b, 61-62 PBMT; none implemented): page fault
        srli    t1, s4, 53
        li      t0, 9
        remu    t1, t1, t0
        addi    t1, t1, 54
        li      t0, 1
        sll     t0, t0, t1
        or      s5, s5, t0
4:      sd      s5, 0(s2)
        addi    s2, s2, 8
        addi    s7, s7, -1
        bnez    s7, 1b
        li      s7, 8
1:      sd      zero, 0(s2)
        addi    s2, s2, 8
        addi    s7, s7, -1
        bnez    s7, 1b
3:      # ---- level-1 entries ----
        la      s2, pt_l1
        PTR     t0, pt_l0
        sd      t0, 0(s2)               # TEST_VA -> pt_l0
        RAND    s4
        LEAF_FLAGS s5, s4, t0
        andi    t0, s5, 0xe
        bnez    t0, 5f
        # R=W=X=0: a pointer to pt_l0 (MEGA_VA then aliases TEST_VA's
        # group); one in four with a bit reserved in non-leaf PTEs (U,
        # A, D, 54-62): page fault.
        PTR     t0, pt_l0
        srli    t1, s4, 50
        andi    t1, t1, 3
        bnez    t1, 6f
        srli    t1, s4, 53
        li      t2, 12
        remu    t1, t1, t2
        la      t2, rsvd_nonleaf
        add     t2, t2, t1
        lbu     t1, 0(t2)
        li      t2, 1
        sll     t2, t2, t1
        or      t0, t0, t2
6:      sd      t0, 8(s2)
        j       7f
5:      # A 2 MiB leaf at MEGA_PA; one in four with PPN[0] != 0
        # (misaligned superpage): page fault.
        li      t0, ((MEGA_PA >> 12) << 10)
        srli    t1, s4, 44
        andi    t1, t1, 3
        bnez    t1, 8f
        srli    t1, s4, 46
        andi    t1, t1, 0x1ff
        ori     t1, t1, 1
        slli    t1, t1, 10
        or      t0, t0, t1
8:      or      t0, t0, s5
        sd      t0, 8(s2)
7:      # ---- PMP entries 0-2 ----
        li      s6, 0
        PMP_ENTRY 0, 2
        PMP_ENTRY 1, 6
        PMP_ENTRY 2, 6
        csrw    pmpcfg0, s6
        # ---- delegation and interrupts ----
        RAND    s4
        # Delegable on both sides: illegal instruction, breakpoint, ECALL
        # from U, fetch/load/store page faults. Which exceptions can be
        # delegated is implementation-defined (WARL); Sigil keeps access
        # faults (1, 5, 7) in M, Spike can delegate them.
        li      t0, 0xb10c              # 2 3 8 12 13 15
        and     t1, s4, t0
        csrw    medeleg, t1
        srli    t1, s4, 16
        andi    t1, t1, 0x222
        csrw    mideleg, t1
        srli    t1, s4, 28
        andi    t1, t1, 0x222
        csrw    mie, t1
        srli    t1, s4, 40
        andi    t1, t1, 0x222
        csrs    mip, t1
        # ---- mstatus: MPP S or U, TVM, SUM, MXR, FS, SIE, SPIE, SPP, MPIE ----
        RAND    s4
        li      t0, (1 << 20) | (1 << 19) | (1 << 18) | (3 << 13) | (1 << 8) | (1 << 7) | (1 << 5) | (1 << 1)
        and     t1, s4, t0
        andi    s8, s4, 1               # 1: S, 0: U
        slli    t2, s8, 11
        or      t1, t1, t2
        csrw    mstatus, t1
        # ---- the stub's operands ----
        RAND    s4
        andi    t0, s4, 0xff
        li      t1, N_OPS
        remu    t0, t0, t1              # t0: operation
        srli    t2, s4, 8
        andi    t2, t2, 15
        li      t1, 12
        bltu    t2, t1, 1f
        li      t1, MEGA_VA             # 12-15: the first page of MEGA_VA
        j       2f
1:      andi    t2, t2, 7               # 0-11: one of the eight test pages
        slli    t2, t2, 12
        li      t1, TEST_VA
        add     t1, t1, t2
2:      li      t2, 15
        bne     t0, t2, 3f
        srli    t2, s4, 16              # fetch: one of the `ret`s at 0-60
        andi    t2, t2, 0x3c
        j       4f
3:      srli    t2, s4, 19              # data: 8-byte aligned, 64-4088
        andi    t2, t2, 0x1ff
        slli    t2, t2, 3
        ori     t2, t2, 0x40
4:      add     t1, t1, t2              # t1: address
        srli    t5, s4, 30
        andi    t5, t5, 3
        seqz    t5, t5                  # t5: set sstatus.SIE first (1 in 4)
        RAND    t2                      # t2: store data
        la      t3, stub
        bnez    s8, 5f
        li      t4, ALIAS_OFF
        sub     t3, t3, t4              # U runs the stub through its alias
5:      csrw    mepc, t3
        sfence.vma
        mret

# Back in M from the stub's ECALL (or the trap limit).
m_iter_end:
        la      s2, pt_l0
        li      s7, 16
1:      ld      t0, 0(s2)
        slli    t1, s9, 7
        srli    s9, s9, 57
        or      s9, s9, t1
        xor     s9, s9, t0
        addi    s2, s2, 8
        addi    s7, s7, -1
        bnez    s7, 1b
        la      s2, pt_l1
        ld      t0, 8(s2)
        xor     s9, s9, t0
        csrr    t0, mip
        add     s9, s9, t0
        addi    s1, s1, -1
        bnez    s1, iter

        la      t0, result
        sd      s9, 0(t0)
        sd      s0, 8(t0)
        li      gp, 1
        la      t5, tohost
        sw      gp, 0(t5)
1:      j       1b

# fill_ret(a0 = page PA, a1 = pages): `ret` in bytes 0-63 of each page.
fill_ret:
        li      t0, 0x00008067
1:      li      t1, 16
        mv      t2, a0
2:      sw      t0, 0(t2)
        addi    t2, t2, 4
        addi    t1, t1, -1
        bnez    t1, 2b
        li      t1, 4096
        add     a0, a0, t1
        addi    a1, a1, -1
        bnez    a1, 1b
        ret

# ---- M-mode trap handler (uses a0-a5 only) ----
        .align 4
mtrap:
        csrr    a0, mcause
        csrr    a1, mepc
        csrr    a2, mtval
        csrr    a3, mstatus
        sd      a0, 0(s11)
        sd      a1, 8(s11)
        sd      a2, 16(s11)
        sd      a3, 24(s11)
        addi    s11, s11, 32
        la      a4, trap_log_end
        bltu    s11, a4, 1f
        la      s11, trap_log
1:      addi    s10, s10, 1
        li      a4, MAX_TRAPS
        bgeu    s10, a4, m_iter_end
        bltz    a0, 3f
        li      a4, 8
        beq     a0, a4, m_iter_end      # ECALL from U
        li      a4, 9
        beq     a0, a4, m_iter_end      # ECALL from S
        li      a4, 1
        beq     a0, a4, 2f
        li      a4, 12
        beq     a0, a4, 2f
        addi    a1, a1, 4               # skip the faulting instruction
        csrw    mepc, a1
        mret
2:      csrw    mepc, ra                # failed fetch: back after the jump
        mret
3:      slli    a4, a0, 1               # interrupt: clear its pending bit
        srli    a4, a4, 1
        li      a5, 1
        sll     a5, a5, a4
        csrc    mip, a5
        mret

# ---- S-mode trap handler (identity-mapped; uses a0-a5 only) ----
        .align 4
strap:
        csrr    a0, scause
        csrr    a1, sepc
        csrr    a2, stval
        csrr    a3, sstatus
        sd      a0, 0(s11)
        sd      a1, 8(s11)
        sd      a2, 16(s11)
        sd      a3, 24(s11)
        addi    s11, s11, 32
        la      a4, trap_log_end
        bltu    s11, a4, 1f
        la      s11, trap_log
1:      addi    s10, s10, 1
        li      a4, MAX_TRAPS
        bgeu    s10, a4, 4f
        bltz    a0, 3f
        li      a4, 8
        beq     a0, a4, 4f              # ECALL from U: hand back to M
        li      a4, 1
        beq     a0, a4, 2f
        li      a4, 12
        beq     a0, a4, 2f
        addi    a1, a1, 4
        csrw    sepc, a1
        sret
2:      csrw    sepc, ra
        sret
3:      slli    a4, a0, 1
        srli    a4, a4, 1
        li      a5, 1
        bne     a4, a5, 4f              # STI/SEI: only M can clear them
        csrci   sip, 2
        sret
4:      ecall                           # to M (cause 9, never delegated)

# ---- the stub, run in S (identity) or U (alias) ----
# t0 = operation, t1 = address, t2 = store data, t5 = set SIE first.
        .align 3
        .option push
        .option norvc
        .option norelax
stub:
        beqz    t5, 1f
        csrsi   sstatus, 2              # S: SIE on (pending S interrupts now); U: illegal
1:      la      t4, ops
        slli    t3, t0, 3
        add     t4, t4, t3
        jr      t4
ops:    lb      t3, 0(t1);           j stub_done   # 0
        lh      t3, 0(t1);           j stub_done
        lw      t3, 0(t1);           j stub_done
        ld      t3, 0(t1);           j stub_done
        lbu     t3, 0(t1);           j stub_done
        lhu     t3, 0(t1);           j stub_done
        lwu     t3, 0(t1);           j stub_done
        sb      t2, 0(t1);           j stub_done
        sh      t2, 0(t1);           j stub_done
        sw      t2, 0(t1);           j stub_done
        sd      t2, 0(t1);           j stub_done   # 10
        amoadd.w t3, t2, (t1);       j stub_done
        amoswap.d t3, t2, (t1);      j stub_done
        amoor.d t3, t2, (t1);        j stub_done
        lr.d    t3, (t1);            j stub_done
        jalr    ra, 0(t1);           j stub_done   # 15: fetch from the page
        fld     f1, 0(t1);           j stub_done
        flw     f2, 0(t1);           j stub_done
        ebreak;                      j stub_done
        csrr    t3, sstatus;         j stub_done
        csrr    t3, sip;             j stub_done   # 20
        csrr    t3, satp;            j stub_done
        sfence.vma;                  j stub_done
        csrr    t3, sie;             j stub_done   # 23
stub_done:
        ecall
        j       stub_done
        .option pop

        .section .data
        .align 6; .global tohost; tohost: .dword 0
        .align 6; .global fromhost; fromhost: .dword 0
pmp_perm:     .byte 0, 1, 4, 5, 3, 7               # -, R, X, RX, RW, RWX
rsvd_nonleaf: .byte 4, 6, 7, 54, 55, 56, 57, 58, 59, 60, 61, 62
        .align 12
pt_root:      .zero 4096
        .align 15                       # the random PMP region: 32 KiB
pt_l1:        .zero 4096
pt_l0:        .zero 4096
bpages:       .zero 4*4096
              .zero 2*4096
trap_log:     .zero 32768
trap_log_end:
result:       .zero 64
