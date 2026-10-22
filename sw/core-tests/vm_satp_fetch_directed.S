// Instruction fetch right after csrw satp (no SFENCE.VMA): which of
// the following instructions run under the old and which under the
// new translation (#53 review, FPGA_TIMING fetch page register).
// The priv spec has satp MODE/ASID changes take effect immediately.
//  a: S runs Bare at PA page C and switches to table T, where VA C
//     maps to page C2 holding the same code with other immediates.
//  b: the same switch to table U, where VA C is unmapped: the next
//     fetch faults (12); s3 counts the instructions run before it.
//  c: running from C2 through VA C under T, switch back to Bare.
//  d: as a, but the csrw is the last word of its fetch pair.
// Results go to res (dumped by CORE_TB_DUMP for the cross-check);
// the test passes once every variant has run.
    .option norvc
    .text
    .globl _start

.equ EXIT,     0x10000000
.equ T_ROOT,   0x100000
.equ T_L1,     0x101000
.equ T_L0,     0x102000
.equ U_ROOT,   0x103000
.equ U_L1,     0x104000
.equ U_L0,     0x105000

// The switch body: identical layout in both pages, value v.
.macro BODY v
    csrw satp, s4               // +0
    li a0, \v                   // +4
    li a1, \v
    li a2, \v
    li a3, \v
    li a4, \v
    li a5, \v
    li a6, \v
    li a7, \v
    addi s3, s3, \v
    addi s3, s3, \v
    jalr x0, 0(s5)              // +44
    .balign 64
    nop                         // +64 (d: csrw at +68)
    csrw satp, s4
    li a0, \v
    li a1, \v
    li a2, \v
    li a3, \v
    li a4, \v
    li a5, \v
    li a6, \v
    li a7, \v
    jalr x0, 0(s5)
.endm
.macro SAVE off
    la t1, res + \off
    sd a0, 0(t1)
    sd a1, 8(t1)
    sd a2, 16(t1)
    sd a3, 24(t1)
    sd a4, 32(t1)
    sd a5, 40(t1)
    sd a6, 48(t1)
    sd a7, 56(t1)
.endm
.macro CLR
    li a0, 0
    li a1, 0
    li a2, 0
    li a3, 0
    li a4, 0
    li a5, 0
    li a6, 0
    li a7, 0
    li s3, 0
.endm

_start:
    la sp, stack_top
    la t1, m_trap
    csrw mtvec, t1
    la t1, s_trap
    csrw stvec, t1
    li t1, -1
    csrw pmpaddr15, t1
    li t1, 0x1f
    slli t1, t1, 56
    csrw pmpcfg2, t1
    li t1, T_ROOT
    li t2, U_L0 + 0x1000
1:  sd x0, 0(t1)
    addi t1, t1, 8
    blt t1, t2, 1b
    // T and U: 4K identity for the first 2M (RWX, A/D); T maps
    // page C to C2, U leaves page C unmapped.
    li t1, (T_L1 >> 2) | 1
    li t2, T_ROOT
    sd t1, 0(t2)
    li t1, (T_L0 >> 2) | 1
    li t2, T_L1
    sd t1, 0(t2)
    li t1, (U_L1 >> 2) | 1
    li t2, U_ROOT
    sd t1, 0(t2)
    li t1, (U_L0 >> 2) | 1
    li t2, U_L1
    sd t1, 0(t2)
    li t1, 0
    li t3, 512
1:  slli t2, t1, 10
    ori t2, t2, 0xCF
    slli t4, t1, 3
    li t5, T_L0
    add t5, t5, t4
    sd t2, 0(t5)
    li t5, U_L0
    add t5, t5, t4
    sd t2, 0(t5)
    addi t1, t1, 1
    blt t1, t3, 1b
    la t1, page_c
    srli t1, t1, 12
    slli t4, t1, 3
    la t2, page_c2
    srli t2, t2, 2
    ori t2, t2, 0xCF
    li t5, T_L0
    add t5, t5, t4
    sd t2, 0(t5)
    li t5, U_L0
    add t5, t5, t4
    sd x0, 0(t5)
    li t1, (1 << 12)            // delegate instruction page faults
    csrw medeleg, t1
    csrw satp, x0
    la t1, s_main
    csrw mepc, t1
    li t1, (3 << 11)
    csrc mstatus, t1
    li t1, (1 << 11)
    csrs mstatus, t1
    mret

s_main:
    li t1, 8
    slli t1, t1, 60
    ori s6, t1, T_ROOT >> 12    // satp T (ASID 0)
    ori s7, t1, U_ROOT >> 12    // satp U
    li s8, 1
    slli s8, s8, 44
    or s8, s8, s6               // satp T, ASID 1 (for c)
    // a: Bare -> T at page C.
    CLR
    mv s4, s6
    la s5, after_a
    la t1, page_c
    jalr x0, 0(t1)
after_a:
    SAVE 0
    la t1, res + 192
    sd s3, 0(t1)
    csrw satp, x0
    sfence.vma
    // b: Bare -> U (page C unmapped).
    CLR
    mv s4, s7
    la s5, after_b
    la t1, s_resume
    sd s5, 0(t1)
    la t1, page_c
    jalr x0, 0(t1)
after_b:
    SAVE 64
    la t1, res + 200
    sd s3, 0(t1)
    la t2, s_info
    ld t3, 0(t2)
    sd t3, 8(t1)                // scause (0: no fault)
    ld t3, 8(t2)
    la t4, page_c
    sub t3, t3, t4
    sd t3, 16(t1)               // sepc - C
    csrw satp, x0
    sfence.vma
    // c: under T (ASID 1) run C2 at VA C, switch to Bare.
    CLR
    csrw satp, s8
    sfence.vma
    li s4, 0
    la s5, after_c
    la t1, page_c
    jalr x0, 0(t1)
after_c:
    SAVE 128
    la t1, res + 224
    sd s3, 0(t1)
    csrw satp, x0
    sfence.vma
    // d: as a, the csrw at +68.
    CLR
    mv s4, s6
    la s5, after_d
    la t1, page_c + 68
    jalr x0, 0(t1)
after_d:
    csrw satp, x0
    sfence.vma
    la t1, res + 232
    sd a0, 0(t1)
    sd a1, 8(t1)
    sd a2, 16(t1)
    sd a3, 24(t1)
    ecall                       // to M: pass
1:  j 1b

m_trap:
    csrr t1, mcause
    li t2, 9
    bne t1, t2, 1f
    li t1, EXIT
    sd x0, 0(t1)
1:  li t1, EXIT
    li t2, 99
    sd t2, 0(t1)
2:  j 2b

s_trap:
    la t1, s_info
    csrr t2, scause
    sd t2, 0(t1)
    csrr t2, sepc
    sd t2, 8(t1)
    la t1, s_resume
    ld t2, 0(t1)
    sd x0, 0(t1)
    csrw sepc, t2
    csrw satp, x0               // back to Bare for the resume
    sfence.vma
    sret

    .balign 4096
page_c:
    BODY 1
    .balign 4096
page_c2:
    BODY 2
    .balign 4096

    .data
    .align 6
res:         .skip 8 * 40
s_info:      .quad 0, 0
s_resume:    .quad 0
    .align 4
stack:       .skip 1024
stack_top:
