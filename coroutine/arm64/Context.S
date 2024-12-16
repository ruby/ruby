##
##  This file is part of the "Coroutine" project and released under the MIT License.
##
##  Created by Samuel Williams on 10/5/2018.
##  Copyright, 2018, by Samuel Williams.
##

#define TOKEN_PASTE(x,y) x##y

#if defined(__APPLE__)
#define x29 fp
#define x30 lr
.text
.p2align 2
#else
.text
.align 2
#endif

#if defined(__ARM_FEATURE_PAC_DEFAULT) && (__ARM_FEATURE_PAC_DEFAULT & 0x02) != 0
# error "-mbranch-protection flag specified b-key but Context.S does not support this"
#endif

#if defined(_WIN32)
## Add more space for certain TEB values on each stack
#define TEB_OFFSET 0x20
#else
#define TEB_OFFSET 0x00
#endif

## NOTE(PAC): Use we HINT mnemonics instead of PAC mnemonics to
## keep compatibility with those assemblers that don't support PAC.
##
## See "Providing protection for complex software" for more details about PAC/BTI
## https://developer.arm.com/architectures/learn-the-architecture/providing-protection-for-complex-software

.global PREFIXED_SYMBOL(coroutine_transfer)
PREFIXED_SYMBOL(coroutine_transfer):

#if defined(__ARM_FEATURE_PAC_DEFAULT) && (__ARM_FEATURE_PAC_DEFAULT != 0)
	# paciasp (it also acts as BTI landing pad, so no need to insert BTI also)
	hint #25
#elif defined(__ARM_FEATURE_BTI_DEFAULT) && (__ARM_FEATURE_BTI_DEFAULT != 0)
	# For the case PAC is not enabled but BTI is.
	# bti c
	hint #34
#endif
	# Make space on the stack for caller registers
	sub sp, sp, 0xa0 + TEB_OFFSET

	# Save caller registers
	stp d8, d9, [sp, 0x00 + TEB_OFFSET]
	stp d10, d11, [sp, 0x10 + TEB_OFFSET]
	stp d12, d13, [sp, 0x20 + TEB_OFFSET]
	stp d14, d15, [sp, 0x30 + TEB_OFFSET]
	stp x19, x20, [sp, 0x40 + TEB_OFFSET]
	stp x21, x22, [sp, 0x50 + TEB_OFFSET]
	stp x23, x24, [sp, 0x60 + TEB_OFFSET]
	stp x25, x26, [sp, 0x70 + TEB_OFFSET]
	stp x27, x28, [sp, 0x80 + TEB_OFFSET]
	stp x29, x30, [sp, 0x90 + TEB_OFFSET]

#if defined(_WIN32)
	# Save certain values from Thread Environment Block (TEB)
	# x18 points to the TEB on Windows
	# Read TeStackBase and TeStackLimit at ksarm64.h from TEB
	ldp  x5,  x6,  [x18, #0x08]
	# Save them
	stp  x5,  x6,  [sp, #0x00]
	# Read TeDeallocationStack at ksarm64.h from TEB
	ldr  x5, [x18, #0x1478]
	# Read TeFiberData at ksarm64.h from TEB
	ldr  x6, [x18, #0x20]
	# Save current fiber data and deallocation stack
	stp  x5,  x6,  [sp, #0x10]
#endif

	# Save stack pointer to x0 (first argument)
	mov x2, sp
	str x2, [x0, 0]

	# Load stack pointer from x1 (second argument)
	ldr x3, [x1, 0]
	mov sp, x3

#if defined(_WIN32)
	# Restore stack base and limit
	ldp  x5,  x6,  [sp, #0x00]
	# Write TeStackBase and TeStackLimit at ksarm64.h to TEB
	stp  x5,  x6,  [x18, #0x08]
	# Restore fiber data and deallocation stack
	ldp  x5,  x6,  [sp, #0x10]
	# Write TeDeallocationStack at ksarm64.h to TEB
	str  x5, [x18, #0x1478]
	# Write TeFiberData at ksarm64.h to TEB
	str  x6, [x18, #0x20]
#endif

	# Restore caller registers
	ldp d8, d9, [sp, 0x00 + TEB_OFFSET]
	ldp d10, d11, [sp, 0x10 + TEB_OFFSET]
	ldp d12, d13, [sp, 0x20 + TEB_OFFSET]
	ldp d14, d15, [sp, 0x30 + TEB_OFFSET]
	ldp x19, x20, [sp, 0x40 + TEB_OFFSET]
	ldp x21, x22, [sp, 0x50 + TEB_OFFSET]
	ldp x23, x24, [sp, 0x60 + TEB_OFFSET]
	ldp x25, x26, [sp, 0x70 + TEB_OFFSET]
	ldp x27, x28, [sp, 0x80 + TEB_OFFSET]
	ldp x29, x30, [sp, 0x90 + TEB_OFFSET]

	# Pop stack frame
	add sp, sp, 0xa0 + TEB_OFFSET

#if defined(__ARM_FEATURE_PAC_DEFAULT) && (__ARM_FEATURE_PAC_DEFAULT != 0)
	# autiasp: Authenticate x30 (LR) with SP and key A
	hint #29
#endif

	# Jump to return address (in x30)
	ret

#if defined(__linux__) && defined(__ELF__)
.section .note.GNU-stack,"",%progbits
#endif

#if (defined(__ARM_FEATURE_BTI_DEFAULT) && __ARM_FEATURE_BTI_DEFAULT != 0) || (defined(__ARM_FEATURE_PAC_DEFAULT) && __ARM_FEATURE_PAC_DEFAULT != 0)
#if defined(__ELF__)
/*  See "ELF for the Arm 64-bit Architecture (AArch64)"
    https://github.com/ARM-software/abi-aa/blob/2023Q3/aaelf64/aaelf64.rst#program-property */
#  define GNU_PROPERTY_AARCH64_FEATURE_1_BTI (1<<0)
#  define GNU_PROPERTY_AARCH64_FEATURE_1_PAC (1<<1)

#  if defined(__ARM_FEATURE_BTI_DEFAULT) && __ARM_FEATURE_BTI_DEFAULT != 0
#    define BTI_FLAG GNU_PROPERTY_AARCH64_FEATURE_1_BTI
#  else
#    define BTI_FLAG 0
#  endif
#  if defined(__ARM_FEATURE_PAC_DEFAULT) && __ARM_FEATURE_PAC_DEFAULT != 0
#    define PAC_FLAG GNU_PROPERTY_AARCH64_FEATURE_1_PAC
#  else
#    define PAC_FLAG 0
#  endif

  # The note section format is described by Note Section in Chapter 5
  # of "System V Application Binary Interface, Edition 4.1".
  .pushsection .note.gnu.property, "a"
  .p2align 3
  .long 0x4        /* Name size ("GNU\0") */
  .long 0x10       /* Descriptor size */
  .long 0x5        /* Type: NT_GNU_PROPERTY_TYPE_0 */
  .asciz "GNU"     /* Name */
  # Begin descriptor
  .long 0xc0000000 /* Property type: GNU_PROPERTY_AARCH64_FEATURE_1_AND */
  .long 0x4        /* Property size */
  .long (BTI_FLAG|PAC_FLAG)
  .long 0x0        /* 8-byte alignment padding */
  # End descriptor
  .popsection
#endif
#endif
