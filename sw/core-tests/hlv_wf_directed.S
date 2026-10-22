// A recorded data walk fault must not leak into a later access of
// the same VA in another translation context (#53 review). In HS, a
// fault-only-first load trims vl at VA P (P unmapped by satp: the
// walk faults and is recorded, no trap); an HLV.D of the same VA P
// (guest: vsatp Bare, G-stage maps GPA P to a page of 0x6666) must
// then load 0x6666 without a trap.
//  1: vle64ff (trim at P), addi, hlv.d P.
//  2: vle64ff (trim at P), hlv.d P. FPGA_TIMING looks the HLV up in
//     EX in the cycle after the trim, while the walk-fault record
//     (matched by VA only) is still live; that capture must not
//     take the record's load page fault (13, tval P). Main looks the
//     HLV up in MEM a cycle later, after the record is dropped, and
//     loads 0x6666.
// Any M trap is logged (mcause, mtval at res+32/40, count at res+48)
// and skipped. t0 = variant; exit store 0 = pass.
    .option arch, +v
    .option arch, +h
    .option norvc
    .text
    .globl _start

.equ EXIT,   0x10000000
.equ ROOT,   0x100000
.equ L1,     0x101000
.equ L0,     0x102000
.equ VA_M,   0x200000           // HS: mapped (PA 0x180000)
.equ VA_P,   0x201000           // HS: unmapped; guest GPA -> hpage

_start:
    la sp, stack_top
    la t1, m_trap
    csrw mtvec, t1
    li t1, -1
    csrw pmpaddr15, t1
    li t1, 0x1f
    slli t1, t1, 56
    csrw pmpcfg2, t1
    li t1, (1 << 9)             // VS = Initial
    csrs mstatus, t1
    li t1, ROOT
    li t2, L0 + 0x1000
1:  sd x0, 0(t1)
    addi t1, t1, 8
    blt t1, t2, 1b
    li t1, 0x180000
    li t2, 0x181000
1:  sd t1, 0(t1)
    addi t1, t1, 8
    blt t1, t2, 1b
    // HS tables: 2M identity, VA_M -> 0x180000, VA_P unmapped.
    li t1, (L1 >> 2) | 1
    li t2, ROOT
    sd t1, 0(t2)
    li t1, 0xCF
    li t2, L1
    sd t1, 0(t2)
    li t1, (L0 >> 2) | 1
    sd t1, 8(t2)
    li t1, (0x180000 >> 2) | 0xC7
    li t2, L0
    sd t1, 0(t2)
    // G-stage (Sv39x4): GPA 0..2M identity (U RWX), GPA VA_P -> hpage.
    la t1, g_root
    la t2, g_l1
    srli t2, t2, 2
    ori t2, t2, 1
    sd t2, 0(t1)
    la t1, g_l1
    li t2, 0xDF
    sd t2, 0(t1)
    la t2, g_l0
    srli t2, t2, 2
    ori t2, t2, 1
    sd t2, 8(t1)
    la t1, g_l0
    la t2, hpage
    srli t2, t2, 2
    ori t2, t2, 0xD7
    sd t2, 8(t1)
    la t1, g_root
    srli t1, t1, 12
    li t2, 0x8001000000000000   // Sv39x4, VMID 1
    or t1, t1, t2
    csrw hgatp, t1
    csrw vsatp, x0
    li t1, (1 << 8)             // hstatus.SPVP: HLV as VS
    csrs hstatus, t1
    li t1, 8
    slli t1, t1, 60
    ori t1, t1, ROOT >> 12
    csrw satp, t1
    sfence.vma
    hfence.gvma
    la t1, hs_main
    csrw mepc, t1
    li t1, (3 << 11)
    csrc mstatus, t1
    li t1, (1 << 11)
    csrs mstatus, t1
    mret

hs_main:
    la s0, res
    li s1, VA_M + 0xFF0
    li s2, VA_P
    // 1: trim, one ALU op, HLV.
    li t0, 1
    vsetivli x0, 4, e64, m1, tu, mu
    li a0, 0
    sd x0, 0(s0)
    vle64ff.v v8, (s1)
    addi a5, x0, 1
    hlv.d a0, (s2)
    sd a0, 8(s0)
    csrr a1, vl
    sd a1, 16(s0)
    // 2: trim, HLV right after.
    li t0, 2
    vsetivli x0, 4, e64, m1, tu, mu
    li a2, 0
    vle64ff.v v8, (s1)
    hlv.d a2, (s2)
    sd a2, 24(s0)
    // Checks (via M: EXIT is not mapped in HS).
    li a7, 0
    li a3, 0x6666
    beq a0, a3, 1f
    li a7, 1
    j 3f
1:  beq a2, a3, 1f
    li a7, 2
    j 3f
1:  ld a4, 48(s0)               // no trap at all
    beqz a4, 3f
    li a7, 3
3:  ecall
2:  j 2b

// M: an HS ecall ends the test with a7; any other trap is logged
// (mcause, mtval at res+32/40, count at res+48) and skipped.
m_trap:
    csrr t1, mcause
    li t2, 9
    bne t1, t2, 1f
    li t1, EXIT
    sd a7, 0(t1)
2:  j 2b
1:  la t2, res
    sd t1, 32(t2)
    csrr t1, mtval
    sd t1, 40(t2)
    ld t1, 48(t2)
    addi t1, t1, 1
    sd t1, 48(t2)
    csrr t1, mepc
    addi t1, t1, 4
    csrw mepc, t1
    mret

    .data
    .balign 64
res:   .skip 64
stack: .skip 256
stack_top:
    .balign 16384
g_root: .skip 16384
g_l1:   .skip 4096
g_l0:   .skip 4096
hpage:
    .rept 512
    .quad 0x6666
    .endr
