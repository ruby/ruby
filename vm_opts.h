/*-*-c-*-*/
/**********************************************************************

  vm_opts.h - VM optimize option

  $Author$
  $Date$

  Copyright (C) 2004-2007 Koichi Sasada

**********************************************************************/


#ifndef VM_OPTS_H_INCLUDED
#define VM_OPTS_H_INCLUDED

/* Compile options.
 * You can change these options at runtime by VM::CompileOption.
 * Following definitions are default values.
 */

#define OPT_TRACE_INSTRUCTION        0
#define OPT_TAILCALL_OPTIMIZATION    0
#define OPT_PEEPHOLE_OPTIMIZATION    1
#define OPT_SPECIALISED_INSTRUCTION  1
#define OPT_INLINE_CONST_CACHE       1


/* Build Options.
 * You can't change these options at runtime.
 */

/* C compiler depend */
#define OPT_DIRECT_THREADED_CODE     1
#define OPT_CALL_THREADED_CODE       0

/* VM running option */
#define OPT_CHECKED_RUN              1
#define OPT_INLINE_METHOD_CACHE      1
#define OPT_BLOCKINLINING            0

/* architecture independent, affects generated code */
#define OPT_OPERANDS_UNIFICATION     0
#define OPT_INSTRUCTIONS_UNIFICATION 0
#define OPT_UNIFY_ALL_COMBINATION    0
#define OPT_STACK_CACHING            0

/* misc */
#define SUPPORT_JOKE                 0

#endif /* VM_OPTS_H_INCLUDED */

