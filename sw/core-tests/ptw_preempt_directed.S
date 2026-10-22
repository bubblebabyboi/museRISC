// Data walk preempting a fetch walk whose PTE read is still in
// flight on the data port (issue #73 oops hunt, MMU lens).
//
// S-mode code runs at VA_A (root[0] -> L1A -> L0A). Each pass
// flushes the TLB, then jumps to a few words before the end of
// page A, whose last word is a load from a data VA under
// root[1]. IF runs on into page B, misses the TLB and starts a
// fetch walk; its root PTE read (root[0]) goes over the bus
// (page tables in uncached RAM, full bus latency). The load
// reaches MEM a cycle or two later, misses the TLB and preempts
// the fetch walk. The fetch walk's root[0] response must not be
// taken as the data walk's root entry: if it is, the data walk
// follows root[0] -> L1A instead of root[1] -> L1C:
//   - VA_D  (vpn1 0): L1A[0] -> L0X -> junk page (0xcccc...),
//     a valid but WRONG mapping: the load returns junk;
//   - VA_D2 (vpn1 2): L1A[2] is invalid: a load page fault on a
//     valid mapping.
// Exit code 0 = pass; else (pass << 8) | kind with kind 1 = wrong
// data (loaded value at RESULT+8), 0x80 | mcause = unexpected trap
// (mtval at RESULT+0x10, mepc at RESULT+0x18).
    .option norvc
    .text
    .globl _start

.equ PT_ROOT, 0x20020000     // uncached RAM in core_tb's map
.equ PT_L1A,  0x20021000
.equ PT_L0A,  0x20022000
.equ PT_L1C,  0x20023000
.equ PT_L0C,  0x20024000
.equ PT_L0X,  0x20025000
.equ RESULT,  0x20030000
.equ VA_A,    0x200000       // page A (code), page B = VA_A + 4K
.equ VA_D,    0x40000000     // root[1], L1C[0] -> L0C[0] -> data
.equ VA_D2,   0x40400000     // root[1], L1C[2] -> L0C[0] -> data
.equ ITERS,   64

_start:
    li t0, 1
    la t1, m_handler
    csrw mtvec, t1
    li t1, -1
    csrw pmpaddr15, t1
    li t1, 0x1f
    slli t1, t1, 56
    csrw pmpcfg2, t1
    // Zero the table pages and the result area.
    li t1, PT_ROOT
    li t2, PT_ROOT + 0x6000
1:  sd x0, 0(t1)
    addi t1, t1, 8
    bltu t1, t2, 1b
    li t1, RESULT
    sd x0, 0(t1)
    sd x0, 8(t1)
    sd x0, 16(t1)
    sd x0, 24(t1)
    // Flags: V1 R2 W4 X8 A64 D128. Pointer = V only.
    li t2, PT_ROOT
    li t1, PT_L1A
    srli t1, t1, 2
    ori t1, t1, 0x01
    sd t1, 0(t2)                  // root[0] -> L1A
    li t1, PT_L1C
    srli t1, t1, 2
    ori t1, t1, 0x01
    sd t1, 8(t2)                  // root[1] -> L1C
    li t2, PT_L1A
    li t1, PT_L0X
    srli t1, t1, 2
    ori t1, t1, 0x01
    sd t1, 0(t2)                  // L1A[0] -> L0X (decoy, VA 0..2M)
    li t1, PT_L0A
    srli t1, t1, 2
    ori t1, t1, 0x01
    sd t1, 8(t2)                  // L1A[1] -> L0A (VA 2M..4M)
    li t2, PT_L0A
    la t1, page_a
    srli t1, t1, 2
    ori t1, t1, 0xCB              // RX A D
    sd t1, 0(t2)                  // L0A[0]: VA_A -> page_a
    la t1, page_b
    srli t1, t1, 2
    ori t1, t1, 0xCB
    sd t1, 8(t2)                  // L0A[1]: VA_A+4K -> page_b
    li t2, PT_L0X
    la t1, junk_page
    srli t1, t1, 2
    ori t1, t1, 0xC7              // RW A D
    sd t1, 0(t2)                  // L0X[0]: VA 0 -> junk_page
    li t2, PT_L1C
    li t1, PT_L0C
    srli t1, t1, 2
    ori t1, t1, 0x01
    sd t1, 0(t2)                  // L1C[0] -> L0C
    sd t1, 16(t2)                 // L1C[2] -> L0C
    li t2, PT_L0C
    la t1, data_page
    srli t1, t1, 2
    ori t1, t1, 0xC7              // RW A D
    sd t1, 0(t2)                  // L0C[0] -> data_page
    fence.i
    li t1, 8
    slli t1, t1, 60
    li t2, PT_ROOT >> 12
    or t1, t1, t2
    csrw satp, t1
    sfence.vma
    la t1, data_page
    ld s6, 0(t1)                  // expected value
    li s2, 0                      // passes
    li s8, VA_A + 0xFF0           // entry window base
    li s9, VA_D2
    li s10, VA_D
    li t1, VA_A
    csrw mepc, t1
    li t1, (1 << 11)              // MPP = S
    csrs mstatus, t1
    li t0, 2
    mret

// ECALL from S (cause 9) ends the test with code a0 (0 = pass).
m_handler:
    csrr t1, mcause
    li t2, 9
    bne t1, t2, m_trap
    li t1, RESULT
    sd a1, 8(t1)
    li t1, 0x10000000
    sd a0, 0(t1)
1:  j 1b
m_trap:
    li t3, RESULT
    sd t1, 0(t3)
    csrr t2, mtval
    sd t2, 16(t3)
    csrr t2, mepc
    sd t2, 24(t3)
    slli a0, s2, 8
    ori a0, a0, 0x80
    or a0, a0, t1
    li t1, 0x10000000
    sd a0, 0(t1)
1:  j 1b

    .balign 4096
page_a:                           // VA_A
    sfence.vma                    // cold TLB for this pass
    andi t1, s2, 3
    slli t1, t1, 2
    add t1, t1, s8                // entry: VA_A + 0xFF0 + 4*(pass & 3)
#ifdef CONTROL
    li t1, VA_A + 0xFC0
#endif
    andi t2, s2, 4
    beqz t2, 1f
    mv s5, s9                     // VA_D2: wrong walk faults
    j 2f
1:  mv s5, s10                    // VA_D: wrong walk reads junk
2:  jr t1
#ifdef CONTROL
    // Control: the load reaches MEM long before IF leaves page A.
    .org page_a + 0xFC0
    ld t3, 0(s5)
    .rept 15
    nop
    .endr
#else
    .org page_a + 0xFF0
    nop                           // VA_A + 0xFF0
    nop
    nop
    ld t3, 0(s5)                  // last word of page A
#endif
page_b:                           // VA_A + 4K: fetch walk starts here
    bne t3, s6, bad
    addi s2, s2, 1
    li t1, ITERS
    bltu s2, t1, back
    li a0, 0
    ecall
back:
    li t1, VA_A
    jr t1
bad:
    mv a1, t3
    slli a0, s2, 8
    ori a0, a0, 1
    ecall
    .balign 4096

data_page:
    .dword 0x1122334455667788
    .balign 4096
junk_page:
    .rept 512
    .dword 0xcccccccccccccccc
    .endr
