#define TOKEN_PASTE(x,y) x##y
#define PREFIXED_SYMBOL(prefix,name) TOKEN_PASTE(prefix,name)

.text
.align 3

.globl PREFIXED_SYMBOL(SYMBOL_PREFIX,coroutine_transfer)
PREFIXED_SYMBOL(SYMBOL_PREFIX,coroutine_transfer):
	# Make space on the stack for caller registers
	addi r1,r1,-152

	# Save caller registers
	std r14,0(r1)
	std r15,8(r1)
	std r16,16(r1)
	std r17,24(r1)
	std r18,32(r1)
	std r19,40(r1)
	std r20,48(r1)
	std r21,56(r1)
	std r22,64(r1)
	std r23,72(r1)
	std r24,80(r1)
	std r25,88(r1)
	std r26,96(r1)
	std r27,104(r1)
	std r28,112(r1)
	std r29,120(r1)
	std r30,128(r1)
	std r31,136(r1)

	# Save return address
	mflr r0
	std r0,144(r1)

	# Save stack pointer to first argument
	std r1,0(r3)

	# Load stack pointer from second argument
	ld r1,0(r4)

	# Restore caller registers
	ld r14,0(r1)
	ld r15,8(r1)
	ld r16,16(r1)
	ld r17,24(r1)
	ld r18,32(r1)
	ld r19,40(r1)
	ld r20,48(r1)
	ld r21,56(r1)
	ld r22,64(r1)
	ld r23,72(r1)
	ld r24,80(r1)
	ld r25,88(r1)
	ld r26,96(r1)
	ld r27,104(r1)
	ld r28,112(r1)
	ld r29,120(r1)
	ld r30,128(r1)
	ld r31,136(r1)

	# Load return address
	ld r0,144(r1)
	mtlr r0

	# Pop stack frame
	addi r1,r1,152

	# Jump to return address
	blr
