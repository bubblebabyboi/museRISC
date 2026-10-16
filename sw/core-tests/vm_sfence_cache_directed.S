// Directed page-table / SFENCE.VMA tests through the caches.
// The page-table walker reads (and A/D-updates) PTEs through
// the write-back D$, so PTE stores that are still dirty in the
// D$, PTEs evicted to memory, and hardware A/D writes must all
// be seen consistently by the walker and by ordinary loads.
//   1 basic Sv39 4K load
//   2 PTE rewritten (dirty in D$) + SFENCE.VMA: new mapping
//   3 hardware A then D update visible to plain loads of the PTE
//   4 code page remapped + SFENCE.VMA: fetch follows the new PA
//   5 PTE rewritten, its line evicted from the D$ by conflict,
//     SFENCE.VMA: walker reads the written-back PTE
// S-mode body; ecall to M reports (a7 = 0 pass, else t0 fails).
    .option norvc
    .text
    .globl _start

.equ PGROOT, 0x100000
.equ PGL1,   0x101000
.equ PGL0,   0x102000
.equ PA_P1,  0x180000
.equ PA_P2,  0x181000
.equ PA_AD,  0x182000
.equ PA_C1,  0x183000
.equ PA_C2,  0x184000
.equ VA_D,   0x200000
.equ VA_AD,  0x201000
.equ VA_C,   0x202000
.equ D_WAY_BYTES, 4096

.macro PTEW tbl, idx, pa, flags
    li t1, \pa
    srli t1, t1, 2
    ori t1, t1, \flags
    li t2, \tbl + \idx * 8
    sd t1, 0(t2)
.endm

_start:
    la t1, handler_m
    csrw mtvec, t1
    li t1, -1
    csrw pmpaddr15, t1
    li t1, 0x1f
    slli t1, t1, 56
    csrw pmpcfg2, t1
    li t1, PGROOT
    li t2, PGROOT + 0x3000
1:  sd x0, 0(t1)
    addi t1, t1, 8
    blt t1, t2, 1b
    // Flags: V1 R2 W4 X8 U16 G32 A64 D128.
    PTEW PGROOT, 0, PGL1, 0x01
    PTEW PGL1, 0, 0x000000, 0xCF      // 2M identity RWX
    PTEW PGL1, 1, PGL0, 0x01
    PTEW PGL0, 0, PA_P1, 0xC7
    PTEW PGL0, 1, PA_AD, 0x07         // A/D clear
    PTEW PGL0, 2, PA_C1, 0xCB         // RX
    li t1, PA_P1
    li t2, 0x1111
    sd t2, 0(t1)
    li t1, PA_P2
    li t2, 0x2222
    sd t2, 0(t1)
    li t1, PA_C1
    li t2, 0x00100513                 // addi a0, x0, 1
    sw t2, 0(t1)
    li t2, 0x00008067                 // ret
    sw t2, 4(t1)
    li t1, PA_C2
    li t2, 0x00200513                 // addi a0, x0, 2
    sw t2, 0(t1)
    li t2, 0x00008067
    sw t2, 4(t1)
    fence.i
    li t1, 8
    slli t1, t1, 60
    ori t1, t1, PGROOT >> 12
    csrw satp, t1
    sfence.vma
    la t1, s_main
    csrw mepc, t1
    li t1, (1 << 11)
    csrs mstatus, t1
    mret

s_main:
    // 1
    li t0, 1
    li t1, VA_D
    ld t2, 0(t1)
    li t3, 0x1111
    bne t2, t3, fail_s

    // 2: rewrite L0[0] -> P2 (the store stays dirty in the D$).
    li t0, 2
    li t1, PA_P2
    srli t1, t1, 2
    ori t1, t1, 0xC7
    li t2, PGL0
    sd t1, 0(t2)
    sfence.vma
    li t1, VA_D
    ld t2, 0(t1)
    li t3, 0x2222
    bne t2, t3, fail_s

    // 3: hardware A, then D, visible to loads of the PTE.
    li t0, 3
    li t1, VA_AD
    ld t2, 0(t1)
    li t4, PGL0 + 8
    ld t5, 0(t4)
    andi t6, t5, 0x40
    beqz t6, fail_s                   // A set by the walker
    andi t6, t5, 0x80
    bnez t6, fail_s                   // D still clear
    li t2, 0x3333
    sd t2, 0(t1)
    ld t5, 0(t4)
    andi t6, t5, 0x80
    beqz t6, fail_s                   // D set by the store's walk
    li t1, PA_AD
    ld t3, 0(t1)
    bne t3, t2, fail_s

    // 4: code page C1 -> C2.
    li t0, 4
    li t1, VA_C
    jalr ra, 0(t1)
    li t3, 1
    bne a0, t3, fail_s
    li t1, PA_C2
    srli t1, t1, 2
    ori t1, t1, 0xCB
    li t2, PGL0 + 16
    sd t1, 0(t2)
    sfence.vma
    li t1, VA_C
    jalr ra, 0(t1)
    li t3, 2
    bne a0, t3, fail_s

    // 5: L0[0] -> P1 again, evict the PTE's line (8 stores
    //    aliasing its D$ set), then SFENCE and reload.
    li t0, 5
    li t1, PA_P1
    srli t1, t1, 2
    ori t1, t1, 0xC7
    li t2, PGL0
    sd t1, 0(t2)
    li t3, 8
    li t4, PGL0
1:  li t5, D_WAY_BYTES
    add t4, t4, t5
    sd t3, 0(t4)
    addi t3, t3, -1
    bnez t3, 1b
    sfence.vma
    li t1, VA_D
    ld t2, 0(t1)
    li t3, 0x1111
    bne t2, t3, fail_s

    li a7, 0
    ecall
fail_s:
    li a7, 1
    ecall

handler_m:
    csrr t1, mcause
    li t2, 9                          // ecall from S
    bne t1, t2, fail
    bnez a7, fail
    li t1, 0x10000000
    sd x0, 0(t1)
1:  j 1b
fail:
    li t1, 0x10000000
    sd t0, 0(t1)
1:  j 1b
