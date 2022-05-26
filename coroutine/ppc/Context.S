#define TOKEN_PASTE(x,y) x##y
#define PREFIXED_SYMBOL(prefix,name) TOKEN_PASTE(prefix,name)

.text
.align 2

.globl PREFIXED_SYMBOL(SYMBOL_PREFIX,coroutine_transfer)
PREFIXED_SYMBOL(SYMBOL_PREFIX,coroutine_transfer):
	# Make space on the stack for caller registers
	addi r1,r1,-80

	# Save caller registers
	stw r13,0(r1)
	stw r14,4(r1)
	stw r15,8(r1)
	stw r16,12(r1)
	stw r17,16(r1)
	stw r18,20(r1)
	stw r19,24(r1)
	stw r20,28(r1)
	stw r21,32(r1)
	stw r22,36(r1)
	stw r23,40(r1)
	stw r24,44(r1)
	stw r25,48(r1)
	stw r26,52(r1)
	stw r27,56(r1)
	stw r28,60(r1)
	stw r29,64(r1)
	stw r30,68(r1)
	stw r31,72(r1)

	# Save return address
	mflr r0
	stw r0,76(r1)

	# Save stack pointer to first argument
	stw r1,0(r3)

	# Load stack pointer from second argument
	lwz r1,0(r4)

	# Restore caller registers
	lwz r13,0(r1)
	lwz r14,4(r1)
	lwz r15,8(r1)
	lwz r16,12(r1)
	lwz r17,16(r1)
	lwz r18,20(r1)
	lwz r19,24(r1)
	lwz r20,28(r1)
	lwz r21,32(r1)
	lwz r22,36(r1)
	lwz r23,40(r1)
	lwz r24,44(r1)
	lwz r25,48(r1)
	lwz r26,52(r1)
	lwz r27,56(r1)
	lwz r28,60(r1)
	lwz r29,64(r1)
	lwz r30,68(r1)
	lwz r31,72(r1)

	# Load return address
	lwz r0,76(r1)
	mtlr r0

	# Pop stack frame
	addi r1,r1,80

	# Jump to return address
	blr

