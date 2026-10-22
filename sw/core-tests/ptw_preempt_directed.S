// Fetch walk preempted by a data walk while its PTE read is in flight
// (issue #73 F2 oops hunt). S-mode code ends a 4 KiB page A with a
// load whose VA (VA_D) is not in the TLB; IF runs on into the next
// page B, misses the TLB and starts a fetch walk. The walker issues
// B's root PTE read (page tables live in uncached RAM, so the read
// takes the full bus latency) and, while it is in flight, the load
// reaches MEM and misses the TLB: sigil_mmu switches the walker to
// the (older) data walk. The fetch walk's root PTE response must not
// be taken as the data walk's root PTE: VA_D lives under root[1],
// page B under root[0], so a mixed-up walk follows L1A (root[0]'s
// table) with VA_D's level-1 index 0, finds L1A[0] = 0 and raises a
// load page fault on a valid mapping (or, with other tables, maps
// VA_D to the wrong page). Four code layouts put the load 0..3 words
// before the page end; every pass flushes the TLB first. The load
// must return MAGIC every time.
// t0 = phase; exit store 0 = pass, 3 = wrong value seen, 4 = trap.
    .option norvc
    .text
    .globl _start

.equ PT_ROOT, 0x20020000     // uncached RAM in core_tb's map
.equ PT_L1A,  0x20021000
.equ PT_L0A,  0x20022000
.equ PT_L1C,  0x20023000
.equ PT_L0C,  0x20024000
.equ VA_CODE, 0x200000       // code region (L1A[1] -> L0A)
.equ VA_D,    0x40000800     // data (root[1] -> L1C[0] -> L0C[0])
.equ NV,      4              // code layouts
.equ ITERS,   256

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
    // L0A[k]: VA_CODE + k*4K -> vcode + k*4K (RX A D), 1 + 2*NV pages.
    la t1, vcode
    srli t1, t1, 2
    ori t1, t1, 0xCB
    li t2, PT_L0A
    li t3, 1 + 2 * NV
2:  sd t1, 0(t2)
    addi t1, t1, (4096 >> 2)
    addi t2, t2, 8
    addi t3, t3, -1
    bnez t3, 2b
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
    la t1, page_d
    srli t1, t1, 2
    ori t1, t1, 0xC7              // RW A D
    li t2, PT_L0C
    sd t1, 0(t2)                  // L0C[0]: VA 0x4000_0000 -> page_d
    fence.i
    li t1, 8
    slli t1, t1, 60
    li t2, PT_ROOT >> 12
    or t1, t1, t2
    csrw satp, t1
    sfence.vma
    li s2, 0                      // passes
    li s6, VA_D
    la t1, page_d
    li t2, 0x800
    add t1, t1, t2
    ld s7, 0(t1)                  // MAGIC
    li s8, 0                      // S-side failure flag
    li t1, VA_CODE                // s_loop is the first word of vcode
    csrw mepc, t1
    li t1, (1 << 11)              // MPP = S
    csrs mstatus, t1
    li t0, 2
    mret

// Only the final ECALL from S (cause 9) is expected in M.
m_handler:
    csrr t1, mcause
    li t2, 9
    bne t1, t2, m_trap
    bnez s8, m_wrong
    li t2, ITERS
    bne s2, t2, m_wrong
    li t1, 0x10000000
    sd x0, 0(t1)
1:  j 1b
m_wrong:
    li t0, 3
    j m_exit
m_trap:
    li t0, 4                      // e.g. load page fault on VA_D
m_exit:
    csrr s9, mepc
    csrr s10, mtval
    li t1, 0x10000000
    sd t0, 0(t1)
1:  j 1b

// ---- S-mode code, VA_CODE + (PA - vcode) ----
    .balign 4096
vcode:
s_loop:
    sfence.vma                    // cold TLB for every pass
    li s5, 0
    andi t1, s2, NV - 1
    slli t1, t1, 13               // layout v: pages 1+2v (A), 2+2v (B)
    la t2, entry0
    add t2, t2, t1
    jr t2
s_next:
    addi s2, s2, 1
    li t1, ITERS
    bltu s2, t1, s_loop
    ecall
s_fail:
    li s8, 1
    ecall

// Layout v: page A's last 16 words (entry at +0xFC0) are NOPs with
// the load at 0xFFC - 4v; page B checks the loaded value.
.macro LAYOUT v
    .balign 4096
    .skip 0xFC0
    .rept 15 - \v
    nop
    .endr
    ld s5, 0(s6)
    .rept \v
    nop
    .endr
    // page B
    beq s5, s7, 1f
    j s_fail
1:  j s_next
    .balign 4096
.endm
entry0 = vcode + 0x1000 + 0xFC0
    LAYOUT 0
    LAYOUT 1
    LAYOUT 2
    LAYOUT 3

    .data
    .balign 4096
page_d:
    .skip 0x800
    .dword 0x5EED5EED12345678
    .skip 0x7F8
