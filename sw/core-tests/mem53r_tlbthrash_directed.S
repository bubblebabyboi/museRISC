// TLB thrash with 4K pages everywhere (#53 review round 3, memory
// lens): 48 data pages and the code, data, stack and table pages all
// through 4K leaves, so the 32-entry TLB refills on nearly every
// access and fetch walks interleave with data walks. With FPGA_TIMING
// every TLB fill invalidates the registered data lookup for a cycle
// (replay) and the fetch page register outlives the entry it came
// from. The loop visits the data pages in a permuted order and per
// page does a load and a store of word 0, an AMOADD of word 1, an
// LR/SC increment of word 2 and a two-element vector load + store
// (0xFF0 -> 0x7F0); the visit and LR/SC helpers live on other code
// pages. Four passes: 0 plain, 1 after SFENCE.VMA, 2 after every data
// PTE lost A and D (A/D re-walks, PTE write-backs), 3 plain.
//  1: the sum of the loaded words.
//  2: every word 0 = 3 idx + 4, word 1 = 4, word 2 = 4, no SC failed.
//  3: the vector copies.
//  4: every data PTE has A and D again.
// t0 = check number; exit store 0 = pass.
    .option arch, +v
    .option norvc
    .text
    .globl _start

.equ EXIT,  0x10000000
.equ ROOT,  0x100000
.equ L1,    0x101000
.equ L0C,   0x102000            // identity 4K leaves, VA 0..2M
.equ L0D,   0x103000            // VA 0x200000 + i*4K -> PA 0x180000 + i*4K
.equ DVA,   0x200000
.equ DPA,   0x180000
.equ NPG,   48

_start:
    la sp, main_stack_top
    la t1, trap_stack_top
    csrw mscratch, t1
    la t1, handler_m
    csrw mtvec, t1
    li t1, (1 << 9)
    csrs mstatus, t1
    li t1, -1
    csrw pmpaddr15, t1
    li t1, 0x1f
    slli t1, t1, 56
    csrw pmpcfg2, t1
    // tables
    li t1, ROOT
    li t2, ROOT + 0x4000
1:  sd x0, 0(t1)
    addi t1, t1, 8
    blt t1, t2, 1b
    li t1, (L1 >> 2) | 1
    li t2, ROOT
    sd t1, 0(t2)
    li t1, (L0C >> 2) | 1
    li t2, L1
    sd t1, 0(t2)
    li t1, (L0D >> 2) | 1
    sd t1, 8(t2)
    li t1, L0C
    li t2, 0xCF
    li a0, 512
1:  sd t2, 0(t1)
    li a1, 1 << 10
    add t2, t2, a1
    addi t1, t1, 8
    addi a0, a0, -1
    bnez a0, 1b
    li t1, L0D
    li t2, (DPA >> 2) | 0xC7
    li a0, NPG
1:  sd t2, 0(t1)
    li a1, 1 << 10
    add t2, t2, a1
    addi t1, t1, 8
    addi a0, a0, -1
    bnez a0, 1b
    // data: page i: word0 = 3i, word1 = word2 = 0, +0xFF0 = 5i+1,
    // +0xFF8 = 7i+2, +0x7F0/+0x7F8 = 0
    li a0, 0
1:  slli t1, a0, 12
    li t2, DPA
    add t1, t1, t2
    li t2, 3
    mul t2, t2, a0
    sd t2, 0(t1)
    sd x0, 8(t1)
    sd x0, 16(t1)
    li t2, 5
    mul t2, t2, a0
    addi t2, t2, 1
    li a1, 0xFF0
    add a1, a1, t1
    sd t2, 0(a1)
    li t2, 7
    mul t2, t2, a0
    addi t2, t2, 2
    sd t2, 8(a1)
    li a1, 0x7F0
    add a1, a1, t1
    sd x0, 0(a1)
    sd x0, 8(a1)
    addi a0, a0, 1
    li t2, NPG
    blt a0, t2, 1b
    li t1, 8
    slli t1, t1, 60
    ori t1, t1, ROOT >> 12
    csrw satp, t1
    sfence.vma
    la t1, s_main
    csrw mepc, t1
    li t1, (3 << 11)
    csrc mstatus, t1
    li t1, (1 << 11)
    csrs mstatus, t1
    mret

s_main:
    li s1, 0                    // pass
    li s4, 0                    // sum of loads
    li s5, 1
    li s6, 0                    // SC failures
pass_loop:
    li t1, 1
    bne s1, t1, 1f
    sfence.vma
1:  li t1, 2
    bne s1, t1, 2f
    // pass 2: drop A and D from every data PTE (identity view of L0D)
    li t1, L0D
    li a0, NPG
3:  ld t2, 0(t1)
    andi t2, t2, ~0xC0
    sd t2, 0(t1)
    addi t1, t1, 8
    addi a0, a0, -1
    bnez a0, 3b
    sfence.vma
2:  li s2, NPG                  // pages to visit
    li s3, 0                    // idx
visit_loop:
    addi s3, s3, 19
    li t1, NPG
    blt s3, t1, 1f
    sub s3, s3, t1
1:  slli a0, s3, 12
    li t1, DVA
    add a0, a0, t1              // page VA
    jal ra, visit_b
    jal ra, visit_c
    addi s2, s2, -1
    bnez s2, visit_loop
    addi s1, s1, 1
    li t1, 4
    blt s1, t1, pass_loop
    j check

check:
    // 1: sum = 4 * sum(3i) + 48 * (0+1+2+3)
    li t0, 1
    li t1, 4 * 3 * (NPG * (NPG - 1) / 2) + NPG * 6
    bne s4, t1, fail_s
    // 2: words
    li t0, 2
    bnez s6, fail_s
    li a0, 0
1:  slli a1, a0, 12
    li t1, DVA
    add a1, a1, t1
    ld t2, 0(a1)
    li t3, 3
    mul t3, t3, a0
    addi t3, t3, 4
    bne t2, t3, fail_s
    ld t2, 8(a1)
    li t3, 4
    bne t2, t3, fail_s
    ld t2, 16(a1)
    bne t2, t3, fail_s
    // 3: vector copies
    li t0, 3
    li t1, 0x7F0
    add t1, t1, a1
    ld t2, 0(t1)
    li t3, 5
    mul t3, t3, a0
    addi t3, t3, 1
    bne t2, t3, fail_s
    ld t2, 8(t1)
    li t3, 7
    mul t3, t3, a0
    addi t3, t3, 2
    bne t2, t3, fail_s
    li t0, 2
    addi a0, a0, 1
    li t1, NPG
    blt a0, t1, 1b
    // 4: A and D back on every data PTE
    li t0, 4
    li t1, L0D
    li a0, NPG
1:  ld t2, 0(t1)
    andi t2, t2, 0xC0
    li t3, 0xC0
    bne t2, t3, fail_s
    addi t1, t1, 8
    addi a0, a0, -1
    bnez a0, 1b
    li a0, 0
    ecall
1:  j 1b
fail_s:
    li a0, 1
    ecall
1:  j 1b

    .balign 4096
// visit_b(a0 = page VA): load/store word 0, AMOADD word 1, vector
// copy 0xFF0 -> 0x7F0 (2 x 64-bit).
visit_b:
    ld t1, 0(a0)
    add s4, s4, t1
    add t1, t1, s5
    sd t1, 0(a0)
    addi t2, a0, 8
    amoadd.d x0, s5, (t2)
    vsetivli x0, 2, e64, m1, ta, ma
    li t2, 0xFF0
    add t2, t2, a0
    vle64.v v8, (t2)
    li t2, 0x7F0
    add t2, t2, a0
    vse64.v v8, (t2)
    jalr x0, 0(ra)

    .balign 4096
// visit_c(a0 = page VA): LR/SC increment of word 2.
visit_c:
    addi t2, a0, 16
1:  lr.d t1, (t2)
    addi t1, t1, 1
    sc.d t3, t1, (t2)
    beqz t3, 2f
    addi s6, s6, 1
    j 1b
2:  jalr x0, 0(ra)

    .balign 4096
// M: the final ECALL ends the test (a0 = 0 pass); any other trap
// fails with (t0 | mcause << 8) after logging mepc/mtval.
handler_m:
    csrrw sp, mscratch, sp
    csrr t1, mcause
    li t2, 9
    bne t1, t2, 2f
    li t1, EXIT
    bnez a0, 3f
    sd x0, 0(t1)
1:  j 1b
3:  sd t0, 0(t1)
1:  j 1b
2:  la t2, m_info
    sd t1, 0(t2)
    csrr t3, mepc
    sd t3, 8(t2)
    csrr t3, mtval
    sd t3, 16(t2)
    slli t1, t1, 8
    or t1, t1, t0
    ori t1, t1, 0x80
    li t2, EXIT
    sd t1, 0(t2)
1:  j 1b

    .data
    .align 3
m_info:      .quad 0, 0, 0
    .align 4
main_stack:  .skip 1024
main_stack_top:
trap_stack:  .skip 1024
trap_stack_top:
