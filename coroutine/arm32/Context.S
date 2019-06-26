##
##  This file is part of the "Coroutine" project and released under the MIT License.
##
##  Created by Samuel Williams on 10/5/2018.
##  Copyright, 2018, by Samuel Williams. All rights reserved.
##

.text

.globl coroutine_transfer
coroutine_transfer:
	push {r4-r11,lr}
	str sp, [r0]
	ldr sp, [r1]
	pop {r4-r11,pc}
