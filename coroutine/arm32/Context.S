##
##  This file is part of the "Coroutine" project and released under the MIT License.
##
##  Created by Samuel Williams on 10/5/2018.
##  Copyright, 2018, by Samuel Williams. All rights reserved.
##

.text

.globl coroutine_transfer
coroutine_transfer:
	stmia r0!, {r4-r11,sp,lr}
	ldmia r1!, {r4-r11,sp,pc}
	bx lr

#if defined(__linux__) && defined(__ELF__)
.section .note.GNU-stack,"",%progbits
#endif
