// Recorded walk fault vs a following access in another
// translation regime (#53 review). M-mode with MPRV=1, MPP=S runs a
// fault-only-first load through satp; its element 1 (a U page, SUM=0)
// page-faults in the walker and trims vl, so the walk-fault record for
// that VA outlives the instruction. An HLV.D of the same numeric VA
// translates through vsatp (Bare) and hgatp (identity G-stage), where
// it is valid: it must load, not take the satp-regime fault.
//  1: FF trim, then HLV.D of the trimmed VA (front end leaves its
//     usual one-cycle gap between the two).
//  2: the same with one instruction in between.
//  3: HLV.D of that VA with no FF load before it (control).
//  4: FF trim, then a plain MPRV load of the same VA: faults (13).
// Traps go to M, which records mcause, clears MPRV (MRET would leave
// MPP=U) and skips the instruction. t0 = test number, exit 0 = pass.
    .option arch, +v, +h
    .option norvc
    .text
    .globl _start

.equ PGROOT, 0x100000
.equ PGL1,   0x101000
.equ PGL0,   0x102000
.equ GROOT,  0x110000          // hgatp root (16 KiB aligned)
.equ VA_S,   0x200000          // satp: -> PA 0x180000 RW
.equ VA_U,   0x201000          // satp: -> PA 0x181000 RW U
                               // hgatp: GPA 0x201000 -> PA 0x201000

.macro PTEW tbl, idx, pa, flags
    li t1, \pa
    srli t1, t1, 2
    ori t1, t1, \flags
    li t2, \tbl + \idx * 8
    sd t1, 0(t2)
.endm

.macro MPRV_S                    // data accesses translate as HS-mode S
    li t1, (3 << 11)
    csrc mstatus, t1
    li t1, (1 << 17) | (1 << 11)
    csrs mstatus, t1
.endm
.macro MPRV_OFF
    li t1, (1 << 17)
    csrc mstatus, t1
.endm

_start:
    la sp, main_stack_top
    la t1, trap_stack_top
    addi t1, t1, -64
    csrw mscratch, t1
    la t1, handler_m
    csrw mtvec, t1
    li t0, 1
    csrr t1, misa
    li t2, (1 << 7)
    and t1, t1, t2
    beqz t1, fail                  // misa.H
    li t1, -1                      // PMP catch-all RWX for S/VS
    csrw pmpaddr15, t1
    li t1, 0x1f
    slli t1, t1, 56
    csrw pmpcfg2, t1
    li t1, (1 << 9)                // VS = Initial
    csrs mstatus, t1
    li t1, PGROOT
    li t2, PGROOT + 0x3000
1:  sd x0, 0(t1)
    addi t1, t1, 8
    blt t1, t2, 1b
    li t1, GROOT
    li t2, GROOT + 0x4000
1:  sd x0, 0(t1)
    addi t1, t1, 8
    blt t1, t2, 1b
    // satp tables. Flags: V1 R2 W4 X8 U16 G32 A64 D128.
    PTEW PGROOT, 0, PGL1, 0x01
    PTEW PGL1, 0, 0x000000, 0xCF
    PTEW PGL1, 1, PGL0, 0x01
    PTEW PGL0, 0, 0x180000, 0xC7
    PTEW PGL0, 1, 0x181000, 0xD7
    // G-stage: 1 GiB identity leaf, U RWX A D.
    li t1, GROOT
    li t2, 0xDF
    sd t2, 0(t1)
    // Payload.
    li t1, 0x180FF8
    li t2, 0x5100
    sd t2, 0(t1)
    li t1, 0x181000
    li t2, 0x5101
    sd t2, 0(t1)
    li t1, VA_U                    // the PA the HLV reaches
    li t2, 0x6A01
    sd t2, 0(t1)
    li t1, 8
    slli t1, t1, 60
    ori t1, t1, PGROOT >> 12
    csrw satp, t1
    csrw 0x280, x0                 // vsatp Bare
    li t1, 8
    slli t1, t1, 60
    ori t1, t1, GROOT >> 12
    csrw 0x680, t1                 // hgatp Sv39x4, VMID 0
    li t1, (1 << 8)
    csrs 0x600, t1                 // hstatus.SPVP = 1 (HLV as VS)
    sfence.vma
    hfence.gvma

    // 1: FF trim, HLV.D of the same VA right after.
    li t0, 1
    call clear_trap
    li a0, VA_U - 8
    li a1, VA_U
    li a3, 0
    vsetivli x0, 2, e64, m1, tu, mu
    MPRV_S
    sfence.vma                     // element 1 must walk
    .rept 8
    nop
    .endr
    vle64ff.v v1, (a0)
    hlv.d a3, (a1)
    MPRV_OFF
    call check_no_trap
    csrr a4, vl
    li a5, 1
    bne a4, a5, fail
    li a5, 0x6A01
    bne a3, a5, fail

    // 2: one instruction between.
    li t0, 2
    call clear_trap
    li a3, 0
    vsetivli x0, 2, e64, m1, tu, mu
    MPRV_S
    sfence.vma
    .rept 8
    nop
    .endr
    vle64ff.v v1, (a0)
    nop
    hlv.d a3, (a1)
    MPRV_OFF
    call check_no_trap
    li a5, 0x6A01
    bne a3, a5, fail

    // 3: control, no FF load.
    li t0, 3
    call clear_trap
    li a3, 0
    MPRV_S
    sfence.vma
    hlv.d a3, (a1)
    MPRV_OFF
    call check_no_trap
    li a5, 0x6A01
    bne a3, a5, fail

    // 4: FF trim, then a satp-regime load of that VA faults.
    li t0, 4
    call clear_trap
    li a3, 0
    vsetivli x0, 2, e64, m1, tu, mu
    MPRV_S
    sfence.vma
    .rept 8
    nop
    .endr
    vle64ff.v v1, (a0)
    ld a3, 0(a1)                   // traps; handler clears MPRV
    MPRV_OFF
    la a4, trap_cause
    ld a5, 0(a4)
    li a6, 13
    bne a5, a6, fail
    ld a5, 8(a4)
    bne a5, a1, fail               // tval = VA
    bnez a3, fail

pass:
    li t1, 0x10000000
    sd x0, 0(t1)
1:  j 1b
fail:
    la t1, dbg_regs                // a3/a4/a5 at the failure (debug)
    sd a3, 0(t1)
    sd a4, 8(t1)
    sd a5, 16(t1)
    li t1, 0x10000000
    sd t0, 0(t1)
1:  j 1b

clear_trap:
    la a4, trap_cause
    sd x0, 0(a4)
    sd x0, 8(a4)
    ret
check_no_trap:
    la a4, trap_cause
    ld a5, 0(a4)
    bnez a5, fail
    ret

handler_m:
    csrrw sp, mscratch, sp
    sd t1, 0(sp)
    sd t2, 8(sp)
    li t1, (1 << 17)               // MPRV off first: MPP is now M,
    csrc mstatus, t1               // MRET would leave MPP = U
    csrr t1, mcause
    la t2, trap_cause
    sd t1, 0(t2)
    csrr t1, mtval
    sd t1, 8(t2)
    csrr t1, mepc
    addi t1, t1, 4
    csrw mepc, t1
    ld t1, 0(sp)
    ld t2, 8(sp)
    csrrw sp, mscratch, sp
    mret

    .data
    .align 3
trap_cause: .quad 0
trap_tval:  .quad 0
dbg_regs:   .quad 0, 0, 0
    .align 4
main_stack:  .skip 1024
main_stack_top:
trap_stack:  .skip 1024
trap_stack_top:
