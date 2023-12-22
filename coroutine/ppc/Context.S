; Based on the code by Samuel Williams. Created by Sergey Fedorov on 04/06/2022.
; Credits to Samuel Williams, Rei Odaira and Iain Sandoe. Errors, if any, are mine.
; Some relevant examples: https://github.com/gcc-mirror/gcc/blob/master/libphobos/libdruntime/config/powerpc/switchcontext.S
; https://github.com/gcc-mirror/gcc/blob/master/libgcc/config/rs6000/darwin-gpsave.S
; https://www.ibm.com/docs/en/aix/7.2?topic=epilogs-saving-gprs-only
; ppc32 version may be re-written compactly with stmw/lwm, but the code won't be faster, see: https://github.com/ruby/ruby/pull/5927#issuecomment-1139730541

; Notice that this code is only for Darwin (macOS). Darwin ABI differs from AIX and ELF.
; To add support for AIX, *BSD or *Linux, please make separate implementations.

#define TOKEN_PASTE(x,y) x##y
#define PREFIXED_SYMBOL(prefix,name) TOKEN_PASTE(prefix,name)

.machine ppc7400 ; = G4, Rosetta
.text

.globl PREFIXED_SYMBOL(SYMBOL_PREFIX,coroutine_transfer)
.align 2

PREFIXED_SYMBOL(SYMBOL_PREFIX,coroutine_transfer):
	; Make space on the stack for caller registers
	; (Should we rather use red zone? See libphobos example.)
	subi r1,r1,80

	; Get LR
	mflr r0

	; Save caller registers
	stw r31,0(r1)
	stw r30,4(r1)
	stw r29,8(r1)
	stw r28,12(r1)
	stw r27,16(r1)
	stw r26,20(r1)
	stw r25,24(r1)
	stw r24,28(r1)
	stw r23,32(r1)
	stw r22,36(r1)
	stw r21,40(r1)
	stw r20,44(r1)
	stw r19,48(r1)
	stw r18,52(r1)
	stw r17,56(r1)
	stw r16,60(r1)
	stw r15,64(r1)
	stw r14,68(r1)
	stw r13,72(r1)

	; Save return address
	; Possibly should rather be saved into linkage area, see libphobos and IBM docs
	stw r0,76(r1)

	; Save stack pointer to first argument
	stw r1,0(r3)

	; Load stack pointer from second argument
	lwz r1,0(r4)

	; Load return address
	lwz r0,76(r1)

	; Restore caller registers
	lwz r13,72(r1)
	lwz r14,68(r1)
	lwz r15,64(r1)
	lwz r16,60(r1)
	lwz r17,56(r1)
	lwz r18,52(r1)
	lwz r19,48(r1)
	lwz r20,44(r1)
	lwz r21,40(r1)
	lwz r22,36(r1)
	lwz r23,32(r1)
	lwz r24,28(r1)
	lwz r25,24(r1)
	lwz r26,20(r1)
	lwz r27,16(r1)
	lwz r28,12(r1)
	lwz r29,8(r1)
	lwz r30,4(r1)
	lwz r31,0(r1)

	; Set LR
	mtlr r0

	; Pop stack frame
	addi r1,r1,80

	; Jump to return address
	blr
