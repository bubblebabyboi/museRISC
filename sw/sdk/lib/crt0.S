// Sigil SDK startup (M-mode, single hart), linked first at 0x8000_0000
// by sw/sdk/link.ld. The boot ROM at 0x1000 jumps here (a0 = 0, a1 =
// DTB address; both ignored).
//
//   1. gp, sp (top of the .stack region in link.ld)
//   2. mstatus.FS = mstatus.VS = Initial: FP and vector instructions
//      trap as illegal while these are Off (their reset value)
//   3. mtvec = sigil_trap_entry (direct mode), interrupts off
//   4. clear .bss
//   5. sigil_exit(main())
	.section .text.init, "ax", @progbits
	.globl _start
_start:
	.option push
	.option norelax
	la	gp, __global_pointer$
	.option pop
	la	sp, _stack_top
	csrw	mie, zero
	li	t0, (1 << 13) | (1 << 9)	// FS = VS = Initial (01)
	csrs	mstatus, t0
	csrwi	fcsr, 0
	la	t0, sigil_trap_entry
	csrw	mtvec, t0
	la	t0, _bss_start
	la	t1, _bss_end
1:	bgeu	t0, t1, 2f
	sd	zero, 0(t0)
	addi	t0, t0, 8
	j	1b
2:	call	main
	call	sigil_exit
3:	wfi
	j	3b

// Trap vector. Saves every integer register plus the caller-saved FP
// registers and fcsr (C handlers may use them), calls
// sigil_trap_dispatch(frame), which returns the PC to resume at
// (mepc for an interrupt), then restores and returns with mret.
// Frame layout (8-byte slots): x1..x31 at 8*i, f-regs from 256, fcsr
// at 256 + 8*20.
#define FRAME 432
	.section .text.trap, "ax", @progbits
	.globl sigil_trap_entry
	.align 4
sigil_trap_entry:
	addi	sp, sp, -FRAME
	sd	x1, 8(sp)
	sd	x3, 24(sp)
	sd	x4, 32(sp)
	sd	x5, 40(sp)
	sd	x6, 48(sp)
	sd	x7, 56(sp)
	sd	x8, 64(sp)
	sd	x9, 72(sp)
	sd	x10, 80(sp)
	sd	x11, 88(sp)
	sd	x12, 96(sp)
	sd	x13, 104(sp)
	sd	x14, 112(sp)
	sd	x15, 120(sp)
	sd	x16, 128(sp)
	sd	x17, 136(sp)
	sd	x18, 144(sp)
	sd	x19, 152(sp)
	sd	x20, 160(sp)
	sd	x21, 168(sp)
	sd	x22, 176(sp)
	sd	x23, 184(sp)
	sd	x24, 192(sp)
	sd	x25, 200(sp)
	sd	x26, 208(sp)
	sd	x27, 216(sp)
	sd	x28, 224(sp)
	sd	x29, 232(sp)
	sd	x30, 240(sp)
	sd	x31, 248(sp)
	addi	t0, sp, FRAME
	sd	t0, 16(sp)		// x2 (sp) as it was at the trap
	fsd	f0, 256(sp)
	fsd	f1, 264(sp)
	fsd	f2, 272(sp)
	fsd	f3, 280(sp)
	fsd	f4, 288(sp)
	fsd	f5, 296(sp)
	fsd	f6, 304(sp)
	fsd	f7, 312(sp)
	fsd	f10, 320(sp)
	fsd	f11, 328(sp)
	fsd	f12, 336(sp)
	fsd	f13, 344(sp)
	fsd	f14, 352(sp)
	fsd	f15, 360(sp)
	fsd	f16, 368(sp)
	fsd	f17, 376(sp)
	fsd	f28, 384(sp)
	fsd	f29, 392(sp)
	fsd	f30, 400(sp)
	fsd	f31, 408(sp)
	frcsr	t0
	sd	t0, 416(sp)
	mv	a0, sp
	call	sigil_trap_dispatch
	csrw	mepc, a0
	ld	t0, 416(sp)
	fscsr	t0
	fld	f0, 256(sp)
	fld	f1, 264(sp)
	fld	f2, 272(sp)
	fld	f3, 280(sp)
	fld	f4, 288(sp)
	fld	f5, 296(sp)
	fld	f6, 304(sp)
	fld	f7, 312(sp)
	fld	f10, 320(sp)
	fld	f11, 328(sp)
	fld	f12, 336(sp)
	fld	f13, 344(sp)
	fld	f14, 352(sp)
	fld	f15, 360(sp)
	fld	f16, 368(sp)
	fld	f17, 376(sp)
	fld	f28, 384(sp)
	fld	f29, 392(sp)
	fld	f30, 400(sp)
	fld	f31, 408(sp)
	ld	x1, 8(sp)
	ld	x3, 24(sp)
	ld	x4, 32(sp)
	ld	x5, 40(sp)
	ld	x6, 48(sp)
	ld	x7, 56(sp)
	ld	x8, 64(sp)
	ld	x9, 72(sp)
	ld	x10, 80(sp)
	ld	x11, 88(sp)
	ld	x12, 96(sp)
	ld	x13, 104(sp)
	ld	x14, 112(sp)
	ld	x15, 120(sp)
	ld	x16, 128(sp)
	ld	x17, 136(sp)
	ld	x18, 144(sp)
	ld	x19, 152(sp)
	ld	x20, 160(sp)
	ld	x21, 168(sp)
	ld	x22, 176(sp)
	ld	x23, 184(sp)
	ld	x24, 192(sp)
	ld	x25, 200(sp)
	ld	x26, 208(sp)
	ld	x27, 216(sp)
	ld	x28, 224(sp)
	ld	x29, 232(sp)
	ld	x30, 240(sp)
	ld	x31, 248(sp)
	addi	sp, sp, FRAME
	mret
