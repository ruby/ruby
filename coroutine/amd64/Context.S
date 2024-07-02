##
##  This file is part of the "Coroutine" project and released under the MIT License.
##
##  Created by Samuel Williams on 10/5/2018.
##  Copyright, 2018, by Samuel Williams.
##

#if defined(__CET__)
#include <cet.h>
#endif

#define TOKEN_PASTE(x,y) x##y
#define PREFIXED_SYMBOL(prefix,name) TOKEN_PASTE(prefix,name)

.text

.globl PREFIXED_SYMBOL(SYMBOL_PREFIX,coroutine_transfer)
PREFIXED_SYMBOL(SYMBOL_PREFIX,coroutine_transfer):

#if defined(__CET__)
	_CET_ENDBR
#endif

	# Make space on the stack for 6 registers:
	subq $48, %rsp

	# Save caller state:
	movq %rbp, 40(%rsp)
	movq %rbx, 32(%rsp)
	movq %r12, 24(%rsp)
	movq %r13, 16(%rsp)
	movq %r14, 8(%rsp)
	movq %r15, (%rsp)

	# Save caller stack pointer:
	movq %rsp, (%rdi)

	# Restore callee stack pointer:
	movq (%rsi), %rsp

	# Restore callee state
	movq 40(%rsp), %rbp
	movq 32(%rsp), %rbx
	movq 24(%rsp), %r12
	movq 16(%rsp), %r13
	movq 8(%rsp), %r14
	movq (%rsp), %r15

	# Adjust stack pointer back:
	addq $48, %rsp

	# Put the first argument into the return value:
	movq %rdi, %rax

	# We pop the return address and jump to it
	ret

#if (defined(__linux__) || defined(__FreeBSD__)) && defined(__ELF__)
.section .note.GNU-stack,"",%progbits
#endif
