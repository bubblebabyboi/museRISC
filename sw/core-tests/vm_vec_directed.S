// Vector loads/stores under Sv39 with page faults (#53 review: the
// FPGA_TIMING vector element translation is looked up while the
// element is sequenced and registered; indexed elements replay).
// Every fault is checked for scause, stval (element address), sepc,
// vstart and the elements written before it; nothing after it runs:
//  1:  vle64 crossing into an unmapped page: element 2 faults
//      (13), elements 0-1 loaded, 2-7 untouched, vstart = 2; then
//      the handler maps the page and the load resumes at vstart.
//  2:  vse64 crossing into a read-only page: element 3 faults (15),
//      elements 0-2 stored, nothing on the read-only page.
//  3:  vluxei64 whose element 2 indexes an unmapped page.
//  4:  vlse64 whose element 2 strides into an unmapped page.
//  5:  vlseg3e32 whose element 2 field 2 is on an unmapped page: no
//      field of element 2 is written, vstart = 2.
//  6:  vle64ff trims vl at an unmapped element 2 without a trap; a
//      scalar load of that VA right after faults (13, stval); a
//      vle64ff faulting on element 0 traps and keeps vl.
//  7:  masked-off elements on an unmapped page do not fault; an
//      active one does.
//  8:  vector store fault followed by a register write, a store and
//      an I/O read: none happens.
//  9:  vstart = 2 skips two elements on an unmapped page.
//  10: TLB-cold strided, indexed (out of order) and unit-stride
//      accesses across five pages, loads and a store.
// t0 = test number; exit store 0 = pass.
    .option arch, +v
    .option norvc
    .text
    .globl _start

.equ EXIT,     0x10000000
.equ ROOT_A,   0x100000
.equ L1_A,     0x101000
.equ L0_A,     0x102000
.equ V_A,      0x200000         // PA 0x180000 RW
.equ V_N,      0x201000         // unmapped until test 1's handler
.equ V_C,      0x202000         // PA 0x182000 RW
.equ V_R,      0x203000         // PA 0x183000 R
.equ V_E,      0x204000         // PA 0x184000 RW
.equ V_N2,     0x205000         // unmapped
.equ V_G,      0x206000         // PA 0x186000 RW
.equ VA_DEV,   0x208000         // PA 0x20000000 (I/O read counter)

.macro PTEW tbl, idx, pa, flags
    li t1, \pa
    srli t1, t1, 2
    ori t1, t1, \flags
    li t2, \tbl + \idx * 8
    sd t1, 0(t2)
.endm
// Last S trap: cause, tval (constant), epc (label), vstart.
.macro CHK_S cause, tval, epc, vst
    la t1, s_cause
    ld t2, 0(t1)
    li t3, \cause
    bne t2, t3, fail_s
    ld t2, 8(t1)
    li t3, \tval
    bne t2, t3, fail_s
    ld t2, 16(t1)
    la t3, \epc
    bne t2, t3, fail_s
    ld t2, 24(t1)
    li t3, \vst
    bne t2, t3, fail_s
.endm
.macro RESUME label
    la t1, \label
    la t2, s_resume
    sd t1, 0(t2)
.endm
// Store vector register vr (e64, 8 elements) to chk.
.macro DUMP64 vr
    vsetivli x0, 8, e64, m1, tu, mu
    csrw vstart, x0
    la t1, chk
    vse64.v \vr, (t1)
.endm
.macro DUMP32 vr
    vsetivli x0, 16, e32, m1, tu, mu
    csrw vstart, x0
    la t1, chk
    vse32.v \vr, (t1)
.endm
// chk[off] == value (64-bit), or 32-bit at byte off.
.macro CHKD off, val
    la t1, chk
    ld t2, \off(t1)
    li t3, \val
    bne t2, t3, fail_s
.endm
.macro CHKW off, val
    la t1, chk
    lwu t2, \off(t1)
    li t3, \val
    bne t2, t3, fail_s
.endm
.macro TRAPS n                  // exactly n traps since s9 was taken
    la t1, s_count
    ld t2, 0(t1)
    sub t2, t2, s9
    li t3, \n
    bne t2, t3, fail_s
.endm
.macro MARK
    la t1, s_count
    ld s9, 0(t1)
.endm

_start:
    la sp, main_stack_top
    la t1, trap_stack_top
    addi t1, t1, -64
    csrw mscratch, t1
    la t1, s_trap_stack_top
    addi t1, t1, -64
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
    li t1, (1 << 9)             // VS = Initial
    csrs mstatus, t1
    li t1, ROOT_A
    li t2, ROOT_A + 0x3000
1:  sd x0, 0(t1)
    addi t1, t1, 8
    blt t1, t2, 1b
    // Data pages: every doubleword holds its own physical address.
    li t1, 0x180000
    li t2, 0x187000
1:  sd t1, 0(t1)
    addi t1, t1, 8
    blt t1, t2, 1b
    PTEW ROOT_A, 0, L1_A, 0x01
    PTEW L1_A, 0, 0x000000, 0xCF
    PTEW L1_A, 1, L0_A, 0x01
    PTEW L0_A, 0, 0x180000, 0xC7
    PTEW L0_A, 2, 0x182000, 0xC7
    PTEW L0_A, 3, 0x183000, 0x43
    PTEW L0_A, 4, 0x184000, 0xC7
    PTEW L0_A, 6, 0x186000, 0xC7
    PTEW L0_A, 8, 0x20000000, 0xC7
    la t1, s_log
    la t2, s_log_ptr
    sd t1, 0(t2)
    li t1, 0xB150               // + misaligned load/store
    csrw medeleg, t1
    li t1, 8
    slli t1, t1, 60
    ori t1, t1, ROOT_A >> 12
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
    // 1a: unit-stride load faults at element 2.
    li t0, 1
    MARK
    vsetivli x0, 8, e64, m1, tu, mu
    li a2, 0x77
    vmv.v.x v8, a2
    RESUME after1a
    li a1, V_A + 0xFF0
f1a: vle64.v v8, (a1)
    j fail_s
after1a:
    CHK_S 13, V_N, f1a, 2
    csrr a3, vstart
    li a2, 2
    bne a3, a2, fail_s
    TRAPS 1
    DUMP64 v8
    CHKD 0, 0x180FF0
    CHKD 8, 0x180FF8
    CHKD 16, 0x77
    CHKD 56, 0x77
    // 1b: the handler maps V_N and the load resumes at vstart.
    MARK
    la t1, s_fix_addr
    li t2, L0_A + 1 * 8
    sd t2, 0(t1)
    la t1, s_fix_val
    li t2, (0x181000 >> 2) | 0xC7
    sd t2, 0(t1)
    vsetivli x0, 8, e64, m1, tu, mu
    li a2, 0x77
    vmv.v.x v8, a2
    li a1, V_A + 0xFF0
f1b: vle64.v v8, (a1)
    csrr a3, vstart
    bnez a3, fail_s
    TRAPS 1
    CHK_S 13, V_N, f1b, 2
    DUMP64 v8
    CHKD 0, 0x180FF0
    CHKD 8, 0x180FF8
    CHKD 16, 0x181000
    CHKD 24, 0x181008
    CHKD 56, 0x181028

    // 2: unit-stride store faults at element 3 (read-only page).
    li t0, 2
    MARK
    vsetivli x0, 8, e64, m1, tu, mu
    vid.v v8
    vadd.vi v8, v8, 10
    RESUME after2
    li a1, V_R - 24
f2: vse64.v v8, (a1)
    j fail_s
after2:
    CHK_S 15, V_R, f2, 3
    csrw vstart, x0
    TRAPS 1
    li a1, 0x182FE8
    ld a2, 0(a1)
    li a3, 10
    bne a2, a3, fail_s
    ld a2, 16(a1)
    li a3, 12
    bne a2, a3, fail_s
    li a1, 0x183000
    ld a2, 0(a1)
    bne a2, a1, fail_s

    // 3: indexed load, element 2 indexes an unmapped page.
    li t0, 3
    MARK
    vsetivli x0, 4, e64, m1, tu, mu
    la a1, idx3
    vle64.v v4, (a1)
    li a2, 0x77
    vmv.v.x v8, a2
    RESUME after3
    li a1, V_E
f3: vluxei64.v v8, (a1), v4
    j fail_s
after3:
    CHK_S 13, V_N2, f3, 2
    TRAPS 1
    DUMP64 v8
    CHKD 0, 0x184000
    CHKD 8, 0x184008
    CHKD 16, 0x77
    CHKD 24, 0x77

    // 4: strided load, element 2 strides into an unmapped page.
    li t0, 4
    MARK
    vsetivli x0, 4, e64, m1, tu, mu
    li a2, 0x77
    vmv.v.x v8, a2
    RESUME after4
    li a1, V_E
    li a2, 0x800
f4: vlse64.v v8, (a1), a2
    j fail_s
after4:
    CHK_S 13, V_N2, f4, 2
    TRAPS 1
    DUMP64 v8
    CHKD 0, 0x184000
    CHKD 8, 0x184800
    CHKD 16, 0x77

    // 5: segment load, element 2 field 2 on an unmapped page.
    li t0, 5
    MARK
    vsetivli x0, 16, e32, m1, tu, mu
    li a2, 0x77
    vmv.v.x v8, a2
    vmv.v.x v9, a2
    vmv.v.x v10, a2
    vsetivli x0, 4, e32, m1, tu, mu
    RESUME after5
    li a1, V_E + 0xFE0
f5: vlseg3e32.v v8, (a1)
    j fail_s
after5:
    CHK_S 13, V_N2, f5, 2
    TRAPS 1
    DUMP32 v8
    CHKW 0, 0x184FE0
    CHKW 4, 0
    CHKW 8, 0x77
    CHKW 12, 0x77
    DUMP32 v9
    CHKW 0, 0
    CHKW 4, 0x184FF0
    CHKW 8, 0x77
    DUMP32 v10
    CHKW 0, 0x184FE8
    CHKW 4, 0
    CHKW 8, 0x77

    // 6: fault-only-first trims; the scalar load after it faults.
    li t0, 6
    MARK
    vsetivli x0, 8, e64, m1, tu, mu
    li a2, 0x77
    vmv.v.x v8, a2
    li a1, V_E + 0xFF0
    li a4, V_N2
    li a3, 0x5555
    vle64ff.v v8, (a1)
f6: ld a3, 0(a4)
    li a2, 0x5555
    bne a3, a2, fail_s
    TRAPS 1
    CHK_S 13, V_N2, f6, 0
    csrr a3, vl
    li a2, 2
    bne a3, a2, fail_s
    DUMP64 v8
    CHKD 0, 0x184FF0
    CHKD 8, 0x184FF8
    CHKD 16, 0x77
    // 6b: element 0 faults: trap, vl kept.
    MARK
    vsetivli x0, 8, e64, m1, tu, mu
    RESUME after6b
f6b: vle64ff.v v8, (a4)
    j fail_s
after6b:
    CHK_S 13, V_N2, f6b, 0
    TRAPS 1
    csrr a3, vl
    li a2, 8
    bne a3, a2, fail_s

    // 7: masked-off elements on an unmapped page.
    li t0, 7
    MARK
    vsetivli x0, 4, e64, m1, tu, mu
    li a2, 0x77
    vmv.v.x v8, a2
    li a2, 3
    vmv.s.x v0, a2              // elements 0-1 active
    li a1, V_E + 0xFF0
    vle64.v v8, (a1), v0.t
    TRAPS 0
    DUMP64 v8
    CHKD 0, 0x184FF0
    CHKD 8, 0x184FF8
    CHKD 16, 0x77
    CHKD 24, 0x77
    vsetivli x0, 4, e64, m1, tu, mu
    li a2, 4
    vmv.s.x v0, a2              // element 2 only
    RESUME after7
    li a1, V_E + 0xFF0
f7: vle64.v v8, (a1), v0.t
    j fail_s
after7:
    CHK_S 13, V_N2, f7, 2
    TRAPS 1
    csrw vstart, x0

    // 8: vector store fault; nothing after it happens.
    li t0, 8
    MARK
    li s3, 0
    la a4, flag8
    sd x0, 0(a4)
    li s6, VA_DEV
    ld s7, 0(s6)
    vsetivli x0, 8, e64, m1, tu, mu
    vid.v v8
    RESUME after8
    li a1, V_R - 16
f8: vse64.v v8, (a1)
    addi s3, s3, 1
    sd s3, 0(a4)
    ld s8, 0(s6)
    j fail_s
after8:
    CHK_S 15, V_R, f8, 2
    csrw vstart, x0
    TRAPS 1
    bnez s3, fail_s
    ld a3, 0(a4)
    bnez a3, fail_s
    ld s8, 0(s6)
    addi s7, s7, 1
    bne s8, s7, fail_s

    // 9: vstart = 2 skips two elements on an unmapped page.
    li t0, 9
    MARK
    vsetivli x0, 8, e64, m1, tu, mu
    li a2, 0x77
    vmv.v.x v8, a2
    li a1, V_N2 + 0x1000 - 16
    li a2, 2
    csrw vstart, a2
    vle64.v v8, (a1)
    csrr a3, vstart
    bnez a3, fail_s
    TRAPS 0
    DUMP64 v8
    CHKD 0, 0x77
    CHKD 8, 0x77
    CHKD 16, 0x186000
    CHKD 56, 0x186028

    // 10: TLB-cold accesses across five pages.
    li t0, 10
    MARK
    sfence.vma
    vsetivli x0, 5, e64, m1, tu, mu
    li a1, V_A + 0x10
    li a2, 0x1000
    vlse64.v v8, (a1), a2       // A, N, C, R, E
    DUMP64 v8
    CHKD 0, 0x180010
    CHKD 8, 0x181010
    CHKD 16, 0x182010
    CHKD 24, 0x183010
    CHKD 32, 0x184010
    sfence.vma
    vsetivli x0, 5, e64, m1, tu, mu
    la a1, idx10
    vle64.v v4, (a1)
    li a1, V_A
    vluxei64.v v8, (a1), v4     // E, A, R, N, C
    DUMP64 v8
    CHKD 0, 0x184020
    CHKD 8, 0x180028
    CHKD 16, 0x183030
    CHKD 24, 0x181038
    CHKD 32, 0x182040
    sfence.vma
    vsetivli x0, 3, e64, m1, tu, mu
    li a2, 0x99
    vmv.v.x v8, a2
    li a1, V_A + 0x1000 - 8
    li a2, 0x1000
    vsse64.v v8, (a1), a2       // A, N, C
    li a1, 0x180FF8
    ld a3, 0(a1)
    li a2, 0x99
    bne a3, a2, fail_s
    li a1, 0x181FF8
    ld a3, 0(a1)
    bne a3, a2, fail_s
    li a1, 0x182FF8
    ld a3, 0(a1)
    bne a3, a2, fail_s
    sfence.vma
    vsetivli x0, 8, e64, m1, tu, mu
    li a1, V_C - 32
    vle64.v v8, (a1)            // N then C
    DUMP64 v8
    CHKD 0, 0x181FE0
    CHKD 16, 0x181FF0
    CHKD 24, 0x99               // test 10's strided store
    CHKD 32, 0x182000
    CHKD 56, 0x182018
    TRAPS 0

    la a1, pass
    la a2, resume_addr
    sd a1, 0(a2)
    ecall
    j fail_s

pass:
    li t1, EXIT
    sd x0, 0(t1)
1:  j 1b
fail_s:
    mv s11, t0
    la a1, m_fail
    la a2, resume_addr
    sd a1, 0(a2)
    ecall
1:  j 1b
m_fail:
    mv t0, s11
fail:
    li t1, EXIT
    sd t0, 0(t1)
1:  j 1b

handler_m:
    csrrw sp, mscratch, sp
    sd t1, 0(sp)
    sd t2, 8(sp)
    la t2, resume_addr
    ld t1, 0(t2)
    beqz t1, 1f
    sd x0, 0(t2)
    csrw mepc, t1
    li t1, (3 << 11)
    csrs mstatus, t1
    j 2f
1:  la t1, m_info             // unexpected M trap: record, fail 99
    csrr t2, mcause
    sd t2, 0(t1)
    csrr t2, mepc
    sd t2, 8(t1)
    csrr t2, mtval
    sd t2, 16(t1)
    sd t0, 24(t1)
    li t1, EXIT
    li t2, 99
    sd t2, 0(t1)
2:  ld t1, 0(sp)
    ld t2, 8(sp)
    csrrw sp, mscratch, sp
    mret

// S: log (cause, tval, epc, vstart), count; then either map a page
// (s_fix_*: PTE store, SFENCE.VMA, return to the instruction), or
// resume at s_resume, or skip the instruction.
handler_s:
    csrrw sp, sscratch, sp
    sd t1, 0(sp)
    sd t2, 8(sp)
    sd t3, 16(sp)
    la t1, s_cause
    csrr t2, scause
    sd t2, 0(t1)
    csrr t3, stval
    sd t3, 8(t1)
    csrr t3, sepc
    sd t3, 16(t1)
    csrr t3, vstart
    sd t3, 24(t1)
    la t1, s_log_ptr
    ld t3, 0(t1)
    sd t2, 0(t3)
    csrr t2, stval
    sd t2, 8(t3)
    csrr t2, sepc
    sd t2, 16(t3)
    csrr t2, vstart
    sd t2, 24(t3)
    addi t3, t3, 32
    sd t3, 0(t1)
    la t1, s_count
    ld t2, 0(t1)
    addi t2, t2, 1
    sd t2, 0(t1)
    la t2, s_fix_addr
    ld t1, 0(t2)
    beqz t1, 3f
    sd x0, 0(t2)
    la t2, s_fix_val
    ld t2, 0(t2)
    sd t2, 0(t1)
    sfence.vma
    j 2f
3:  la t2, s_resume
    ld t1, 0(t2)
    beqz t1, 1f
    sd x0, 0(t2)
    csrw sepc, t1
    j 2f
1:  csrr t1, sepc
    addi t1, t1, 4
    csrw sepc, t1
2:  ld t1, 0(sp)
    ld t2, 8(sp)
    ld t3, 16(sp)
    csrrw sp, sscratch, sp
    sret

    .data
    .align 3
idx3:        .quad 0, 8, 0x1000, 16
idx10:       .quad 0x4020, 0x28, 0x3030, 0x1038, 0x2040
s_cause:     .quad 0, 0, 0, 0
resume_addr: .quad 0
m_info:      .quad 0, 0, 0, 0
s_resume:    .quad 0
s_count:     .quad 0
s_fix_addr:  .quad 0
s_fix_val:   .quad 0
flag8:       .quad 0
s_log_ptr:   .quad 0
    .align 6
chk:         .skip 64
s_log:       .skip 32 * 64
    .align 4
main_stack:  .skip 2048
main_stack_top:
trap_stack:  .skip 1024
trap_stack_top:
s_trap_stack: .skip 1024
s_trap_stack_top:
