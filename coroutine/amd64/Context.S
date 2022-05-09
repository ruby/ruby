##
##  This file is part of the "Coroutine" project and released under the MIT License.
##
##  Created by Samuel Williams on 10/5/2018.
##  Copyright, 2018, by Samuel Williams.
##

/* Important - do _not_ include <cet.h> in this file; doing so will
 * cause an incorrect .note.gnu.property section to be emitted. We have
 * one at the bottom of this file */

#define TOKEN_PASTE(x,y) x##y
#define PREFIXED_SYMBOL(prefix,name) TOKEN_PASTE(prefix,name)

.text

.globl PREFIXED_SYMBOL(SYMBOL_PREFIX,coroutine_transfer)
PREFIXED_SYMBOL(SYMBOL_PREFIX,coroutine_transfer):

#if defined(__CET__) && (__CET__ & 0x01) != 0
        /* IBT landing pad */
        endbr64
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

#if defined(COROUTINE_CONTROL_FLOW_PROTECTION)
	# Read the current shadow stack into the rbp (scratch) register:
	rdsspq %rbp
	# Save the source shadow stack pointer:
	pushq %rbp
#endif

	# Save caller stack pointer:
	movq %rsp, (%rdi)

	# Restore callee stack pointer:
	movq (%rsi), %rsp

#if defined(COROUTINE_CONTROL_FLOW_PROTECTION)
	# Restore the destination shadow stack pointer:
	popq %rbp
	rstorssp -8(%rbp)

	# Save the source shadown stack pointer token:
	saveprevssp
#endif

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

#if defined(__ELF__)

#if defined(__CET__) && (__CET__ & 0x01) != 0
# define IBT_FLAG 0x01
#else
# define IBT_FLAG 0x00
#endif

/* We do _NOT_ support CET shadow-stack. Do _not_ add the property for
 * this to the Context.o object. If you require CET shadow-stack support,
 * for now, consider building with --with-coroutine=ucontext */
#define SHSTK_FLAG 0x00

.pushsection .note.gnu.property, "a"
.p2align 3
.long 0x4        /* Name size ("GNU\0") */
.long 0x10       /* Descriptor size */
.long 0x5        /* Type: NT_GNU_PROPERTY_TYPE_0 */
.asciz "GNU"     /* Name */
# Begin descriptor
.long 0xc0000002 /* Property type: GNU_PROPERTY_X86_FEATURE_1_AND */
.long 0x4        /* Property size */
.long (IBT_FLAG | SHSTK_FLAG)
.long 0x0        /* 8-byte alignment padding */
/* End descriptor */
.popsection
#endif
