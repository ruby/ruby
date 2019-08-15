##
##  This file is part of the "Coroutine" project and released under the MIT License.
##
##  Created by Samuel Williams on 3/11/2018.
##  Copyright, 2018, by Samuel Williams. All rights reserved.
##

#define TOKEN_PASTE(x,y) x##y
#define PREFIXED_SYMBOL(prefix,name) TOKEN_PASTE(prefix,name)

.text

.globl PREFIXED_SYMBOL(SYMBOL_PREFIX,coroutine_transfer)
PREFIXED_SYMBOL(SYMBOL_PREFIX,coroutine_transfer):

	# Save caller registers
	pushl %ebp
	pushl %ebx
	pushl %edi
	pushl %esi

	# Save caller stack pointer
	movl %esp, (%ecx)

	# Restore callee stack pointer
	movl (%edx), %esp

	# Restore callee stack
	popl %esi
	popl %edi
	popl %ebx
	popl %ebp

	# Save the first argument as the return value
	movl %ecx, %eax

	# Jump to the address on the stack
	ret

#if defined(__linux__) && defined(__ELF__)
.section .note.GNU-stack,"",%progbits
#endif
