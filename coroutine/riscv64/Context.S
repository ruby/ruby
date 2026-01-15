#define TOKEN_PASTE(x,y) x##y

.text
.align 2

.global PREFIXED_SYMBOL(coroutine_transfer)
PREFIXED_SYMBOL(coroutine_transfer):

	# Make space on the stack for caller registers
	addi sp, sp, -0xd0

	# Save caller registers
	sd s0, 0x00(sp)
	sd s1, 0x08(sp)
	sd s2, 0x10(sp)
	sd s3, 0x18(sp)
	sd s4, 0x20(sp)
	sd s5, 0x28(sp)
	sd s6, 0x30(sp)
	sd s7, 0x38(sp)
	sd s8, 0x40(sp)
	sd s9, 0x48(sp)
	sd s10, 0x50(sp)
	sd s11, 0x58(sp)
	fsd fs0, 0x60(sp)
	fsd fs1, 0x68(sp)
	fsd fs2, 0x70(sp)
	fsd fs3, 0x78(sp)
	fsd fs4, 0x80(sp)
	fsd fs5, 0x88(sp)
	fsd fs6, 0x90(sp)
	fsd fs7, 0x98(sp)
	fsd fs8, 0xa0(sp)
	fsd fs9, 0xa8(sp)
	fsd fs10, 0xb0(sp)
	fsd fs11, 0xb8(sp)

	# Save return address
	sd ra, 0xc0(sp)

	# Save stack pointer to a0 (first argument)
	mv a2, sp
	sd a2, (a0)

	# Load stack pointer from a1 (second argument)
	ld a3, (a1)
	mv sp, a3

	# Restore caller registers
	ld s0, 0x00(sp)
	ld s1, 0x08(sp)
	ld s2, 0x10(sp)
	ld s3, 0x18(sp)
	ld s4, 0x20(sp)
	ld s5, 0x28(sp)
	ld s6, 0x30(sp)
	ld s7, 0x38(sp)
	ld s8, 0x40(sp)
	ld s9, 0x48(sp)
	ld s10, 0x50(sp)
	ld s11, 0x58(sp)
	fld fs0, 0x60(sp)
	fld fs1, 0x68(sp)
	fld fs2, 0x70(sp)
	fld fs3, 0x78(sp)
	fld fs4, 0x80(sp)
	fld fs5, 0x88(sp)
	fld fs6, 0x90(sp)
	fld fs7, 0x98(sp)
	fld fs8, 0xa0(sp)
	fld fs9, 0xa8(sp)
	fld fs10, 0xb0(sp)
	fld fs11, 0xb8(sp)

	# Load return address
	ld ra, 0xc0(sp)

	# Pop stack frame
	addi sp, sp, 0xd0

	# Jump to return address
	ret

#if defined(__linux__) && defined(__ELF__)
.section .note.GNU-stack,"",%progbits
#endif
