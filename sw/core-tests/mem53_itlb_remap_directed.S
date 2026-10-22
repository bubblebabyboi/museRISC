// Code page remapped without SFENCE.VMA while it executes (#53
// review). Until an SFENCE.VMA, a hart may fetch through either the
// old or the new translation (priv spec, SFENCE.VMA notes); both
// physical pages hold the same code, so either is correct.
// S-mode runs a position-independent stub from VA 0x200000 (PA
// 0x180000, RWX, A=1, D=0). The stub rewrites its own leaf PTE to
// point at an identical copy (PA 0x181000), then stores to its own
// page: D=0 makes the store re-walk, which refills the TLB entry for
// that VA with the new PPN while instruction fetch keeps going on
// the page. It then counts 16 instructions and ECALLs to M.
//  1: the ECALL arrives from S with the count intact.
//  2: after SFENCE.VMA in M, a load of PA 0x1817F8 sees the
//     store (it went through the new mapping).
// t0 = test number, exit store 0 = pass.
    .option norvc
    .text
    .globl _start

.equ PGROOT, 0x100000
.equ PGL1,   0x101000
.equ PGL0,   0x102000

_start:
    la sp, main_stack_top
    la t1, trap_stack_top
    addi t1, t1, -64
    csrw mscratch, t1
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
    // root[0] -> L1; L1[0] 2M identity RWX (tables, data);
    // L1[1] -> L0; L0[0] VA 0x200000 -> PA 0x180000 RWX A, D=0.
    li t1, (PGL1 >> 2) | 0x01
    li t2, PGROOT
    sd t1, 0(t2)
    li t1, 0xCF
    li t2, PGL1
    sd t1, 0(t2)
    li t1, (PGL0 >> 2) | 0x01
    sd t1, 8(t2)
    li t1, (0x180000 >> 2) | 0x4F
    li t2, PGL0
    sd t1, 0(t2)
    // Copy the stub to both physical pages.
    la t1, stub
    la t2, stub_end
    li a0, 0x180000
    li a1, 0x181000
1:  lw a2, 0(t1)
    sw a2, 0(a0)
    sw a2, 0(a1)
    addi t1, t1, 4
    addi a0, a0, 4
    addi a1, a1, 4
    blt t1, t2, 1b
    fence.i
    li t1, 8
    slli t1, t1, 60
    ori t1, t1, PGROOT >> 12
    csrw satp, t1
    sfence.vma
    // Stub arguments.
    li a0, PGL0                    // its leaf PTE
    li a1, (0x181000 >> 2) | 0x4F  // the copy, RWX A, D=0
    li a2, 0x7E57
    li a3, 0x200000
    li a4, 0
    li t1, 0x200000
    csrw mepc, t1
    li t1, (3 << 11)
    csrc mstatus, t1
    li t1, (1 << 11)               // MPP = S
    csrs mstatus, t1
    li t0, 1
    mret

stub:
    sd a1, 0(a0)                   // remap own page, no SFENCE
    sd a2, 0x7F8(a3)               // D=0: re-walk refills the entry
    .rept 16
    addi a4, a4, 1
    .endr
    ecall
1:  j 1b
stub_end:

handler_m:
    csrr t1, mcause
    li t2, 9
    bne t1, t2, fail               // only the stub's ECALL from S
    li t1, 16
    bne a4, t1, fail
    li t0, 2
    sfence.vma
    li t1, 0x1817F8                // the store's PA (new mapping)
    ld t2, 0(t1)
    bne t2, a2, fail
pass:
    li t1, 0x10000000
    sd x0, 0(t1)
1:  j 1b
fail:
    li t1, 0x10000000
    sd t0, 0(t1)
1:  j 1b

    .data
    .align 4
main_stack:  .skip 1024
main_stack_top:
trap_stack:  .skip 1024
trap_stack_top:
