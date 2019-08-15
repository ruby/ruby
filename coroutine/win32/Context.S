##
##  This file is part of the "Coroutine" project and released under the MIT License.
##
##  Created by Lars Kanis on 06/06/2019.
##

.text

# Using fastcall is a big win (and it's the same as how x64 works).
# In coroutine transfer, the arguments are passed in ecx and edx. We don't need
# to touch these in order to pass them to the destination coroutine.

.globl @coroutine_transfer@8
@coroutine_transfer@8:
	# Save the thread information block:
	pushl %fs:0
	pushl %fs:4
	pushl %fs:8

	# Save caller registers:
	pushl %ebp
	pushl %ebx
	pushl %edi
	pushl %esi

	# Save caller stack pointer:
	movl %esp, (%ecx)

	# Restore callee stack pointer:
	movl (%edx), %esp

	# Restore callee stack:
	popl %esi
	popl %edi
	popl %ebx
	popl %ebp

	# Restore the thread information block:
	popl %fs:8
	popl %fs:4
	popl %fs:0

	# Save the first argument as the return value:
	movl %ecx, %eax

	# Jump to the address on the stack:
	ret
