##
##  This file is part of the "Coroutine" project and released under the MIT License.
##
##  Created by Samuel Williams on 10/5/2018.
##  Copyright, 2018, by Samuel Williams.
##

#define TOKEN_PASTE(x,y) x##y
#define PREFIXED_SYMBOL(prefix,name) TOKEN_PASTE(prefix,name)

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

## NOTE(PAC): Use we HINT mnemonics instead of PAC mnemonics to
## keep compatibility with those assemblers that don't support PAC.
##
## See "Providing protection for complex software" for more details about PAC/BTI
## https://developer.arm.com/architectures/learn-the-architecture/providing-protection-for-complex-software

.global PREFIXED_SYMBOL(SYMBOL_PREFIX,coroutine_transfer)
PREFIXED_SYMBOL(SYMBOL_PREFIX,coroutine_transfer):

#if defined(__ARM_FEATURE_PAC_DEFAULT) && (__ARM_FEATURE_PAC_DEFAULT != 0)
	# paciasp (it also acts as BTI landing pad, so no need to insert BTI also)
	hint #25
#elif defined(__ARM_FEATURE_BTI_DEFAULT) && (__ARM_FEATURE_BTI_DEFAULT != 0)
	# For the case PAC is not enabled but BTI is.
	# bti c
	hint #34
#endif
	# Make space on the stack for caller registers
	sub sp, sp, 0xa0

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

	# Pop stack frame
	add sp, sp, 0xa0

#if defined(__ARM_FEATURE_PAC_DEFAULT) && (__ARM_FEATURE_PAC_DEFAULT != 0)
	# autiasp: Authenticate x30 (LR) with SP and key A
	hint #29
#endif

	# Jump to return address (in x30)
	ret

#if defined(__linux__) && defined(__ELF__)
.section .note.GNU-stack,"",%progbits
#endif

#if (defined(__ARM_FEATURE_BTI_DEFAULT) && __ARM_FEATURE_BTI_DEFAULT != 0) || (defined(____ARM_FEATURE_PAC_DEFAULT) && __ARM_FEATURE_PAC_DEFAULT != 0)
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
