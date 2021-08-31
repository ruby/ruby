##
##  This file is part of the "Coroutine" project and released under the MIT License.
##
##  Created by Samuel Williams on 4/11/2018.
##  Copyright, 2018, by Samuel Williams.
##

.text

.globl coroutine_transfer
coroutine_transfer:
	# Save the thread information block:
	pushq %gs:8
	pushq %gs:16

	# Save caller registers:
	pushq %rbp
	pushq %rbx
	pushq %rdi
	pushq %rsi
	pushq %r12
	pushq %r13
	pushq %r14
	pushq %r15

	movaps %xmm15, -168(%rsp)
	movaps %xmm14, -152(%rsp)
	movaps %xmm13, -136(%rsp)
	movaps %xmm12, -120(%rsp)
	movaps %xmm11, -104(%rsp)
	movaps %xmm10, -88(%rsp)
	movaps %xmm9, -72(%rsp)
	movaps %xmm8, -56(%rsp)
	movaps %xmm7, -40(%rsp)
	movaps %xmm6, -24(%rsp)

	# Save caller stack pointer:
	mov %rsp, (%rcx)

	# Restore callee stack pointer:
	mov (%rdx), %rsp

	movaps -24(%rsp), %xmm6
	movaps -40(%rsp), %xmm7
	movaps -56(%rsp), %xmm8
	movaps -72(%rsp), %xmm9
	movaps -88(%rsp), %xmm10
	movaps -104(%rsp), %xmm11
	movaps -120(%rsp), %xmm12
	movaps -136(%rsp), %xmm13
	movaps -152(%rsp), %xmm14
	movaps -168(%rsp), %xmm15

	# Restore callee stack:
	popq %r15
	popq %r14
	popq %r13
	popq %r12
	popq %rsi
	popq %rdi
	popq %rbx
	popq %rbp

	# Restore the thread information block:
	popq %gs:16
	popq %gs:8

	# Put the first argument into the return value:
	mov %rcx, %rax

	# We pop the return address and jump to it:
	ret

.globl coroutine_trampoline
coroutine_trampoline:
	# Do not remove this. This forces 16-byte alignment when entering the coroutine.
	ret
