; Based on the code by Samuel Williams. Created by Sergey Fedorov on 04/06/2022.
; Credits to Samuel Williams, Rei Odaira and Iain Sandoe. Errors, if any, are mine.
; Some relevant examples: https://github.com/gcc-mirror/gcc/blob/master/libphobos/libdruntime/config/powerpc/switchcontext.S
; https://github.com/gcc-mirror/gcc/blob/master/libgcc/config/rs6000/darwin-gpsave.S
; https://www.ibm.com/docs/en/aix/7.2?topic=epilogs-saving-gprs-only

; Notice that this code is only for Darwin (macOS). Darwin ABI differs from AIX and ELF.
; To add support for AIX, *BSD or *Linux, please make separate implementations.

#define TOKEN_PASTE(x,y) x##y
#define PREFIXED_SYMBOL(prefix,name) TOKEN_PASTE(prefix,name)

.machine ppc64 ; = G5
.text

.globl PREFIXED_SYMBOL(SYMBOL_PREFIX,coroutine_transfer)
.align 2

PREFIXED_SYMBOL(SYMBOL_PREFIX,coroutine_transfer):
	; Make space on the stack for caller registers
	; (Should we rather use red zone? See libphobos example.)
	subi r1,r1,160

	; Get LR
	mflr r0

	; Save caller registers
	std r31,0(r1)
	std r30,8(r1)
	std r29,16(r1)
	std r28,24(r1)
	std r27,32(r1)
	std r26,40(r1)
	std r25,48(r1)
	std r24,56(r1)
	std r23,64(r1)
	std r22,72(r1)
	std r21,80(r1)
	std r20,88(r1)
	std r19,96(r1)
	std r18,104(r1)
	std r17,112(r1)
	std r16,120(r1)
	std r15,128(r1)
	std r14,136(r1)
	std r13,144(r1)

	; Save return address
	; Possibly should rather be saved into linkage area, see libphobos and IBM docs
	std r0,152(r1)

	; Save stack pointer to first argument
	std r1,0(r3)

	; Load stack pointer from second argument
	ld r1,0(r4)

	; Load return address
	ld r0,152(r1)

	; Restore caller registers
	ld r13,144(r1)
	ld r14,136(r1)
	ld r15,128(r1)
	ld r16,120(r1)
	ld r17,112(r1)
	ld r18,104(r1)
	ld r19,96(r1)
	ld r20,88(r1)
	ld r21,80(r1)
	ld r22,72(r1)
	ld r23,64(r1)
	ld r24,56(r1)
	ld r25,48(r1)
	ld r26,40(r1)
	ld r27,32(r1)
	ld r28,24(r1)
	ld r29,16(r1)
	ld r30,8(r1)
	ld r31,0(r1)

	; Set LR
	mtlr r0

	; Pop stack frame
	addi r1,r1,160

	; Jump to return address
	blr
