// Status-field probe (#13 review): csrc / csrs / csrw of mstatus,
// sstatus and vsstatus (0x200) with VS, FS and SD bit patterns, each
// followed by readbacks of mstatus, sstatus and vsstatus; then, in VS
// mode (mret with MPV = 1), the same on sstatus (the vsstatus view)
// and an FP write that dirties FS, and the final mstatus, vsstatus and
// misa. Sigil's no-vector core and Spike without V must produce the
// same signature (sim/novec-sweep/run_sweep.sh). Generated; linked
// with sweep.ld.
    .option norvc
    .text
    .globl _start
_start:
    la t0, trap
    csrw mtvec, t0
    la s2, begin_signature
    li t0, 9223372036854801920
    csrc mstatus, t0
    li t0, 0
    csrs mstatus, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    nop
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc mstatus, t0
    li t0, 1536
    csrs mstatus, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    nop
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc mstatus, t0
    li t0, 512
    csrs mstatus, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    nop
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc mstatus, t0
    li t0, 1024
    csrs mstatus, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    nop
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc mstatus, t0
    li t0, 24576
    csrs mstatus, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    nop
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc mstatus, t0
    li t0, 26112
    csrs mstatus, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    nop
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc mstatus, t0
    li t0, 9216
    csrs mstatus, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    nop
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc mstatus, t0
    li t0, 9223372036854777344
    csrs mstatus, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    nop
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc mstatus, t0
    li t0, 9223372036854775808
    csrs mstatus, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    nop
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc sstatus, t0
    li t0, 0
    csrs sstatus, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc sstatus, t0
    li t0, 0
    csrw sstatus, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc sstatus, t0
    li t0, 1536
    csrs sstatus, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc sstatus, t0
    li t0, 1536
    csrw sstatus, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc sstatus, t0
    li t0, 512
    csrs sstatus, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc sstatus, t0
    li t0, 512
    csrw sstatus, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc sstatus, t0
    li t0, 1024
    csrs sstatus, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc sstatus, t0
    li t0, 1024
    csrw sstatus, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc sstatus, t0
    li t0, 24576
    csrs sstatus, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc sstatus, t0
    li t0, 24576
    csrw sstatus, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc sstatus, t0
    li t0, 26112
    csrs sstatus, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc sstatus, t0
    li t0, 26112
    csrw sstatus, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc sstatus, t0
    li t0, 9216
    csrs sstatus, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc sstatus, t0
    li t0, 9216
    csrw sstatus, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc sstatus, t0
    li t0, 9223372036854777344
    csrs sstatus, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc sstatus, t0
    li t0, 9223372036854777344
    csrw sstatus, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc sstatus, t0
    li t0, 9223372036854775808
    csrs sstatus, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc sstatus, t0
    li t0, 9223372036854775808
    csrw sstatus, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc 0x200, t0
    li t0, 0
    csrs 0x200, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc 0x200, t0
    li t0, 0
    csrw 0x200, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc 0x200, t0
    li t0, 1536
    csrs 0x200, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc 0x200, t0
    li t0, 1536
    csrw 0x200, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc 0x200, t0
    li t0, 512
    csrs 0x200, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc 0x200, t0
    li t0, 512
    csrw 0x200, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc 0x200, t0
    li t0, 1024
    csrs 0x200, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc 0x200, t0
    li t0, 1024
    csrw 0x200, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc 0x200, t0
    li t0, 24576
    csrs 0x200, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc 0x200, t0
    li t0, 24576
    csrw 0x200, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc 0x200, t0
    li t0, 26112
    csrs 0x200, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc 0x200, t0
    li t0, 26112
    csrw 0x200, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc 0x200, t0
    li t0, 9216
    csrs 0x200, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc 0x200, t0
    li t0, 9216
    csrw 0x200, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc 0x200, t0
    li t0, 9223372036854777344
    csrs 0x200, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc 0x200, t0
    li t0, 9223372036854777344
    csrw 0x200, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc 0x200, t0
    li t0, 9223372036854775808
    csrs 0x200, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 9223372036854801920
    csrc 0x200, t0
    li t0, 9223372036854775808
    csrw 0x200, t0
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    csrw pmpcfg0, zero
    li t0, -1
    csrw pmpaddr0, t0
    li t0, 0x1f
    csrw pmpcfg0, t0
    csrw satp, zero
    csrw 0x680, zero
    csrw 0x280, zero
    li t0, (3 << 11) | (1 << 39)
    csrc mstatus, t0
    li t0, (1 << 11) | (1 << 39) | (1 << 13)
    csrs mstatus, t0
    li t0, 1<<13
    csrs 0x200, t0
    la t0, 97f
    csrw mepc, t0
    mret
97:
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 3<<9
    csrs sstatus, t0
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    fmv.d.x f1, zero
    csrr t1, sstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    ecall
    csrr t1, mstatus
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, 0x200
    sd t1, 0(s2)
    addi s2, s2, 8
    csrr t1, misa
    sd t1, 0(s2)
    addi s2, s2, 8
    li t0, 1
    la t1, tohost
    sd t0, 0(t1)
1:  j 1b
    .align 2
trap:
    li t5, 3 << 11
    csrs mstatus, t5
    li t5, 1 << 39
    csrc mstatus, t5
    csrr t6, mepc
    addi t6, t6, 4
    csrw mepc, t6
    mret
    .data
    .align 6
    .globl begin_signature
begin_signature:
    .space 2048
    .globl end_signature
end_signature:
    .align 6
    .globl tohost
tohost: .dword 0
    .globl fromhost
fromhost: .dword 0
