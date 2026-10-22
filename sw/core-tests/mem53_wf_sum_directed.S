// Recorded walk fault vs a following SUM/MXR change (#53 review).
// A fault-only-first load whose element 1 page-faults in the walker
// trims vl without trapping, so the MMU's recorded walk fault for
// that VA survives the instruction. sstatus.SUM/MXR changes take
// effect immediately (priv spec, SFENCE.VMA notes), so a later load
// of the same VA after setting SUM (MXR) must not reuse that fault.
// The body runs in S with Sv39; traps go to M, which records
// mcause/mtval and skips the instruction. The front end fetches at
// most one instruction per two cycles, so a bubble normally trails
// the vector load; a TLB-missing load right before it stalls MEM
// while ID and the fetch buffer fill, so the instructions after the
// vector load run back to back (as they would after any stall).
//  1: FF trim on a U page (SUM=0), addi a1 = that VA, csrs SUM,
//     ld from it: must load, no trap.
//  2: the same with the CSR right after the FF load (control).
//  3: FF trim on an X-only page (MXR=0), addi, csrs MXR, ld.
//  4: unmasked element 0 of an FF load faults (traps), then the
//     same VA after SUM is set loads (control for the trap path).
// Convention: t0 = test number, exit store 0 = pass.
    .option arch, +v
    .option norvc
    .text
    .globl _start

.equ PGROOT, 0x100000
.equ PGL1,   0x101000
.equ PGL0,   0x102000
.equ VA_S,   0x200000          // -> PA 0x180000 RW (S page)
.equ VA_U,   0x201000          // -> PA 0x181000 RW U
.equ VA_S2,  0x202000          // -> PA 0x182000 RW (S page)
.equ VA_X,   0x203000          // -> PA 0x183000 X only
.equ VA_U2,  0x204000          // -> PA 0x184000 RW U

.macro PTEW tbl, idx, pa, flags
    li t1, \pa
    srli t1, t1, 2
    ori t1, t1, \flags
    li t2, \tbl + \idx * 8
    sd t1, 0(t2)
.endm

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
    li t1, (1 << 9)                // VS = Initial
    csrs mstatus, t1
    li t1, PGROOT
    li t2, PGROOT + 0x3000
1:  sd x0, 0(t1)
    addi t1, t1, 8
    blt t1, t2, 1b
    // Flags: V1 R2 W4 X8 U16 G32 A64 D128.
    PTEW PGROOT, 0, PGL1, 0x01
    PTEW PGL1, 0, 0x000000, 0xCF   // 2M identity RWX (code, data)
    PTEW PGL1, 1, PGL0, 0x01
    PTEW PGL0, 0, 0x180000, 0xC7
    PTEW PGL0, 1, 0x181000, 0xD7
    PTEW PGL0, 2, 0x182000, 0xC7
    PTEW PGL0, 3, 0x183000, 0x49
    PTEW PGL0, 4, 0x184000, 0xD7
    // Payload words.
    li t1, 0x180FF8
    li t2, 0x5100
    sd t2, 0(t1)
    li t1, 0x181000
    li t2, 0x5101
    sd t2, 0(t1)
    li t1, 0x182FF8
    li t2, 0x5200
    sd t2, 0(t1)
    li t1, 0x183000
    li t2, 0x5201
    sd t2, 0(t1)
    li t1, 0x184000
    li t2, 0x5401
    sd t2, 0(t1)
    li t1, 8
    slli t1, t1, 60
    ori t1, t1, PGROOT >> 12
    csrw satp, t1
    sfence.vma
    la t1, s_main
    csrw mepc, t1
    li t1, (3 << 11)
    csrc mstatus, t1
    li t1, (1 << 11)               // MPP = S
    csrs mstatus, t1
    mret

// ---- S-mode body ----------------------------------------------
s_main:
    // 1: FF trim at VA_U, address in MEM, then SUM, then the load.
    li t0, 1
    li s1, 2                       // two passes: the first warms the I$
1:  call clear_trap
    li a0, VA_U - 8
    li s6, VA_S2 + 0x800
    vsetivli x0, 2, e64, m1, tu, mu
    li t2, (1 << 18)
    li a3, 0
    sfence.vma                     // element 1 must miss in the TLB
    .rept 8
    nop                            // front end refilled after the sfence
    .endr
    ld s5, 0(s6)                   // TLB miss: MEM stalls while the
                                   // front end fills, so what follows
                                   // the vector load runs back to back
    vle64ff.v v1, (a0)
    addi a1, a0, 8                 // = VA_U (MEM keeps that VA)
    csrs sstatus, t2               // SUM = 1
    ld a3, 0(a1)
    csrc sstatus, t2
    csrr a4, vl
    li a5, 1
    bne a4, a5, fail_s             // trimmed to 1
    call check_no_trap
    li a5, 0x5101
    bne a3, a5, fail_s
    addi s1, s1, -1
    bnez s1, 1b

    // 2: control, CSR directly after the FF load.
    li t0, 2
    call clear_trap
    li a0, VA_U - 8
    li a1, VA_U
    vsetivli x0, 2, e64, m1, tu, mu
    li t2, (1 << 18)
    sfence.vma
    vle64ff.v v1, (a0)
    csrs sstatus, t2
    ld a3, 0(a1)
    csrc sstatus, t2
    call check_no_trap
    li a5, 0x5101
    bne a3, a5, fail_s

    // 3: X-only page, MXR.
    li t0, 3
    li s1, 2
1:  call clear_trap
    li a0, VA_X - 8
    li s6, VA_S + 0x800
    vsetivli x0, 2, e64, m1, tu, mu
    li t2, (1 << 19)
    li a3, 0
    sfence.vma
    .rept 8
    nop
    .endr
    ld s5, 0(s6)
    vle64ff.v v1, (a0)
    addi a1, a0, 8                 // = VA_X
    csrs sstatus, t2               // MXR = 1
    ld a3, 0(a1)
    csrc sstatus, t2
    csrr a4, vl
    li a5, 1
    bne a4, a5, fail_s
    call check_no_trap
    li a5, 0x5201
    bne a3, a5, fail_s
    addi s1, s1, -1
    bnez s1, 1b

    // 4: element 0 faults (trap, cause 13), then SUM and a load.
    li t0, 4
    call clear_trap
    li a0, VA_U2
    vsetivli x0, 2, e64, m1, tu, mu
    li t2, (1 << 18)
    sfence.vma
    vle64ff.v v1, (a0)             // traps, handler skips it
    addi a1, a0, 0
    csrs sstatus, t2
    ld a3, 0(a1)
    csrc sstatus, t2
    la a4, trap_cause
    ld a5, 0(a4)
    li a6, 13
    bne a5, a6, fail_s
    sd x0, 0(a4)
    call check_no_trap
    li a5, 0x5401
    bne a3, a5, fail_s

    li a0, 0
    ecall                          // pass
1:  j 1b
fail_s:
    li a0, 1
    ecall
1:  j 1b

clear_trap:
    la a4, trap_cause
    sd x0, 0(a4)
    sd x0, 8(a4)
    ret
check_no_trap:
    la a4, trap_cause
    ld a5, 0(a4)
    bnez a5, fail_s
    ret

// ---- M handler ------------------------------------------------
handler_m:
    csrrw sp, mscratch, sp
    sd t1, 0(sp)
    sd t2, 8(sp)
    csrr t1, mcause
    li t2, 9
    beq t1, t2, m_exit             // ecall from S: report
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
m_exit:
    li t1, 0x10000000
    beqz a0, 1f
    sd t0, 0(t1)
2:  j 2b
1:  sd x0, 0(t1)
3:  j 3b

    .data
    .align 3
trap_cause: .quad 0
trap_tval:  .quad 0
    .align 4
main_stack:  .skip 2048
main_stack_top:
trap_stack:  .skip 1024
trap_stack_top:
