#define TOKEN_PASTE(x,y) x##y

.text
.align 2

.global PREFIXED_SYMBOL(coroutine_transfer)
PREFIXED_SYMBOL(coroutine_transfer):

	# Make space on the stack for caller registers
	addi.d $sp, $sp, -0xa0

	# Save caller registers
	st.d $s0, $sp, 0x00
	st.d $s1, $sp, 0x08
	st.d $s2, $sp, 0x10
	st.d $s3, $sp, 0x18
	st.d $s4, $sp, 0x20
	st.d $s5, $sp, 0x28
	st.d $s6, $sp, 0x30
	st.d $s7, $sp, 0x38
	st.d $s8, $sp, 0x40
	st.d $fp, $sp, 0x48
	fst.d $fs0, $sp, 0x50
	fst.d $fs1, $sp, 0x58
	fst.d $fs2, $sp, 0x60
	fst.d $fs3, $sp, 0x68
	fst.d $fs4, $sp, 0x70
	fst.d $fs5, $sp, 0x78
	fst.d $fs6, $sp, 0x80
	fst.d $fs7, $sp, 0x88

	# Save return address
	st.d $ra, $sp, 0x90

	# Save stack pointer to a0 (first argument)
	st.d $sp, $a0, 0x00

	# Load stack pointer from a1 (second argument)
	ld.d $sp, $a1, 0x00

	# Restore caller registers
	ld.d $s0, $sp, 0x00
	ld.d $s1, $sp, 0x08
	ld.d $s2, $sp, 0x10
	ld.d $s3, $sp, 0x18
	ld.d $s4, $sp, 0x20
	ld.d $s5, $sp, 0x28
	ld.d $s6, $sp, 0x30
	ld.d $s7, $sp, 0x38
	ld.d $s8, $sp, 0x40
	ld.d $fp, $sp, 0x48
	fld.d $fs0, $sp, 0x50
	fld.d $fs1, $sp, 0x58
	fld.d $fs2, $sp, 0x60
	fld.d $fs3, $sp, 0x68
	fld.d $fs4, $sp, 0x70
	fld.d $fs5, $sp, 0x78
	fld.d $fs6, $sp, 0x80
	fld.d $fs7, $sp, 0x88

	# Load return address
	ld.d $ra, $sp, 0x90

	# Pop stack frame
	addi.d $sp, $sp, 0xa0	

	# Jump to return address
	jr $ra

#if defined(__linux__) && defined(__ELF__)
.section .note.GNU-stack,"",%progbits
#endif
