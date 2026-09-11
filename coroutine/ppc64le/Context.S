#define TOKEN_PASTE(x,y) x##y

.abiversion 2
.text
.align 2

.globl PREFIXED_SYMBOL(coroutine_transfer)
.type   PREFIXED_SYMBOL(coroutine_transfer), @function
PREFIXED_SYMBOL(coroutine_transfer):
	# Global entry: set up TOC pointer (r2) from r12.
	# Required by ELFv2 ABI when this function is reached via the PLT.
	addis 2, 12, .TOC. - PREFIXED_SYMBOL(coroutine_transfer)@ha
	addi  2, 2,  .TOC. - PREFIXED_SYMBOL(coroutine_transfer)@l
	.localentry PREFIXED_SYMBOL(coroutine_transfer), .-PREFIXED_SYMBOL(coroutine_transfer)

	# Make space on the stack for caller registers
	addi 1,1,-496

	# Save caller registers
	std 14,0(1)
	std 15,8(1)
	std 16,16(1)
	std 17,24(1)
	std 18,32(1)
	std 19,40(1)
	std 20,48(1)
	std 21,56(1)
	std 22,64(1)
	std 23,72(1)
	std 24,80(1)
	std 25,88(1)
	std 26,96(1)
	std 27,104(1)
	std 28,112(1)
	std 29,120(1)
	std 30,128(1)
	std 31,136(1)

	# Save return address
	mflr 0
	std 0,144(1)

        # Save caller special register
        mfcr 0
        std 0, 152(1)

	# Save non-volatile FP registers f14-f31 (ELFv2 callee-saved). GCC keeps
	# GPR values in them under pressure (mtvsrdd/mffprd spills).
	stfd 14,160(1)
	stfd 15,168(1)
	stfd 16,176(1)
	stfd 17,184(1)
	stfd 18,192(1)
	stfd 19,200(1)
	stfd 20,208(1)
	stfd 21,216(1)
	stfd 22,224(1)
	stfd 23,232(1)
	stfd 24,240(1)
	stfd 25,248(1)
	stfd 26,256(1)
	stfd 27,264(1)
	stfd 28,272(1)
	stfd 29,280(1)
	stfd 30,288(1)
	stfd 31,296(1)

	# Save non-volatile vector registers v20-v31 (vs52-vs63). Offsets are
	# multiples of 16 from a 16-byte aligned r1, as stvx/lvx require.
	li 11,304
	stvx 20,1,11
	li 11,320
	stvx 21,1,11
	li 11,336
	stvx 22,1,11
	li 11,352
	stvx 23,1,11
	li 11,368
	stvx 24,1,11
	li 11,384
	stvx 25,1,11
	li 11,400
	stvx 26,1,11
	li 11,416
	stvx 27,1,11
	li 11,432
	stvx 28,1,11
	li 11,448
	stvx 29,1,11
	li 11,464
	stvx 30,1,11
	li 11,480
	stvx 31,1,11

	# Save stack pointer to first argument
	std 1,0(3)

	# Load stack pointer from second argument
	ld 1,0(4)

	# Restore non-volatile FP and vector registers
	lfd 14,160(1)
	lfd 15,168(1)
	lfd 16,176(1)
	lfd 17,184(1)
	lfd 18,192(1)
	lfd 19,200(1)
	lfd 20,208(1)
	lfd 21,216(1)
	lfd 22,224(1)
	lfd 23,232(1)
	lfd 24,240(1)
	lfd 25,248(1)
	lfd 26,256(1)
	lfd 27,264(1)
	lfd 28,272(1)
	lfd 29,280(1)
	lfd 30,288(1)
	lfd 31,296(1)
	li 11,304
	lvx 20,1,11
	li 11,320
	lvx 21,1,11
	li 11,336
	lvx 22,1,11
	li 11,352
	lvx 23,1,11
	li 11,368
	lvx 24,1,11
	li 11,384
	lvx 25,1,11
	li 11,400
	lvx 26,1,11
	li 11,416
	lvx 27,1,11
	li 11,432
	lvx 28,1,11
	li 11,448
	lvx 29,1,11
	li 11,464
	lvx 30,1,11
	li 11,480
	lvx 31,1,11

	# Restore caller registers
	ld 14,0(1)
	ld 15,8(1)
	ld 16,16(1)
	ld 17,24(1)
	ld 18,32(1)
	ld 19,40(1)
	ld 20,48(1)
	ld 21,56(1)
	ld 22,64(1)
	ld 23,72(1)
	ld 24,80(1)
	ld 25,88(1)
	ld 26,96(1)
	ld 27,104(1)
	ld 28,112(1)
	ld 29,120(1)
	ld 30,128(1)
	ld 31,136(1)

	# Load return address
	ld 0,144(1)
	mtlr 0

        # Load special registers
        ld 0,152(1)
        # Restore cr register cr2, cr3 and cr4 (field index 3,4,5)
        # (field index is 1-based, field 1 = cr0) using a mask (32|16|8 = 56)
        mtcrf 56,0

	# Pop stack frame
	addi 1,1,496

	# Jump to return address
	blr

#if defined(__linux__) && defined(__ELF__)
.section .note.GNU-stack,"",%progbits
#endif
