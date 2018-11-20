;;
;;  This file is part of the "Coroutine" project and released under the MIT License.
;;
;;  Created by Samuel Williams on 10/5/2018.
;;  Copyright, 2018, by Samuel Williams. All rights reserved.
;;

.model flat

.code

; Using fastcall is a big win (and it's the same has how x64 works).
; In coroutine transfer, the arguments are passed in ecx and edx. We don't need
; to touch these in order to pass them to the destination coroutine.

@coroutine_transfer@8 proc
	; Save caller registers
	push ebp
	push ebx
	push edi
	push esi

	; Save caller stack pointer
	mov dword ptr [ecx], esp

	; Restore callee stack pointer
	mov esp, dword ptr [edx]

	; Restore callee stack
	pop esi
	pop edi
	pop ebx
	pop ebp

	; Save the first argument as the return value
	mov eax, dword ptr ecx

	; Jump to the address on the stack
	ret
@coroutine_transfer@8 endp

end
