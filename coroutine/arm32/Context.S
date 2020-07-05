##
##  This file is part of the "Coroutine" project and released under the MIT License.
##
##  Created by Samuel Williams on 10/5/2018.
##  Copyright, 2018, by Samuel Williams.
##

.file "Context.S"
.text
.globl coroutine_transfer
.align 2
.type coroutine_transfer,%function
.syntax unified

coroutine_transfer:
	# Save caller state (8 registers + return address)
	push {r4-r11,lr}

	# Save caller stack pointer
	str sp, [r0]

	# Restore callee stack pointer
	ldr sp, [r1]

	# Restore callee state (8 registers program counter)
	pop {r4-r11,pc}
