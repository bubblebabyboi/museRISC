// An interrupt that becomes pending right before the instruction that
// disables it (#53 review, precise interrupts; software-only, no
// timer offset needed). The interrupt pin is raised by an uncached
// store to the core_tb IRQ_CTL register (pins follow from the next
// cycle on), so it becomes pending while that store waits in MEM and
// interrupts cannot be injected; 0-2 uncached I/O reads before the
// store let the fetch run ahead, so that the disabling CSR write sits
// in EX with the next instruction in ID when the store completes.
// The interrupt may then be taken before the CSR write (xPIE = 1 in
// the handler) or not until interrupts are enabled again; it must
// never be taken with them disabled (xPIE = 0).
//  M: MEIP (pin 11) with mie.MEIE, window closed by csrci mstatus.MIE.
//  S: SEIP (pin 9) delegated, sie.SEIE, closed by csrci sstatus.SIE.
// Variant v = pre * 3 + gap (pre = I/O reads before the store, gap =
// nops between the store and the csrci); M variants are bits 0-8, S
// variants bits 9-17 of the exit value: bit set = that variant took
// its interrupt with interrupts disabled. Bit 20: some variant did not
// take exactly one interrupt. Exit 0 = pass, 99 = unexpected trap.
    .option norvc
    .text
    .globl _start
.equ EXIT,    0x10000000
.equ IRQ_CTL, 0x10000008
.equ DEV,     0x20000000

// One window: \csr/\bit disable, pin mask in s7, variant number \v.
.macro WIN csr, bit, pre, gap, v
    li s4, \v
    li s9, 0                     // interrupts taken in this variant
    csrsi \csr, \bit
    .rept \pre
    ld t3, 0(s6)
    .endr
    sd s7, 0(s8)                 // raise the pin
    .rept \gap
    nop
    .endr
    csrci \csr, \bit
    addi s5, s5, 1
    addi s5, s5, 1
    csrsi \csr, \bit             // collect it if still pending
    nop
    nop
    nop
    nop
    csrci \csr, \bit
    li t1, 1
    beq s9, t1, 3f
    li t1, 1 << 20
    or s11, s11, t1
3:
.endm
.macro WINS csr, bit, base
    WIN \csr, \bit, 0, 0, \base + 0
    WIN \csr, \bit, 0, 1, \base + 1
    WIN \csr, \bit, 0, 2, \base + 2
    WIN \csr, \bit, 1, 0, \base + 3
    WIN \csr, \bit, 1, 1, \base + 4
    WIN \csr, \bit, 1, 2, \base + 5
    WIN \csr, \bit, 2, 0, \base + 6
    WIN \csr, \bit, 2, 1, \base + 7
    WIN \csr, \bit, 2, 2, \base + 8
.endm

_start:
    la t1, handler_m
    csrw mtvec, t1
    la t1, handler_s
    csrw stvec, t1
    li t1, -1
    csrw pmpaddr15, t1
    li t1, 0x1f
    slli t1, t1, 56
    csrw pmpcfg2, t1
    li s6, DEV
    li s8, IRQ_CTL
    li s11, 0
    csrci mstatus, 8
    li t1, (1 << 11)
    csrw mie, t1                 // MEIE
    // warm the I$ over the M windows once (no pin raised)
    li s7, 0
    WINS mstatus, 8, 0
    li s11, 0
    li s7, (1 << 11)
    WINS mstatus, 8, 0

    // S: SEI delegated
    li t1, (1 << 9)
    csrw mideleg, t1
    csrw mie, t1                 // SEIE
    la t1, s_code
    csrw mepc, t1
    li t1, (3 << 11)
    csrc mstatus, t1
    li t1, (1 << 11)
    csrs mstatus, t1
    mret
s_code:
    li s7, (1 << 9)
    WINS sstatus, 2, 9
    li t1, EXIT
    sd s11, 0(t1)
1:  j 1b

    .balign 64
handler_m:
    csrr t1, mcause
    li t2, 1
    slli t2, t2, 63
    ori t2, t2, 11
    bne t1, t2, unexpected
    sd x0, 0(s8)                 // lower the pin
    ld x0, 0(s6)                 // (an uncached read orders it)
    csrr t1, mstatus
    andi t1, t1, 0x80            // MPIE
    bnez t1, 1f
    li t1, 1
    sll t1, t1, s4
    or s11, s11, t1
1:  addi s9, s9, 1
    mret

    .balign 64
handler_s:
    csrr t1, scause
    li t2, 1
    slli t2, t2, 63
    ori t2, t2, 9
    bne t1, t2, unexpected
    sd x0, 0(s8)
    ld x0, 0(s6)
    csrr t1, sstatus
    andi t1, t1, 0x20            // SPIE
    bnez t1, 1f
    li t1, 1
    sll t1, t1, s4
    or s11, s11, t1
1:  addi s9, s9, 1
    sret

unexpected:
    li t1, EXIT
    li t2, 99
    sd t2, 0(t1)
1:  j 1b
