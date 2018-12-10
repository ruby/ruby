.text
.align 2

.globl coroutine_transfer
.type   coroutine_transfer, @function
coroutine_transfer:
	# Make space on the stack for caller registers
	addi 1,1,-152

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

	# Save stack pointer to first argument
	std 1,0(3)

	# Load stack pointer from second argument
	ld 1,0(4)

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

	# Pop stack frame
	addi 1,1,152

	# Jump to return address
	blr

#if defined(__linux__) && defined(__ELF__)
.section .note.GNU-stack,"",%progbits
#endif
