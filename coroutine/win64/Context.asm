;;
;;  win64.asm
;;  File file is part of the "Coroutine" project and released under the MIT License.
;;
;;  Created by Samuel Williams on 10/5/2018.
;;  Copyright, 2018, by Samuel Williams. All rights reserved.
;;

.code

coroutine_transfer proc
	push rbp
	push rbx
	push rdi
	push rsi
	push r12
	push r13
	push r14
	push r15
	
	; Save caller stack pointer
	mov [rcx], rsp 
	
	; Restore callee stack pointer
	mov rsp, [rdx]

	; Restore callee stack
	pop r15
	pop r14
	pop r13
	pop r12
	pop rsi
	pop rdi
	pop rbx
	pop rbp

	; Put the first argument into the return value
	mov rax, rcx

	; We pop the return address and jump to it
	ret
coroutine_transfer endp

end
