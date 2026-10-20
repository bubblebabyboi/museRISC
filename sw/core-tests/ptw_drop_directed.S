// Stale page-table-walker response after a trap (audit N3 of the
// L1 PR). S-mode code ends a 4 KiB page with EBREAK, so IF runs
// on into the next page B, misses the TLB and starts a fetch walk
// whose PTE reads go over the bus (page tables live in uncached
// RAM, so each read takes the full bus latency). EBREAK reaches
// WB and traps while that walk read is in flight; the trap aborts
// the walk and the delegated handler's vector (VA 0x4000_0000)
// lives under a different root entry with its own L1/L0 tables.
// The aborted walk's response must be dropped: if it were handed
// to the restarted walk, the handler's root lookup would read the
// page-B chain's PTE and follow the wrong tables (instruction page
// fault to M, or wrong code). The handler flushes the TLB and
// returns to the same entry 48 times, so the race is hit across
// the bus-latency spread. t0 = test number; exit store 0 = pass.
    .option norvc
    .text
    .globl _start

.equ PT_ROOT, 0x20020000     // uncached RAM in core_tb's map
.equ PT_L1A,  0x20021000
.equ PT_L0A,  0x20022000
.equ PT_L1C,  0x20023000
.equ PT_L0C,  0x20024000
.equ VA_A,    0x200000       // page A (code; entry at +0xFE0)
.equ VA_C,    0x40000000     // S handler page (root[1])
.equ ITERS,   48

_start:
    li t0, 1
    la t1, m_handler
    csrw mtvec, t1
    li t1, -1
    csrw pmpaddr15, t1
    li t1, 0x1f
    slli t1, t1, 56
    csrw pmpcfg2, t1
    // Zero the five table pages.
    li t1, PT_ROOT
    li t2, PT_ROOT + 0x5000
1:  sd x0, 0(t1)
    addi t1, t1, 8
    bltu t1, t2, 1b
    // Flags: V1 R2 W4 X8 A64 D128. Pointer = V only.
    li t1, PT_L1A
    srli t1, t1, 2
    ori t1, t1, 0x01
    li t2, PT_ROOT
    sd t1, 0(t2)                  // root[0] -> L1A
    li t1, PT_L0A
    srli t1, t1, 2
    ori t1, t1, 0x01
    li t2, PT_L1A + 8
    sd t1, 0(t2)                  // L1A[1] -> L0A (VA 2M..4M)
    la t1, page_a
    srli t1, t1, 2
    ori t1, t1, 0xCB              // RX A D
    li t2, PT_L0A
    sd t1, 0(t2)                  // L0A[0]: VA_A -> page_a
    la t1, page_b
    srli t1, t1, 2
    ori t1, t1, 0xCB
    sd t1, 8(t2)                  // L0A[1]: VA_A+4K -> page_b
    li t1, PT_L1C
    srli t1, t1, 2
    ori t1, t1, 0x01
    li t2, PT_ROOT + 8
    sd t1, 0(t2)                  // root[1] -> L1C
    li t1, PT_L0C
    srli t1, t1, 2
    ori t1, t1, 0x01
    li t2, PT_L1C
    sd t1, 0(t2)                  // L1C[0] -> L0C
    la t1, page_c
    srli t1, t1, 2
    ori t1, t1, 0xCB
    li t2, PT_L0C
    sd t1, 0(t2)                  // L0C[0]: VA_C -> page_c
    fence.i
    // Breakpoints go to the S handler at VA_C.
    li t1, (1 << 3)
    csrw medeleg, t1
    li t1, VA_C
    csrw stvec, t1
    li t1, 8
    slli t1, t1, 60
    li t2, PT_ROOT >> 12
    or t1, t1, t2
    csrw satp, t1
    sfence.vma
    li s2, 0                      // entries into page A
    li s3, 0                      // S handler visits
    li s4, VA_A + 0xFE0
    csrw mepc, s4
    li t1, (1 << 11)              // MPP = S
    csrs mstatus, t1
    li t0, 2
    mret

// Only the final ECALL from S (cause 9) is expected in M.
m_handler:
    csrr t1, mcause
    li t2, 9
    bne t1, t2, m_fail
    li t2, ITERS
    bne s2, t2, m_fail
    bne s3, t2, m_fail
    li t1, 0x10000000
    sd x0, 0(t1)
1:  j 1b
m_fail:
    li t0, 3
    li t2, 9
    beq t1, t2, 2f                // right cause, wrong counts
    li t0, 4                      // unexpected trap (e.g. fault)
2:  li t1, 0x10000000
    sd t0, 0(t1)
1:  j 1b

    .balign 4096
page_a:
    .skip 0xFE0
    addi s2, s2, 1                // VA_A + 0xFE0: entry
    nop
    nop
    nop
    nop
    nop
    nop
    ebreak                        // last word of page A
page_b:                           // next page: fetched, never run
    .skip 4096

    .balign 4096
page_c:                           // S handler at VA_C
    addi s3, s3, 1
    li t1, ITERS
    bgeu s3, t1, 1f
    csrw sepc, s4
    sfence.vma                    // cold TLB for the next pass
    sret
1:  ecall
