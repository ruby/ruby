/**********************************************************************

  vm_dump.c -

  $Author$

  Copyright (C) 2004-2007 Koichi Sasada

**********************************************************************/


#include "internal.h"
#include "addr2line.h"
#include "vm_core.h"
#include "iseq.h"
#ifdef HAVE_UCONTEXT_H
#include "ucontext.h"
#endif

/* see vm_insnhelper.h for the values */
#ifndef VMDEBUG
#define VMDEBUG 0
#endif

#define MAX_POSBUF 128

#define VM_CFP_CNT(ec, cfp) \
  ((rb_control_frame_t *)((ec)->vm_stack + (ec)->vm_stack_size) - \
   (rb_control_frame_t *)(cfp))

static void
control_frame_dump(const rb_execution_context_t *ec, const rb_control_frame_t *cfp)
{
    ptrdiff_t pc = -1;
    ptrdiff_t ep = cfp->ep - ec->vm_stack;
    char ep_in_heap = ' ';
    char posbuf[MAX_POSBUF+1];
    int line = 0;

    const char *magic, *iseq_name = "-", *selfstr = "-", *biseq_name = "-";
    VALUE tmp;

    const rb_callable_method_entry_t *me;

    if (ep < 0 || (size_t)ep > ec->vm_stack_size) {
	ep = (ptrdiff_t)cfp->ep;
	ep_in_heap = 'p';
    }

    switch (VM_FRAME_TYPE(cfp)) {
      case VM_FRAME_MAGIC_TOP:
	magic = "TOP";
	break;
      case VM_FRAME_MAGIC_METHOD:
	magic = "METHOD";
	break;
      case VM_FRAME_MAGIC_CLASS:
	magic = "CLASS";
	break;
      case VM_FRAME_MAGIC_BLOCK:
	magic = "BLOCK";
	break;
      case VM_FRAME_MAGIC_CFUNC:
	magic = "CFUNC";
	break;
      case VM_FRAME_MAGIC_IFUNC:
	magic = "IFUNC";
	break;
      case VM_FRAME_MAGIC_EVAL:
	magic = "EVAL";
	break;
      case VM_FRAME_MAGIC_RESCUE:
	magic = "RESCUE";
	break;
      case 0:
	magic = "------";
	break;
      default:
	magic = "(none)";
	break;
    }

    if (0) {
	tmp = rb_inspect(cfp->self);
	selfstr = StringValueCStr(tmp);
    }
    else {
	selfstr = "";
    }

    if (cfp->iseq != 0) {
#define RUBY_VM_IFUNC_P(ptr) imemo_type_p((VALUE)ptr, imemo_ifunc)
	if (RUBY_VM_IFUNC_P(cfp->iseq)) {
	    iseq_name = "<ifunc>";
	}
	else if (SYMBOL_P(cfp->iseq)) {
	    tmp = rb_sym2str((VALUE)cfp->iseq);
	    iseq_name = RSTRING_PTR(tmp);
	    snprintf(posbuf, MAX_POSBUF, ":%s", iseq_name);
	    line = -1;
	}
	else {
	    pc = cfp->pc - cfp->iseq->body->iseq_encoded;
	    iseq_name = RSTRING_PTR(cfp->iseq->body->location.label);
	    line = rb_vm_get_sourceline(cfp);
	    if (line) {
		snprintf(posbuf, MAX_POSBUF, "%s:%d", RSTRING_PTR(rb_iseq_path(cfp->iseq)), line);
	    }
	}
    }
    else if ((me = rb_vm_frame_method_entry(cfp)) != NULL) {
	iseq_name = rb_id2name(me->def->original_id);
	snprintf(posbuf, MAX_POSBUF, ":%s", iseq_name);
	line = -1;
    }

    fprintf(stderr, "c:%04"PRIdPTRDIFF" ",
	    ((rb_control_frame_t *)(ec->vm_stack + ec->vm_stack_size) - cfp));
    if (pc == -1) {
	fprintf(stderr, "p:---- ");
    }
    else {
	fprintf(stderr, "p:%04"PRIdPTRDIFF" ", pc);
    }
    fprintf(stderr, "s:%04"PRIdPTRDIFF" ", cfp->sp - ec->vm_stack);
    fprintf(stderr, ep_in_heap == ' ' ? "e:%06"PRIdPTRDIFF" " : "E:%06"PRIxPTRDIFF" ", ep % 10000);
    fprintf(stderr, "%-6s", magic);
    if (line) {
	fprintf(stderr, " %s", posbuf);
    }
    if (VM_FRAME_FINISHED_P(cfp)) {
	fprintf(stderr, " [FINISH]");
    }
    if (0) {
	fprintf(stderr, "              \t");
	fprintf(stderr, "iseq: %-24s ", iseq_name);
	fprintf(stderr, "self: %-24s ", selfstr);
	fprintf(stderr, "%-1s ", biseq_name);
    }
    fprintf(stderr, "\n");
}

void
rb_vmdebug_stack_dump_raw(const rb_execution_context_t *ec, const rb_control_frame_t *cfp)
{
#if 0
    VALUE *sp = cfp->sp;
    const VALUE *ep = cfp->ep;
    VALUE *p, *st, *t;

    fprintf(stderr, "-- stack frame ------------\n");
    for (p = st = ec->vm_stack; p < sp; p++) {
	fprintf(stderr, "%04ld (%p): %08"PRIxVALUE, (long)(p - st), p, *p);

	t = (VALUE *)*p;
	if (ec->vm_stack <= t && t < sp) {
	    fprintf(stderr, " (= %ld)", (long)((VALUE *)GC_GUARDED_PTR_REF((VALUE)t) - ec->vm_stack));
	}

	if (p == ep)
	    fprintf(stderr, " <- ep");

	fprintf(stderr, "\n");
    }
#endif

    fprintf(stderr, "-- Control frame information "
	    "-----------------------------------------------\n");
    while ((void *)cfp < (void *)(ec->vm_stack + ec->vm_stack_size)) {
	control_frame_dump(ec, cfp);
	cfp++;
    }
    fprintf(stderr, "\n");
}

void
rb_vmdebug_stack_dump_raw_current(void)
{
    const rb_execution_context_t *ec = GET_EC();
    rb_vmdebug_stack_dump_raw(ec, ec->cfp);
}

void
rb_vmdebug_env_dump_raw(const rb_env_t *env, const VALUE *ep)
{
    unsigned int i;
    fprintf(stderr, "-- env --------------------\n");

    while (env) {
	fprintf(stderr, "--\n");
	for (i = 0; i < env->env_size; i++) {
	    fprintf(stderr, "%04d: %08"PRIxVALUE" (%p)", i, env->env[i], (void *)&env->env[i]);
	    if (&env->env[i] == ep) fprintf(stderr, " <- ep");
	    fprintf(stderr, "\n");
	}

	env = rb_vm_env_prev_env(env);
    }
    fprintf(stderr, "---------------------------\n");
}

void
rb_vmdebug_proc_dump_raw(rb_proc_t *proc)
{
    const rb_env_t *env;
    char *selfstr;
    VALUE val = rb_inspect(vm_block_self(&proc->block));
    selfstr = StringValueCStr(val);

    fprintf(stderr, "-- proc -------------------\n");
    fprintf(stderr, "self: %s\n", selfstr);
    env = VM_ENV_ENVVAL_PTR(vm_block_ep(&proc->block));
    rb_vmdebug_env_dump_raw(env, vm_block_ep(&proc->block));
}

void
rb_vmdebug_stack_dump_th(VALUE thval)
{
    rb_thread_t *target_th = rb_thread_ptr(thval);
    rb_vmdebug_stack_dump_raw(target_th->ec, target_th->ec->cfp);
}

#if VMDEBUG > 2

/* copy from vm.c */
static const VALUE *
vm_base_ptr(const rb_control_frame_t *cfp)
{
    const rb_control_frame_t *prev_cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
    const VALUE *bp = prev_cfp->sp + cfp->iseq->body->local_table_size + VM_ENV_DATA_SIZE;

    if (cfp->iseq->body->type == ISEQ_TYPE_METHOD) {
	bp += 1;
    }
    return bp;
}

static void
vm_stack_dump_each(const rb_execution_context_t *ec, const rb_control_frame_t *cfp)
{
    int i, argc = 0, local_table_size = 0;
    VALUE rstr;
    VALUE *sp = cfp->sp;
    const VALUE *ep = cfp->ep;

    if (VM_FRAME_RUBYFRAME_P(cfp)) {
	const rb_iseq_t *iseq = cfp->iseq;
	argc = iseq->body->param.lead_num;
	local_table_size = iseq->body->local_table_size;
    }

    /* stack trace header */

    if (VM_FRAME_TYPE(cfp) == VM_FRAME_MAGIC_METHOD||
	VM_FRAME_TYPE(cfp) == VM_FRAME_MAGIC_TOP   ||
	VM_FRAME_TYPE(cfp) == VM_FRAME_MAGIC_BLOCK ||
	VM_FRAME_TYPE(cfp) == VM_FRAME_MAGIC_CLASS ||
	VM_FRAME_TYPE(cfp) == VM_FRAME_MAGIC_CFUNC ||
	VM_FRAME_TYPE(cfp) == VM_FRAME_MAGIC_IFUNC ||
	VM_FRAME_TYPE(cfp) == VM_FRAME_MAGIC_EVAL  ||
	VM_FRAME_TYPE(cfp) == VM_FRAME_MAGIC_RESCUE)
    {
	const VALUE *ptr = ep - local_table_size;

	control_frame_dump(ec, cfp);

	for (i = 0; i < argc; i++) {
	    rstr = rb_inspect(*ptr);
	    fprintf(stderr, "  arg   %2d: %8s (%p)\n", i, StringValueCStr(rstr),
		   (void *)ptr++);
	}
	for (; i < local_table_size - 1; i++) {
	    rstr = rb_inspect(*ptr);
	    fprintf(stderr, "  local %2d: %8s (%p)\n", i, StringValueCStr(rstr),
		   (void *)ptr++);
	}

	ptr = vm_base_ptr(cfp);
	for (; ptr < sp; ptr++, i++) {
	    switch (TYPE(*ptr)) {
	      case T_UNDEF:
		rstr = rb_str_new2("undef");
		break;
	      case T_IMEMO:
		rstr = rb_str_new2("imemo"); /* TODO: can put mode detail information */
		break;
	      default:
		rstr = rb_inspect(*ptr);
		break;
	    }
	    fprintf(stderr, "  stack %2d: %8s (%"PRIdPTRDIFF")\n", i, StringValueCStr(rstr),
		    (ptr - ec->vm_stack));
	}
    }
    else if (VM_FRAME_FINISHED_P(cfp)) {
	if (ec->vm_stack + ec->vm_stack_size > (VALUE *)(cfp + 1)) {
	    vm_stack_dump_each(ec, cfp + 1);
	}
	else {
	    /* SDR(); */
	}
    }
    else {
	rb_bug("unsupport frame type: %08lx", VM_FRAME_TYPE(cfp));
    }
}
#endif

void
rb_vmdebug_debug_print_register(const rb_execution_context_t *ec)
{
    rb_control_frame_t *cfp = ec->cfp;
    ptrdiff_t pc = -1;
    ptrdiff_t ep = cfp->ep - ec->vm_stack;
    ptrdiff_t cfpi;

    if (VM_FRAME_RUBYFRAME_P(cfp)) {
	pc = cfp->pc - cfp->iseq->body->iseq_encoded;
    }

    if (ep < 0 || (size_t)ep > ec->vm_stack_size) {
	ep = -1;
    }

    cfpi = ((rb_control_frame_t *)(ec->vm_stack + ec->vm_stack_size)) - cfp;
    fprintf(stderr, "  [PC] %04"PRIdPTRDIFF", [SP] %04"PRIdPTRDIFF", [EP] %04"PRIdPTRDIFF", [CFP] %04"PRIdPTRDIFF"\n",
	    pc, (cfp->sp - ec->vm_stack), ep, cfpi);
}

void
rb_vmdebug_thread_dump_regs(VALUE thval)
{
    rb_vmdebug_debug_print_register(rb_thread_ptr(thval)->ec);
}

void
rb_vmdebug_debug_print_pre(const rb_execution_context_t *ec, const rb_control_frame_t *cfp, const VALUE *_pc)
{
    const rb_iseq_t *iseq = cfp->iseq;

    if (iseq != 0) {
	ptrdiff_t pc = _pc - iseq->body->iseq_encoded;
	int i;

	for (i=0; i<(int)VM_CFP_CNT(ec, cfp); i++) {
	    printf(" ");
	}
	printf("| ");
	if(0)printf("[%03ld] ", (long)(cfp->sp - ec->vm_stack));

	/* printf("%3"PRIdPTRDIFF" ", VM_CFP_CNT(ec, cfp)); */
	if (pc >= 0) {
	    const VALUE *iseq_original = rb_iseq_original_iseq((rb_iseq_t *)iseq);

	    rb_iseq_disasm_insn(0, iseq_original, (size_t)pc, iseq, 0);
	}
    }

#if VMDEBUG > 3
    fprintf(stderr, "        (1)");
    rb_vmdebug_debug_print_register(ec);
#endif
}

void
rb_vmdebug_debug_print_post(const rb_execution_context_t *ec, const rb_control_frame_t *cfp
#if OPT_STACK_CACHING
		 , VALUE reg_a, VALUE reg_b
#endif
    )
{
#if VMDEBUG > 9
    SDR2(cfp);
#endif

#if VMDEBUG > 3
    fprintf(stderr, "        (2)");
    rb_vmdebug_debug_print_register(ec);
#endif
    /* stack_dump_raw(ec, cfp); */

#if VMDEBUG > 2
    /* stack_dump_thobj(ec); */
    vm_stack_dump_each(ec, ec->cfp);

#if OPT_STACK_CACHING
    {
	VALUE rstr;
	rstr = rb_inspect(reg_a);
	fprintf(stderr, "  sc reg A: %s\n", StringValueCStr(rstr));
	rstr = rb_inspect(reg_b);
	fprintf(stderr, "  sc reg B: %s\n", StringValueCStr(rstr));
    }
#endif
    printf
	("--------------------------------------------------------------\n");
#endif
}

VALUE
rb_vmdebug_thread_dump_state(VALUE self)
{
    rb_thread_t *th = rb_thread_ptr(self);
    rb_control_frame_t *cfp = th->ec->cfp;

    fprintf(stderr, "Thread state dump:\n");
    fprintf(stderr, "pc : %p, sp : %p\n", (void *)cfp->pc, (void *)cfp->sp);
    fprintf(stderr, "cfp: %p, ep : %p\n", (void *)cfp, (void *)cfp->ep);

    return Qnil;
}

#if defined __APPLE__
# if __DARWIN_UNIX03
#   define MCTX_SS_REG(reg) __ss.__##reg
# else
#   define MCTX_SS_REG(reg) ss.reg
# endif
#endif

#if defined(HAVE_BACKTRACE)
# ifdef HAVE_LIBUNWIND
#  undef backtrace
#  define backtrace unw_backtrace
# elif defined(__APPLE__) && defined(__x86_64__) && defined(HAVE_LIBUNWIND_H)
#  define UNW_LOCAL_ONLY
#  include <libunwind.h>
#  include <sys/mman.h>
#  undef backtrace
int
backtrace(void **trace, int size)
{
    unw_cursor_t cursor; unw_context_t uc;
    unw_word_t ip;
    int n = 0;

    unw_getcontext(&uc);
    unw_init_local(&cursor, &uc);
    while (unw_step(&cursor) > 0) {
	unw_get_reg(&cursor, UNW_REG_IP, &ip);
	trace[n++] = (void *)ip;
	{
	    char buf[256];
	    unw_get_proc_name(&cursor, buf, 256, &ip);
	    if (strncmp("_sigtramp", buf, sizeof("_sigtramp")) == 0) {
		goto darwin_sigtramp;
	    }
	}
    }
    return n;
darwin_sigtramp:
    /* darwin's bundled libunwind doesn't support signal trampoline */
    {
	ucontext_t *uctx;
	char vec[1];
	int r;
	/* get previous frame information from %rbx at _sigtramp and set values to cursor
	 * http://www.opensource.apple.com/source/Libc/Libc-825.25/i386/sys/_sigtramp.s
	 * http://www.opensource.apple.com/source/libunwind/libunwind-35.1/src/unw_getcontext.s
	 */
	unw_get_reg(&cursor, UNW_X86_64_RBX, &ip);
	uctx = (ucontext_t *)ip;
	unw_set_reg(&cursor, UNW_X86_64_RAX, uctx->uc_mcontext->MCTX_SS_REG(rax));
	unw_set_reg(&cursor, UNW_X86_64_RBX, uctx->uc_mcontext->MCTX_SS_REG(rbx));
	unw_set_reg(&cursor, UNW_X86_64_RCX, uctx->uc_mcontext->MCTX_SS_REG(rcx));
	unw_set_reg(&cursor, UNW_X86_64_RDX, uctx->uc_mcontext->MCTX_SS_REG(rdx));
	unw_set_reg(&cursor, UNW_X86_64_RDI, uctx->uc_mcontext->MCTX_SS_REG(rdi));
	unw_set_reg(&cursor, UNW_X86_64_RSI, uctx->uc_mcontext->MCTX_SS_REG(rsi));
	unw_set_reg(&cursor, UNW_X86_64_RBP, uctx->uc_mcontext->MCTX_SS_REG(rbp));
	unw_set_reg(&cursor, UNW_X86_64_RSP, 8+(uctx->uc_mcontext->MCTX_SS_REG(rsp)));
	unw_set_reg(&cursor, UNW_X86_64_R8,  uctx->uc_mcontext->MCTX_SS_REG(r8));
	unw_set_reg(&cursor, UNW_X86_64_R9,  uctx->uc_mcontext->MCTX_SS_REG(r9));
	unw_set_reg(&cursor, UNW_X86_64_R10, uctx->uc_mcontext->MCTX_SS_REG(r10));
	unw_set_reg(&cursor, UNW_X86_64_R11, uctx->uc_mcontext->MCTX_SS_REG(r11));
	unw_set_reg(&cursor, UNW_X86_64_R12, uctx->uc_mcontext->MCTX_SS_REG(r12));
	unw_set_reg(&cursor, UNW_X86_64_R13, uctx->uc_mcontext->MCTX_SS_REG(r13));
	unw_set_reg(&cursor, UNW_X86_64_R14, uctx->uc_mcontext->MCTX_SS_REG(r14));
	unw_set_reg(&cursor, UNW_X86_64_R15, uctx->uc_mcontext->MCTX_SS_REG(r15));
	ip = uctx->uc_mcontext->MCTX_SS_REG(rip);

	/* There are 4 cases for SEGV:
	 * (1) called invalid address
	 * (2) read or write invalid address
	 * (3) received signal
	 *
	 * Detail:
	 * (1) called invalid address
	 * In this case, saved ip is invalid address.
	 * It needs to just save the address for the information,
	 * skip the frame, and restore the frame calling the
	 * invalid address from %rsp.
	 * The problem is how to check whether the ip is valid or not.
	 * This code uses mincore(2) and assume the address's page is
	 * incore/referenced or not reflects the problem.
	 * Note that High Sierra's mincore(2) may return -128.
	 * (2) read or write invalid address
	 * saved ip is valid. just restart backtracing.
	 * (3) received signal in user space
	 * Same as (2).
	 * (4) received signal in kernel
	 * In this case saved ip points just after syscall, but registers are
	 * already overwritten by kernel. To fix register consistency,
	 * skip libc's kernel wrapper.
	 * To detect this case, just previous two bytes of ip is "\x0f\x05",
	 * syscall instruction of x86_64.
	 */
	r = mincore((const void *)ip, 1, vec);
	if (r || vec[0] <= 0 || memcmp((const char *)ip-2, "\x0f\x05", 2) == 0) {
	    /* if segv is caused by invalid call or signal received in syscall */
	    /* the frame is invalid; skip */
	    trace[n++] = (void *)ip;
	    ip = *(unw_word_t*)uctx->uc_mcontext->MCTX_SS_REG(rsp);
	}
	trace[n++] = (void *)ip;
	unw_set_reg(&cursor, UNW_REG_IP, ip);
    }
    while (unw_step(&cursor) > 0) {
	unw_get_reg(&cursor, UNW_REG_IP, &ip);
	trace[n++] = (void *)ip;
    }
    return n;
}
# elif defined(BROKEN_BACKTRACE)
#  undef HAVE_BACKTRACE
#  define HAVE_BACKTRACE 0
# endif
#else
# define HAVE_BACKTRACE 0
#endif

#if HAVE_BACKTRACE
# include <execinfo.h>
#elif defined(_WIN32)
# include <imagehlp.h>
# ifndef SYMOPT_DEBUG
#  define SYMOPT_DEBUG 0x80000000
# endif
# ifndef MAX_SYM_NAME
# define MAX_SYM_NAME 2000
typedef struct {
    DWORD64 Offset;
    WORD Segment;
    ADDRESS_MODE Mode;
} ADDRESS64;
typedef struct {
    DWORD64 Thread;
    DWORD ThCallbackStack;
    DWORD ThCallbackBStore;
    DWORD NextCallback;
    DWORD FramePointer;
    DWORD64 KiCallUserMode;
    DWORD64 KeUserCallbackDispatcher;
    DWORD64 SystemRangeStart;
    DWORD64 KiUserExceptionDispatcher;
    DWORD64 StackBase;
    DWORD64 StackLimit;
    DWORD64 Reserved[5];
} KDHELP64;
typedef struct {
    ADDRESS64 AddrPC;
    ADDRESS64 AddrReturn;
    ADDRESS64 AddrFrame;
    ADDRESS64 AddrStack;
    ADDRESS64 AddrBStore;
    void *FuncTableEntry;
    DWORD64 Params[4];
    BOOL Far;
    BOOL Virtual;
    DWORD64 Reserved[3];
    KDHELP64 KdHelp;
} STACKFRAME64;
typedef struct {
    ULONG SizeOfStruct;
    ULONG TypeIndex;
    ULONG64 Reserved[2];
    ULONG Index;
    ULONG Size;
    ULONG64 ModBase;
    ULONG Flags;
    ULONG64 Value;
    ULONG64 Address;
    ULONG Register;
    ULONG Scope;
    ULONG Tag;
    ULONG NameLen;
    ULONG MaxNameLen;
    char Name[1];
} SYMBOL_INFO;
typedef struct {
    DWORD SizeOfStruct;
    void *Key;
    DWORD LineNumber;
    char *FileName;
    DWORD64 Address;
} IMAGEHLP_LINE64;
typedef void *PREAD_PROCESS_MEMORY_ROUTINE64;
typedef void *PFUNCTION_TABLE_ACCESS_ROUTINE64;
typedef void *PGET_MODULE_BASE_ROUTINE64;
typedef void *PTRANSLATE_ADDRESS_ROUTINE64;
# endif

static void
dump_thread(void *arg)
{
    HANDLE dbghelp;
    BOOL (WINAPI *pSymInitialize)(HANDLE, const char *, BOOL);
    BOOL (WINAPI *pSymCleanup)(HANDLE);
    BOOL (WINAPI *pStackWalk64)(DWORD, HANDLE, HANDLE, STACKFRAME64 *, void *, PREAD_PROCESS_MEMORY_ROUTINE64, PFUNCTION_TABLE_ACCESS_ROUTINE64, PGET_MODULE_BASE_ROUTINE64, PTRANSLATE_ADDRESS_ROUTINE64);
    DWORD64 (WINAPI *pSymGetModuleBase64)(HANDLE, DWORD64);
    BOOL (WINAPI *pSymFromAddr)(HANDLE, DWORD64, DWORD64 *, SYMBOL_INFO *);
    BOOL (WINAPI *pSymGetLineFromAddr64)(HANDLE, DWORD64, DWORD *, IMAGEHLP_LINE64 *);
    HANDLE (WINAPI *pOpenThread)(DWORD, BOOL, DWORD);
    DWORD tid = *(DWORD *)arg;
    HANDLE ph;
    HANDLE th;

    dbghelp = LoadLibrary("dbghelp.dll");
    if (!dbghelp) return;
    pSymInitialize = (BOOL (WINAPI *)(HANDLE, const char *, BOOL))GetProcAddress(dbghelp, "SymInitialize");
    pSymCleanup = (BOOL (WINAPI *)(HANDLE))GetProcAddress(dbghelp, "SymCleanup");
    pStackWalk64 = (BOOL (WINAPI *)(DWORD, HANDLE, HANDLE, STACKFRAME64 *, void *, PREAD_PROCESS_MEMORY_ROUTINE64, PFUNCTION_TABLE_ACCESS_ROUTINE64, PGET_MODULE_BASE_ROUTINE64, PTRANSLATE_ADDRESS_ROUTINE64))GetProcAddress(dbghelp, "StackWalk64");
    pSymGetModuleBase64 = (DWORD64 (WINAPI *)(HANDLE, DWORD64))GetProcAddress(dbghelp, "SymGetModuleBase64");
    pSymFromAddr = (BOOL (WINAPI *)(HANDLE, DWORD64, DWORD64 *, SYMBOL_INFO *))GetProcAddress(dbghelp, "SymFromAddr");
    pSymGetLineFromAddr64 = (BOOL (WINAPI *)(HANDLE, DWORD64, DWORD *, IMAGEHLP_LINE64 *))GetProcAddress(dbghelp, "SymGetLineFromAddr64");
    pOpenThread = (HANDLE (WINAPI *)(DWORD, BOOL, DWORD))GetProcAddress(GetModuleHandle("kernel32.dll"), "OpenThread");
    if (pSymInitialize && pSymCleanup && pStackWalk64 && pSymGetModuleBase64 &&
	pSymFromAddr && pSymGetLineFromAddr64 && pOpenThread) {
	SymSetOptions(SYMOPT_UNDNAME | SYMOPT_DEFERRED_LOADS | SYMOPT_DEBUG | SYMOPT_LOAD_LINES);
	ph = GetCurrentProcess();
	pSymInitialize(ph, NULL, TRUE);
	th = pOpenThread(THREAD_SUSPEND_RESUME|THREAD_GET_CONTEXT, FALSE, tid);
	if (th) {
	    if (SuspendThread(th) != (DWORD)-1) {
		CONTEXT context;
		memset(&context, 0, sizeof(context));
		context.ContextFlags = CONTEXT_FULL;
		if (GetThreadContext(th, &context)) {
		    char libpath[MAX_PATH];
		    char buf[sizeof(SYMBOL_INFO) + MAX_SYM_NAME];
		    SYMBOL_INFO *info = (SYMBOL_INFO *)buf;
		    DWORD mac;
		    STACKFRAME64 frame;
		    memset(&frame, 0, sizeof(frame));
#if defined(_M_AMD64) || defined(__x86_64__)
		    mac = IMAGE_FILE_MACHINE_AMD64;
		    frame.AddrPC.Mode = AddrModeFlat;
		    frame.AddrPC.Offset = context.Rip;
		    frame.AddrFrame.Mode = AddrModeFlat;
		    frame.AddrFrame.Offset = context.Rbp;
		    frame.AddrStack.Mode = AddrModeFlat;
		    frame.AddrStack.Offset = context.Rsp;
#elif defined(_M_IA64) || defined(__ia64__)
		    mac = IMAGE_FILE_MACHINE_IA64;
		    frame.AddrPC.Mode = AddrModeFlat;
		    frame.AddrPC.Offset = context.StIIP;
		    frame.AddrBStore.Mode = AddrModeFlat;
		    frame.AddrBStore.Offset = context.RsBSP;
		    frame.AddrStack.Mode = AddrModeFlat;
		    frame.AddrStack.Offset = context.IntSp;
#else	/* i386 */
		    mac = IMAGE_FILE_MACHINE_I386;
		    frame.AddrPC.Mode = AddrModeFlat;
		    frame.AddrPC.Offset = context.Eip;
		    frame.AddrFrame.Mode = AddrModeFlat;
		    frame.AddrFrame.Offset = context.Ebp;
		    frame.AddrStack.Mode = AddrModeFlat;
		    frame.AddrStack.Offset = context.Esp;
#endif

		    while (pStackWalk64(mac, ph, th, &frame, &context, NULL,
					NULL, NULL, NULL)) {
			DWORD64 addr = frame.AddrPC.Offset;
			IMAGEHLP_LINE64 line;
			DWORD64 displacement;
			DWORD tmp;

			if (addr == frame.AddrReturn.Offset || addr == 0 ||
			    frame.AddrReturn.Offset == 0)
			    break;

			memset(buf, 0, sizeof(buf));
			info->SizeOfStruct = sizeof(SYMBOL_INFO);
			info->MaxNameLen = MAX_SYM_NAME;
			if (pSymFromAddr(ph, addr, &displacement, info)) {
			    if (GetModuleFileName((HANDLE)(uintptr_t)pSymGetModuleBase64(ph, addr), libpath, sizeof(libpath)))
				fprintf(stderr, "%s", libpath);
			    fprintf(stderr, "(%s+0x%I64x)",
				    info->Name, displacement);
			}
			fprintf(stderr, " [0x%p]", (void *)(VALUE)addr);
			memset(&line, 0, sizeof(line));
			line.SizeOfStruct = sizeof(line);
			if (pSymGetLineFromAddr64(ph, addr, &tmp, &line))
			    fprintf(stderr, " %s:%lu", line.FileName, line.LineNumber);
			fprintf(stderr, "\n");
		    }
		}

		ResumeThread(th);
	    }
	    CloseHandle(th);
	}
	pSymCleanup(ph);
    }
    FreeLibrary(dbghelp);
}
#endif

void
rb_print_backtrace(void)
{
#if HAVE_BACKTRACE
#define MAX_NATIVE_TRACE 1024
    static void *trace[MAX_NATIVE_TRACE];
    int n = (int)backtrace(trace, MAX_NATIVE_TRACE);
#if (defined(USE_ELF) || defined(HAVE_MACH_O_LOADER_H)) && defined(HAVE_DLADDR) && !defined(__sparc)
    rb_dump_backtrace_with_lines(n, trace);
#else
    char **syms = backtrace_symbols(trace, n);
    if (syms) {
	int i;
	for (i=0; i<n; i++) {
	    fprintf(stderr, "%s\n", syms[i]);
	}
	free(syms);
    }
#endif
#elif defined(_WIN32)
    DWORD tid = GetCurrentThreadId();
    HANDLE th = (HANDLE)_beginthread(dump_thread, 0, &tid);
    if (th != (HANDLE)-1)
	WaitForSingleObject(th, INFINITE);
#endif
}

#ifdef HAVE_LIBPROCSTAT
#include "missing/procstat_vm.c"
#endif

#if defined __linux__
# if defined __x86_64__ || defined __i386__
#  define HAVE_PRINT_MACHINE_REGISTERS 1
# endif
#elif defined __APPLE__
# if defined __x86_64__ || defined __i386__
#  define HAVE_PRINT_MACHINE_REGISTERS 1
# endif
#endif

#ifdef HAVE_PRINT_MACHINE_REGISTERS
static int
print_machine_register(size_t reg, const char *reg_name, int col_count, int max_col)
{
    int ret;
    char buf[64];

#ifdef __LP64__
    ret = snprintf(buf, sizeof(buf), " %3.3s: 0x%016" PRIxSIZE, reg_name, reg);
#else
    ret = snprintf(buf, sizeof(buf), " %3.3s: 0x%08" PRIxSIZE, reg_name, reg);
#endif
    if (col_count + ret > max_col) {
	fputs("\n", stderr);
	col_count = 0;
    }
    col_count += ret;
    fputs(buf, stderr);
    return col_count;
}
# ifdef __linux__
#   define dump_machine_register(reg) (col_count = print_machine_register(mctx->gregs[REG_##reg], #reg, col_count, 80))
# elif defined __APPLE__
#   define dump_machine_register(reg) (col_count = print_machine_register(mctx->MCTX_SS_REG(reg), #reg, col_count, 80))
# endif

static void
rb_dump_machine_register(const ucontext_t *ctx)
{
    int col_count = 0;
    if (!ctx) return;

    fprintf(stderr, "-- Machine register context "
	    "------------------------------------------------\n");

# if defined __linux__
    {
	const mcontext_t *const mctx = &ctx->uc_mcontext;
#   if defined __x86_64__
	dump_machine_register(RIP);
	dump_machine_register(RBP);
	dump_machine_register(RSP);
	dump_machine_register(RAX);
	dump_machine_register(RBX);
	dump_machine_register(RCX);
	dump_machine_register(RDX);
	dump_machine_register(RDI);
	dump_machine_register(RSI);
	dump_machine_register(R8);
	dump_machine_register(R9);
	dump_machine_register(R10);
	dump_machine_register(R11);
	dump_machine_register(R12);
	dump_machine_register(R13);
	dump_machine_register(R14);
	dump_machine_register(R15);
	dump_machine_register(EFL);
#   elif defined __i386__
	dump_machine_register(GS);
	dump_machine_register(FS);
	dump_machine_register(ES);
	dump_machine_register(DS);
	dump_machine_register(EDI);
	dump_machine_register(ESI);
	dump_machine_register(EBP);
	dump_machine_register(ESP);
	dump_machine_register(EBX);
	dump_machine_register(EDX);
	dump_machine_register(ECX);
	dump_machine_register(EAX);
	dump_machine_register(TRAPNO);
	dump_machine_register(ERR);
	dump_machine_register(EIP);
	dump_machine_register(CS);
	dump_machine_register(EFL);
	dump_machine_register(UESP);
	dump_machine_register(SS);
#   endif
    }
# elif defined __APPLE__
    {
	const mcontext_t mctx = ctx->uc_mcontext;
#   if defined __x86_64__
	dump_machine_register(rax);
	dump_machine_register(rbx);
	dump_machine_register(rcx);
	dump_machine_register(rdx);
	dump_machine_register(rdi);
	dump_machine_register(rsi);
	dump_machine_register(rbp);
	dump_machine_register(rsp);
	dump_machine_register(r8);
	dump_machine_register(r9);
	dump_machine_register(r10);
	dump_machine_register(r11);
	dump_machine_register(r12);
	dump_machine_register(r13);
	dump_machine_register(r14);
	dump_machine_register(r15);
	dump_machine_register(rip);
	dump_machine_register(rflags);
#   elif defined __i386__
	dump_machine_register(eax);
	dump_machine_register(ebx);
	dump_machine_register(ecx);
	dump_machine_register(edx);
	dump_machine_register(edi);
	dump_machine_register(esi);
	dump_machine_register(ebp);
	dump_machine_register(esp);
	dump_machine_register(ss);
	dump_machine_register(eflags);
	dump_machine_register(eip);
	dump_machine_register(cs);
	dump_machine_register(ds);
	dump_machine_register(es);
	dump_machine_register(fs);
	dump_machine_register(gs);
#   endif
    }
# endif
    fprintf(stderr, "\n\n");
}
#else
# define rb_dump_machine_register(ctx) ((void)0)
#endif /* HAVE_PRINT_MACHINE_REGISTERS */

void
rb_vm_bugreport(const void *ctx)
{
#ifdef __linux__
# define PROC_MAPS_NAME "/proc/self/maps"
#endif
#ifdef PROC_MAPS_NAME
    enum {other_runtime_info = 1};
#else
    enum {other_runtime_info = 0};
#endif
    const rb_vm_t *const vm = GET_VM();

    if (vm) {
	SDR();
	rb_backtrace_print_as_bugreport();
	fputs("\n", stderr);
    }

    rb_dump_machine_register(ctx);

#if HAVE_BACKTRACE || defined(_WIN32)
    fprintf(stderr, "-- C level backtrace information "
	    "-------------------------------------------\n");
    rb_print_backtrace();


    fprintf(stderr, "\n");
#endif /* HAVE_BACKTRACE */

    if (other_runtime_info || vm) {
	fprintf(stderr, "-- Other runtime information "
		"-----------------------------------------------\n\n");
    }
    if (vm) {
	int i;
	VALUE name;
	long len;
	const int max_name_length = 1024;
# define LIMITED_NAME_LENGTH(s) \
	(((len = RSTRING_LEN(s)) > max_name_length) ? max_name_length : (int)len)

	name = vm->progname;
	fprintf(stderr, "* Loaded script: %.*s\n",
		LIMITED_NAME_LENGTH(name), RSTRING_PTR(name));
	fprintf(stderr, "\n");
	fprintf(stderr, "* Loaded features:\n\n");
	for (i=0; i<RARRAY_LEN(vm->loaded_features); i++) {
	    name = RARRAY_AREF(vm->loaded_features, i);
	    if (RB_TYPE_P(name, T_STRING)) {
		fprintf(stderr, " %4d %.*s\n", i,
			LIMITED_NAME_LENGTH(name), RSTRING_PTR(name));
	    }
	    else if (RB_TYPE_P(name, T_CLASS) || RB_TYPE_P(name, T_MODULE)) {
		const char *const type = RB_TYPE_P(name, T_CLASS) ?
		    "class" : "module";
		name = rb_search_class_path(rb_class_real(name));
		if (!RB_TYPE_P(name, T_STRING)) {
		    fprintf(stderr, " %4d %s:<unnamed>\n", i, type);
		    continue;
		}
		fprintf(stderr, " %4d %s:%.*s\n", i, type,
			LIMITED_NAME_LENGTH(name), RSTRING_PTR(name));
	    }
	    else {
		VALUE klass = rb_search_class_path(rb_obj_class(name));
		if (!RB_TYPE_P(klass, T_STRING)) {
		    fprintf(stderr, " %4d #<%p:%p>\n", i,
			    (void *)CLASS_OF(name), (void *)name);
		    continue;
		}
		fprintf(stderr, " %4d #<%.*s:%p>\n", i,
			LIMITED_NAME_LENGTH(klass), RSTRING_PTR(klass),
			(void *)name);
	    }
	}
	fprintf(stderr, "\n");
    }

    {
#ifdef PROC_MAPS_NAME
	{
	    FILE *fp = fopen(PROC_MAPS_NAME, "r");
	    if (fp) {
		fprintf(stderr, "* Process memory map:\n\n");

		while (!feof(fp)) {
		    char buff[0x100];
		    size_t rn = fread(buff, 1, 0x100, fp);
		    if (fwrite(buff, 1, rn, stderr) != rn)
			break;
		}

		fclose(fp);
		fprintf(stderr, "\n\n");
	    }
	}
#endif /* __linux__ */
#ifdef HAVE_LIBPROCSTAT
# define MIB_KERN_PROC_PID_LEN 4
	int mib[MIB_KERN_PROC_PID_LEN];
	struct kinfo_proc kp;
	size_t len = sizeof(struct kinfo_proc);
	mib[0] = CTL_KERN;
	mib[1] = KERN_PROC;
	mib[2] = KERN_PROC_PID;
	mib[3] = getpid();
	if (sysctl(mib, MIB_KERN_PROC_PID_LEN, &kp, &len, NULL, 0) == -1) {
	    perror("sysctl");
	}
	else {
	    struct procstat *prstat = procstat_open_sysctl();
	    fprintf(stderr, "* Process memory map:\n\n");
	    procstat_vm(prstat, &kp);
	    procstat_close(prstat);
	    fprintf(stderr, "\n");
	}
#endif /* __FreeBSD__ */
    }
}

#ifdef NON_SCALAR_THREAD_ID
const char *ruby_fill_thread_id_string(rb_nativethread_id_t thid, rb_thread_id_string_t buf);
#endif

void
rb_vmdebug_stack_dump_all_threads(void)
{
    rb_vm_t *vm = GET_VM();
    rb_thread_t *th = NULL;

    list_for_each(&vm->living_threads, th, vmlt_node) {
#ifdef NON_SCALAR_THREAD_ID
	rb_thread_id_string_t buf;
	ruby_fill_thread_id_string(th->thread_id, buf);
	fprintf(stderr, "th: %p, native_id: %s\n", th, buf);
#else
        fprintf(stderr, "th: %p, native_id: %p\n", (void *)th, (void *)(uintptr_t)th->thread_id);
#endif
	rb_vmdebug_stack_dump_raw(th->ec, th->ec->cfp);
    }
}
