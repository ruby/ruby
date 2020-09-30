;;
;;  This file is part of the "Coroutine" project and released under the MIT License.
;;
;;  Created by Samuel Williams on 10/5/2018.
;;  Copyright, 2018, by Samuel Williams.
;;

.code

coroutine_transfer proc
	; Save the thread information block:
	push qword ptr gs:[8]
	push qword ptr gs:[16]

	; Save caller registers:
	push rbp
	push rbx
	push rdi
	push rsi
	push r12
	push r13
	push r14
	push r15

	movaps [rsp - 24], xmm6
	movaps [rsp - 40], xmm7
	movaps [rsp - 56], xmm8
	movaps [rsp - 72], xmm9
	movaps [rsp - 88], xmm10
	movaps [rsp - 104], xmm11
	movaps [rsp - 120], xmm12
	movaps [rsp - 136], xmm13
	movaps [rsp - 152], xmm14
	movaps [rsp - 168], xmm15

	; Save caller stack pointer:
	mov [rcx], rsp

	; Restore callee stack pointer:
	mov rsp, [rdx]

	movaps xmm15, [rsp - 168]
	movaps xmm14, [rsp - 152]
	movaps xmm13, [rsp - 136]
	movaps xmm12, [rsp - 120]
	movaps xmm11, [rsp - 104]
	movaps xmm10, [rsp - 88]
	movaps xmm9, [rsp - 72]
	movaps xmm8, [rsp - 56]
	movaps xmm7, [rsp - 40]
	movaps xmm6, [rsp - 24]

	; Restore callee stack:
	pop r15
	pop r14
	pop r13
	pop r12
	pop rsi
	pop rdi
	pop rbx
	pop rbp

	; Restore the thread information block:
	pop qword ptr gs:[16]
	pop qword ptr gs:[8]

	; Put the first argument into the return value:
	mov rax, rcx

	; We pop the return address and jump to it:
	ret
coroutine_transfer endp

coroutine_trampoline proc
	; Do not remove this. This forces 16-byte alignment when entering the coroutine.
	ret
coroutine_trampoline endp

end
