// rb_ia64_flushrs and rb_ia64_bsp is written in IA64 assembly language
// because Intel Compiler for IA64 doesn't support inline assembly.
//
// This file is based on following C program compiled by gcc.
//
//   void rb_ia64_flushrs(void) { __builtin_ia64_flushrs(); }
//   void *rb_ia64_bsp(void) { return __builtin_ia64_bsp(); }
// 
	.file	"ia64.c"
	.text
	.align 16
	.global rb_ia64_flushrs#
	.proc rb_ia64_flushrs#
rb_ia64_flushrs:
	.prologue
	.body
	flushrs
	;;
	nop.i 0
	br.ret.sptk.many b0
	.endp rb_ia64_flushrs#
	.align 16
	.global rb_ia64_bsp#
	.proc rb_ia64_bsp#
rb_ia64_bsp:
	.prologue
	.body
	nop.m 0
	;;
	mov r8 = ar.bsp
	br.ret.sptk.many b0
	.endp rb_ia64_bsp#
	.ident	"GCC: (GNU) 3.3.5 (Debian 1:3.3.5-13)"
