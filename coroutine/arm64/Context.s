##
##  This file is part of the "Coroutine" project and released under the MIT License.
##
##  Created by Samuel Williams on 10/5/2018.
##  Copyright, 2018, by Samuel Williams. All rights reserved.
##

.text
.align 2

.global coroutine_transfer
coroutine_transfer:

	# Make space on the stack for caller registers
	sub sp, sp, 0xb0
	
	# Save caller registers
	stp d8, d9, [sp, 0x00]
	stp d10, d11, [sp, 0x10]
	stp d12, d13, [sp, 0x20]
	stp d14, d15, [sp, 0x30]
	stp x19, x20, [sp, 0x40]
	stp x21, x22, [sp, 0x50]
	stp x23, x24, [sp, 0x60]
	stp x25, x26, [sp, 0x70]
	stp x27, x28, [sp, 0x80]
	stp x29, x30, [sp, 0x90]

	# Save return address
	str x30, [sp, 0xa0]

	# Save stack pointer to x0 (first argument)
	mov x2, sp
	str x2, [x0, 0]

	# Load stack pointer from x1 (second argument)
	ldr x3, [x1, 0]
	mov sp, x3

	# Restore caller registers
	ldp d8, d9, [sp, 0x00]
	ldp d10, d11, [sp, 0x10]
	ldp d12, d13, [sp, 0x20]
	ldp d14, d15, [sp, 0x30]
	ldp x19, x20, [sp, 0x40]
	ldp x21, x22, [sp, 0x50]
	ldp x23, x24, [sp, 0x60]
	ldp x25, x26, [sp, 0x70]
	ldp x27, x28, [sp, 0x80]
	ldp x29, x30, [sp, 0x90]

	# Load return address into x4
	ldr x4, [sp, 0xa0]

	# Pop stack frame
	add sp, sp, 0xb0

	# Jump to return address (in x4)
	ret x4
