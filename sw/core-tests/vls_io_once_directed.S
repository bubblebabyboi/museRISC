// Vector element accesses to an I/O device happen exactly once (#53
// review, side effects with FPGA_TIMING: every element's translation
// comes from the registered D lookup, replayed after each TLB update
// and for every indexed element; a replay must never repeat an
// access). S-mode, Sv39: VA 0x300000 -> the core_tb test device
// (PA 0x20000000: +0 read counter, +8 write count, +0x10 write
// counter), VA 0x301000 unmapped until the handler maps it (mode 1).
// Each case flushes the TLB first.
//  1: vlse64 stride 0, vl 8: elements c..c+7, 8 device reads.
//  2: vluxei64 all indices 0, vl 8: consecutive values, 8 reads.
//  3: vsse64 stride 0 to +0x10, vl 8: write count +8.
//  4: vluxei64, element 5's index on the unmapped page: page fault
//     (13, vstart 5); the handler maps the page and retries: elements
//     5-7 read once each (8 reads in all, values consecutive).
//  5: vluxei64, element 3 misaligned (index 4): 4 at element 3,
//     exactly 3 reads.
//  6: vluxei64 with a timer interrupt somewhere inside (run with
//     --irq-timer-after): still exactly 8 reads and consecutive values.
// Exit value: bit i set = case i failed (0 = pass); 99 = unexpected.
    .option arch, +v
    .option norvc
    .text
    .globl _start
.equ EXIT,   0x10000000
.equ DEV,    0x20000000
.equ PGROOT, 0x100000
.equ PGL1,   0x101000
.equ PGL0,   0x102000
.equ VA_D,   0x300000
.equ VA_D2,  0x301000

.macro FAILIF br, ra, rb, bit
    \br \ra, \rb, 1f
    j 2f
1:  li t4, 1 << \bit
    or s11, s11, t4
2:
.endm
// Device reads since s9 (re-armed) = \n.
.macro READS n, bit
    li t1, VA_D
    ld t2, 0(t1)                 // one more read: returns the count
    sub t2, t2, s9
    li t3, \n
    FAILIF bne, t2, t3, \bit
    li t1, VA_D
    ld s9, 0(t1)                 // re-arm (count after this read = s9 + 1)
    addi s9, s9, 1
.endm
// v1[0..7] consecutive from v1[0].
.macro CONSEC bit
    vmv.x.s t5, v1
    li t6, 1
7:  vslidedown.vx v2, v1, t6
    vmv.x.s t3, v2
    add t2, t5, t6
    FAILIF bne, t3, t2, \bit
    addi t6, t6, 1
    li t3, 8
    blt t6, t3, 7b
.endm

_start:
    la sp, stack_top
    la t1, trap_stack_top
    csrw mscratch, t1
    csrw sscratch, t1
    la t1, handler_m
    csrw mtvec, t1
    la t1, handler_s
    csrw stvec, t1
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
    li t2, PGROOT
    li t1, (PGL1 >> 2) | 1
    sd t1, 0(t2)
    li t2, PGL1
    li t1, 0xEF                  // VA 0..2M identity RWX G A D
    sd t1, 0(t2)
    li t1, (PGL0 >> 2) | 1
    sd t1, 8(t2)                 // VA 2M..4M via PGL0
    li t1, (EXIT >> 2) | 0xE7
    li t3, PGL1 + 128 * 8
    sd t1, 0(t3)
    li t2, PGL0 + 256 * 8        // VA 0x300000 -> DEV
    li t1, (DEV >> 2) | 0xC7
    sd t1, 0(t2)
    li t1, (1 << 4) | (1 << 13) | (1 << 15)
    csrw medeleg, t1
    li t1, (8 << 60) | (PGROOT >> 12)
    csrw satp, t1
    sfence.vma
    li t1, (1 << 7)
    csrs mie, t1                 // MTIE (case 6; M handles it)
    la t1, s_main
    csrw mepc, t1
    li t1, (3 << 11)
    csrc mstatus, t1
    li t1, (1 << 11) | (1 << 9)
    csrs mstatus, t1
    mret

s_main:
    li s11, 0
    li t1, VA_D
    ld s9, 0(t1)
    addi s9, s9, 1
    vsetivli x0, 8, e64, m1, ta, ma
    // 1: strided, stride 0
    li a1, VA_D
    sfence.vma
    vlse64.v v1, (a1), x0
    READS 8, 1
    CONSEC 1
    // 2: indexed, all indices 0
    vmv.v.i v10, 0
    sfence.vma
    vluxei64.v v1, (a1), v10
    READS 8, 2
    CONSEC 2
    // 3: strided store to the write counter
    li t1, VA_D
    ld s8, 8(t1)                 // write count before
    li a2, VA_D + 0x10
    sfence.vma
    vsse64.v v1, (a2), x0
    li t1, VA_D
    ld t2, 8(t1)
    sub t2, t2, s8
    li t3, 8
    FAILIF bne, t2, t3, 3
    // 4: element 5 on the unmapped page; the handler maps and retries
    la t1, s_mode
    li t2, 1
    sd t2, 0(t1)
    la a3, idx4
    vle64.v v10, (a3)
    sfence.vma
    vluxei64.v v1, (a1), v10
    la t1, s_mode
    sd x0, 0(t1)
    la t2, s_cause
    ld t1, 0(t2)
    li t3, 13
    FAILIF bne, t1, t3, 4
    ld t1, 16(t2)
    li t3, 5
    FAILIF bne, t1, t3, 4
    READS 8, 4
    CONSEC 4
    // 5: element 3 misaligned
    la a3, idx5
    vle64.v v10, (a3)
    sfence.vma
    la t2, s_cause
    sd x0, 0(t2)
    vluxei64.v v1, (a1), v10
    csrw vstart, x0
    la t2, s_cause
    ld t1, 0(t2)
    li t3, 4
    FAILIF bne, t1, t3, 5
    ld t1, 16(t2)
    li t3, 3
    FAILIF bne, t1, t3, 5
    READS 3, 5
    // 6: indexed loads in a loop (timer interrupt somewhere inside)
    li s7, 40
    vmv.v.i v10, 0
6:  sfence.vma
    vluxei64.v v1, (a1), v10
    READS 8, 6
    CONSEC 6
    addi s7, s7, -1
    bnez s7, 6b
    li t1, EXIT
    sd s11, 0(t1)
1:  j 1b

    .balign 64
handler_m:
    csrrw sp, mscratch, sp      // timer: mask it and return
    sd t1, -8(sp)
    csrr t1, mcause
    bgez t1, 9f
    li t1, (1 << 7)
    csrc mie, t1
    ld t1, -8(sp)
    csrrw sp, mscratch, sp
    mret
9:  li t1, EXIT
    li t2, 99
    sd t2, 0(t1)
1:  j 1b

    .balign 64
handler_s:
    csrrw sp, sscratch, sp
    sd t1, -8(sp)
    sd t2, -16(sp)
    la t2, s_cause
    csrr t1, scause
    sd t1, 0(t2)
    csrr t1, stval
    sd t1, 8(t2)
    csrr t1, vstart
    sd t1, 16(t2)
    la t1, s_mode
    ld t1, 0(t1)
    beqz t1, 1f
    li t1, (DEV >> 2) | 0xC7     // map VA_D2 -> DEV and retry
    li t2, PGL0 + 257 * 8
    sd t1, 0(t2)
    sfence.vma
    j 2f
1:  csrr t1, sepc
    addi t1, t1, 4
    csrw sepc, t1
2:  ld t1, -8(sp)
    ld t2, -16(sp)
    csrrw sp, sscratch, sp
    sret

    .data
    .align 6
idx4:   .dword 0, 0, 0, 0, 0, 0x1000, 0, 0
idx5:   .dword 0, 0, 0, 4, 0, 0, 0, 0
s_cause: .dword 0, 0, 0
s_mode:  .dword 0
    .skip 512
stack_top:
    .skip 512
trap_stack_top:
