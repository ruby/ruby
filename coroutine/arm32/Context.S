##
##  This file is part of the "Coroutine" project and released under the MIT License.
##
##  Created by Samuel Williams on 10/5/2018.
##  Copyright, 2018, by Samuel Williams.
##

#define TOKEN_PASTE(x,y) x##y
#define PREFIXED_SYMBOL(prefix,name) TOKEN_PASTE(prefix,name)

.file "Context.S"
.text
.globl PREFIXED_SYMBOL(SYMBOL_PREFIX,coroutine_transfer)
.align 2
.type PREFIXED_SYMBOL(SYMBOL_PREFIX,coroutine_transfer),%function
.syntax unified

PREFIXED_SYMBOL(SYMBOL_PREFIX,coroutine_transfer):
	# Save caller state (8 registers + return address)
	push {r4-r11,lr}

	# Save caller stack pointer
	str sp, [r0]

	# Restore callee stack pointer
	ldr sp, [r1]

	# Restore callee state (8 registers program counter)
	pop {r4-r11,pc}

#if defined(__linux__) && defined(__ELF__)
.section .note.GNU-stack,"",%progbits
#endif
