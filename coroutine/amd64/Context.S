
##
##  This file is part of the "Coroutine" project and released under the MIT License.
##
##  Created by Samuel Williams on 10/5/2018.
##  Copyright, 2018, by Samuel Williams.
##

#define TOKEN_PASTE(x,y) x##y
#define PREFIXED_SYMBOL(prefix,name) TOKEN_PASTE(prefix,name)

.text

.globl PREFIXED_SYMBOL(SYMBOL_PREFIX,coroutine_transfer)
PREFIXED_SYMBOL(SYMBOL_PREFIX,coroutine_transfer):

	# Save caller state
	pushq %rbp
	pushq %rbx
	pushq %r12
	pushq %r13
	pushq %r14
	pushq %r15

	# Save caller stack pointer
	movq %rsp, (%rdi)

	# Restore callee stack pointer
	movq (%rsi), %rsp

	# Restore callee state
	popq %r15
	popq %r14
	popq %r13
	popq %r12
	popq %rbx
	popq %rbp

	# Put the first argument into the return value
	movq %rdi, %rax

	# We pop the return address and jump to it
	ret

#if (defined(__linux__) || defined(__FreeBSD__)) && defined(__ELF__)
.section .note.GNU-stack,"",%progbits
.section .note.gnu.property,"a"
.p2align 3
.long 1f - 0f    # name length
.long 4f - 1f    # data length
.long 5          # NT_GNU_PROPERTY_TYPE_0
0:
.asciz "GNU"     # vendor name
1:
.p2align 3
.long 0xc0000002 # pr_type
.long 3f - 2f    # pr_datasz
2:
.long 3          # Indirect Branch Tracking (IBT) and Shadow Stack (SHSTK) is supported.
3:
.p2align 3
4:
#endif
