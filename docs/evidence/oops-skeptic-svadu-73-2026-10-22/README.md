# Svadu A/D write-back atomicity — CONFIRMED on the patched RTL

Adversarial review of the fetch-walk preemption fix
(`experiment-preempt-drop.patch`), svadu-atomicity lens.

Base: `73-oops-dcache` RTL **with** the preempt-drop patch applied
(commit "Review base: apply experiment-preempt-drop.patch ...").
The patch does not touch the A/D update path, so this reproduces on
the patched RTL exactly as it would on unpatched RTL.

## Finding

The hardware A/D update (Svadu) is a non-atomic two-step on the
shared data port: `W_VS_READ` latches the leaf PTE into `pte_q`,
then `W_VS_UPD` writes `pte_q | A` back. MEM has port priority
between those two states (`walk_issue` requires `!mem_needs_port`).
So an older-in-program-order store to that same PTE can take the
port between the walker's read and its write-back, commit, and then
be **overwritten** by the stale `pte_q | A`. The committed store is
lost with no trap.

The RISC-V privileged spec requires the A/D update to be performed
atomically with respect to other accesses to the PTE; this
implementation's read-then-write is not atomic.

## Test

`sw/core-tests/ptw_svadu_race_directed.S`, runner
`make -C sim -f Makefile.oops oops-svadu-race` (three bus timings:
`--mem-lat 1`, rand `1:6 gap2 ready70`, `--mem-lat 40:50`).

S-mode gadget: page A ends with (a leading mem op), a latency-tuned
`DIV` (operand sweep → 1..34 cycle EX stall), and a store to page
B's leaf PTE (initial A=0, D=0, with RSW bit 8 = a "marker" that
the walker explicitly ignores). While DIV stalls EX, IF runs into
page B, misses the TLB and starts a fetch walk that reads page B's
leaf PTE; the store then reaches MEM and, by the DIV tuning, lands
between the walk's leaf read and its A/D write-back. Page B reads
the PTE back and checks the marker.

Ops swept: 0 `SD`, 1 `AMOOR.D`, 2 `LR.D/SC.D`, 3 `SD` with a leading
load (LR-like timing, no reservation). The sweep records a per-op
fail bitmask in `s11` and runs to completion.

## Result (`ev_svadu_race_bitmask.log`)

All three timings: `CORE TB FAIL ... test 12`. `12 = 0b1100` →
bit 2 (LR/SC) **and** bit 3 (plain SD with a leading load) lose the
committed store. Op 3 failing proves this is **not** an LR/SC
reservation artifact: a plain `SD` is clobbered.

A walker A/D store does not clear an LR reservation (only a program
`mem_write` does, `sigil_core.sv` ~L1752), so in op 2 the `SC.D`
genuinely committed (else the test skips the check) and the walker
still overwrote it.

## Mechanism from the trace (`ev_svadu_race_firstfail_and_trace.log`,
port activity on the PTE PA `0x102140`, op-2 failing pass)

- walker loads leaf PTE `0x102140` → `0x180b` (A=0) → enters W_VS_UPD
- a walker store and a MEM store to `0x102140` issue back to back
- `SC.D` commits `0x190b` (marker set, A clear)
- walker W_VS_UPD commits `pte_q | A = 0x184b` (A set, **marker clear**)
- program's final `LD` of the PTE returns `0x184b` → marker lost

The simulation memory-consistency checker reports
`stale-walk-rsp 0` and `d-load-mismatch 0`: the data port is
self-consistent (the walker store is a legitimate last writer on the
port). The violation is architectural — the walker resurrected a
superseded PTE value — which only the directed marker check catches.

## Relation to the fix under review

Orthogonal. `walk_preempt` never fires in the failing window
(`miss_d = 0` throughout: the store's VA is a TLB hit, pre-loaded).
The preempt-drop patch is sound for the walker-race it targets; this
is a separate, pre-existing hole it does not address. It confirms
the task's own "Also noted (unconfirmed, low): non-atomic Svadu A/D
write-back on fetch walks" — now confirmed by directed test.
