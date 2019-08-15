##
##  This file is part of the "Coroutine" project and released under the MIT License.
##
##  Created by Samuel Williams on 10/5/2018.
##  Copyright, 2018, by Samuel Williams. All rights reserved.
##

.text

.globl coroutine_transfer
coroutine_transfer:
	# Save caller state (8 registers + return address)
	push {r4-r11,lr}
	
	# Save caller stack pointer
	str sp, [r0]
	
	# Restore callee stack pointer
	ldr sp, [r1]
	
	# Restore callee state (8 registers program counter)
	pop {r4-r11,pc}
