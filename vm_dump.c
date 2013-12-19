/**********************************************************************

  vm_dump.c -

  $Author$

  Copyright (C) 2004-2007 Koichi Sasada

**********************************************************************/


#include "ruby/ruby.h"
#include "addr2line.h"
#include "vm_core.h"
#include "internal.h"

/* see vm_insnhelper.h for the values */
#ifndef VMDEBUG
#define VMDEBUG 0
#endif

#define MAX_POSBUF 128

#define VM_CFP_CNT(th, cfp) \
  ((rb_control_frame_t *)((th)->stack + (th)->stack_size) - (rb_control_frame_t *)(cfp))

static void
control_frame_dump(rb_thread_t *th, rb_control_frame_t *cfp)
{
    ptrdiff_t pc = -1;
    ptrdiff_t ep = cfp->ep - th->stack;
    char ep_in_heap = ' ';
    char posbuf[MAX_POSBUF+1];
    int line = 0;

    const char *magic, *iseq_name = "-", *selfstr = "-", *biseq_name = "-";
    VALUE tmp;

    if (cfp->block_iseq != 0 && BUILTIN_TYPE(cfp->block_iseq) != T_NODE) {
	biseq_name = "";	/* RSTRING(cfp->block_iseq->location.label)->ptr; */
    }

    if (ep < 0 || (size_t)ep > th->stack_size) {
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
      case VM_FRAME_MAGIC_PROC:
	magic = "PROC";
	break;
      case VM_FRAME_MAGIC_LAMBDA:
	magic = "LAMBDA";
	break;
      case VM_FRAME_MAGIC_IFUNC:
	magic = "IFUNC";
	break;
      case VM_FRAME_MAGIC_EVAL:
	magic = "EVAL";
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
	if (RUBY_VM_IFUNC_P(cfp->iseq)) {
	    iseq_name = "<ifunc>";
	}
	else {
	    pc = cfp->pc - cfp->iseq->iseq_encoded;
	    iseq_name = RSTRING_PTR(cfp->iseq->location.label);
	    line = rb_vm_get_sourceline(cfp);
	    if (line) {
		snprintf(posbuf, MAX_POSBUF, "%s:%d", RSTRING_PTR(cfp->iseq->location.path), line);
	    }
	}
    }
    else if (cfp->me) {
	iseq_name = rb_id2name(cfp->me->def->original_id);
	snprintf(posbuf, MAX_POSBUF, ":%s", iseq_name);
	line = -1;
    }

    fprintf(stderr, "c:%04"PRIdPTRDIFF" ",
	    ((rb_control_frame_t *)(th->stack + th->stack_size) - cfp));
    if (pc == -1) {
	fprintf(stderr, "p:---- ");
    }
    else {
	fprintf(stderr, "p:%04"PRIdPTRDIFF" ", pc);
    }
    fprintf(stderr, "s:%04"PRIdPTRDIFF" ", cfp->sp - th->stack);
    fprintf(stderr, ep_in_heap == ' ' ? "e:%06"PRIdPTRDIFF" " : "E:%06"PRIxPTRDIFF" ", ep % 10000);
    fprintf(stderr, "%-6s", magic);
    if (line) {
	fprintf(stderr, " %s", posbuf);
    }
    if (VM_FRAME_TYPE_FINISH_P(cfp)) {
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
rb_vmdebug_stack_dump_raw(rb_thread_t *th, rb_control_frame_t *cfp)
{
#if 0
    VALUE *sp = cfp->sp, *ep = cfp->ep;
    VALUE *p, *st, *t;

    fprintf(stderr, "-- stack frame ------------\n");
    for (p = st = th->stack; p < sp; p++) {
	fprintf(stderr, "%04ld (%p): %08"PRIxVALUE, (long)(p - st), p, *p);

	t = (VALUE *)*p;
	if (th->stack <= t && t < sp) {
	    fprintf(stderr, " (= %ld)", (long)((VALUE *)GC_GUARDED_PTR_REF(t) - th->stack));
	}

	if (p == ep)
	    fprintf(stderr, " <- ep");

	fprintf(stderr, "\n");
    }
#endif

    fprintf(stderr, "-- Control frame information "
	    "-----------------------------------------------\n");
    while ((void *)cfp < (void *)(th->stack + th->stack_size)) {
	control_frame_dump(th, cfp);
	cfp++;
    }
    fprintf(stderr, "\n");
}

void
rb_vmdebug_stack_dump_raw_current(void)
{
    rb_thread_t *th = GET_THREAD();
    rb_vmdebug_stack_dump_raw(th, th->cfp);
}

void
rb_vmdebug_env_dump_raw(rb_env_t *env, VALUE *ep)
{
    int i;
    fprintf(stderr, "-- env --------------------\n");

    while (env) {
	fprintf(stderr, "--\n");
	for (i = 0; i < env->env_size; i++) {
	    fprintf(stderr, "%04d: %08"PRIxVALUE" (%p)", -env->local_size + i, env->env[i],
		   (void *)&env->env[i]);
	    if (&env->env[i] == ep)
		fprintf(stderr, " <- ep");
	    fprintf(stderr, "\n");
	}

	if (env->prev_envval != 0) {
	    GetEnvPtr(env->prev_envval, env);
	}
	else {
	    env = 0;
	}
    }
    fprintf(stderr, "---------------------------\n");
}

void
rb_vmdebug_proc_dump_raw(rb_proc_t *proc)
{
    rb_env_t *env;
    char *selfstr;
    VALUE val = rb_inspect(proc->block.self);
    selfstr = StringValueCStr(val);

    fprintf(stderr, "-- proc -------------------\n");
    fprintf(stderr, "self: %s\n", selfstr);
    GetEnvPtr(proc->envval, env);
    rb_vmdebug_env_dump_raw(env, proc->block.ep);
}

void
rb_vmdebug_stack_dump_th(VALUE thval)
{
    rb_thread_t *th;
    GetThreadPtr(thval, th);
    rb_vmdebug_stack_dump_raw(th, th->cfp);
}

#if VMDEBUG > 2

/* copy from vm.c */
static VALUE *
vm_base_ptr(rb_control_frame_t *cfp)
{
    rb_control_frame_t *prev_cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
    VALUE *bp = prev_cfp->sp + cfp->iseq->local_size + 1;

    if (cfp->iseq->type == ISEQ_TYPE_METHOD) {
	bp += 1;
    }
    return bp;
}

static void
vm_stack_dump_each(rb_thread_t *th, rb_control_frame_t *cfp)
{
    int i;

    VALUE rstr;
    VALUE *sp = cfp->sp;
    VALUE *ep = cfp->ep;

    int argc = 0, local_size = 0;
    const char *name;
    rb_iseq_t *iseq = cfp->iseq;

    if (iseq == 0) {
	if (RUBYVM_CFUNC_FRAME_P(cfp)) {
	    name = rb_id2name(cfp->me->called_id);
	}
	else {
	    name = "?";
	}
    }
    else if (RUBY_VM_IFUNC_P(iseq)) {
	name = "<ifunc>";
    }
    else {
	argc = iseq->argc;
	local_size = iseq->local_size;
	name = RSTRING_PTR(iseq->location.label);
    }

    /* stack trace header */

    if (VM_FRAME_TYPE(cfp) == VM_FRAME_MAGIC_METHOD ||
	VM_FRAME_TYPE(cfp) == VM_FRAME_MAGIC_TOP ||
	VM_FRAME_TYPE(cfp) == VM_FRAME_MAGIC_BLOCK ||
	VM_FRAME_TYPE(cfp) == VM_FRAME_MAGIC_CLASS ||
	VM_FRAME_TYPE(cfp) == VM_FRAME_MAGIC_PROC ||
	VM_FRAME_TYPE(cfp) == VM_FRAME_MAGIC_LAMBDA ||
	VM_FRAME_TYPE(cfp) == VM_FRAME_MAGIC_CFUNC ||
	VM_FRAME_TYPE(cfp) == VM_FRAME_MAGIC_IFUNC ||
	VM_FRAME_TYPE(cfp) == VM_FRAME_MAGIC_EVAL) {

	VALUE *ptr = ep - local_size;

	control_frame_dump(th, cfp);

	for (i = 0; i < argc; i++) {
	    rstr = rb_inspect(*ptr);
	    fprintf(stderr, "  arg   %2d: %8s (%p)\n", i, StringValueCStr(rstr),
		   (void *)ptr++);
	}
	for (; i < local_size - 1; i++) {
	    rstr = rb_inspect(*ptr);
	    fprintf(stderr, "  local %2d: %8s (%p)\n", i, StringValueCStr(rstr),
		   (void *)ptr++);
	}

	ptr = vm_base_ptr(cfp);
	for (; ptr < sp; ptr++, i++) {
	    if (*ptr == Qundef) {
		rstr = rb_str_new2("undef");
	    }
	    else {
		rstr = rb_inspect(*ptr);
	    }
	    fprintf(stderr, "  stack %2d: %8s (%"PRIdPTRDIFF")\n", i, StringValueCStr(rstr),
		    (ptr - th->stack));
	}
    }
    else if (VM_FRAME_TYPE_FINISH_P(cfp)) {
	if ((th)->stack + (th)->stack_size > (VALUE *)(cfp + 1)) {
	    vm_stack_dump_each(th, cfp + 1);
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
rb_vmdebug_debug_print_register(rb_thread_t *th)
{
    rb_control_frame_t *cfp = th->cfp;
    ptrdiff_t pc = -1;
    ptrdiff_t ep = cfp->ep - th->stack;
    ptrdiff_t cfpi;

    if (RUBY_VM_NORMAL_ISEQ_P(cfp->iseq)) {
	pc = cfp->pc - cfp->iseq->iseq_encoded;
    }

    if (ep < 0 || (size_t)ep > th->stack_size) {
	ep = -1;
    }

    cfpi = ((rb_control_frame_t *)(th->stack + th->stack_size)) - cfp;
    fprintf(stderr, "  [PC] %04"PRIdPTRDIFF", [SP] %04"PRIdPTRDIFF", [EP] %04"PRIdPTRDIFF", [CFP] %04"PRIdPTRDIFF"\n",
	    pc, (cfp->sp - th->stack), ep, cfpi);
}

void
rb_vmdebug_thread_dump_regs(VALUE thval)
{
    rb_thread_t *th;
    GetThreadPtr(thval, th);
    rb_vmdebug_debug_print_register(th);
}

void
rb_vmdebug_debug_print_pre(rb_thread_t *th, rb_control_frame_t *cfp,VALUE *_pc)
{
    rb_iseq_t *iseq = cfp->iseq;

    if (iseq != 0) {
	VALUE *seq = iseq->iseq;
	ptrdiff_t pc = _pc - iseq->iseq_encoded;
	int i;

	for (i=0; i<(int)VM_CFP_CNT(th, cfp); i++) {
	    printf(" ");
	}
	printf("| ");
	if(0)printf("[%03ld] ", (long)(cfp->sp - th->stack));

	/* printf("%3"PRIdPTRDIFF" ", VM_CFP_CNT(th, cfp)); */
	if (pc >= 0) {
	    rb_iseq_disasm_insn(0, seq, (size_t)pc, iseq, 0);
	}
    }

#if VMDEBUG > 3
    fprintf(stderr, "        (1)");
    rb_vmdebug_debug_print_register(th);
#endif
}

void
rb_vmdebug_debug_print_post(rb_thread_t *th, rb_control_frame_t *cfp
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
    rb_vmdebug_debug_print_register(th);
#endif
    /* stack_dump_raw(th, cfp); */

#if VMDEBUG > 2
    /* stack_dump_thobj(th); */
    vm_stack_dump_each(th, th->cfp);

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
    rb_thread_t *th;
    rb_control_frame_t *cfp;
    GetThreadPtr(self, th);
    cfp = th->cfp;

    fprintf(stderr, "Thread state dump:\n");
    fprintf(stderr, "pc : %p, sp : %p\n", (void *)cfp->pc, (void *)cfp->sp);
    fprintf(stderr, "cfp: %p, ep : %p\n", (void *)cfp, (void *)cfp->ep);

    return Qnil;
}

#if defined(HAVE_BACKTRACE)
# if HAVE_LIBUNWIND
#  undef backtrace
#  define backtrace unw_backtrace
# elif defined(__APPLE__) && defined(__x86_64__)
#  define UNW_LOCAL_ONLY
#  include <libunwind.h>
#  undef backtrace
int backtrace (void **trace, int size) {
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
	/* get _sigtramp's ucontext_t and set values to cursor
	 * http://www.opensource.apple.com/source/Libc/Libc-825.25/i386/sys/_sigtramp.s
	 * http://www.opensource.apple.com/source/libunwind/libunwind-35.1/src/unw_getcontext.s
	 */
	unw_get_reg(&cursor, UNW_X86_64_RBX, &ip);
	uctx = (ucontext_t *)ip;
	unw_set_reg(&cursor, UNW_X86_64_RAX, uctx->uc_mcontext->__ss.__rax);
	unw_set_reg(&cursor, UNW_X86_64_RBX, uctx->uc_mcontext->__ss.__rbx);
	unw_set_reg(&cursor, UNW_X86_64_RCX, uctx->uc_mcontext->__ss.__rcx);
	unw_set_reg(&cursor, UNW_X86_64_RDX, uctx->uc_mcontext->__ss.__rdx);
	unw_set_reg(&cursor, UNW_X86_64_RDI, uctx->uc_mcontext->__ss.__rdi);
	unw_set_reg(&cursor, UNW_X86_64_RSI, uctx->uc_mcontext->__ss.__rsi);
	unw_set_reg(&cursor, UNW_X86_64_RBP, uctx->uc_mcontext->__ss.__rbp);
	unw_set_reg(&cursor, UNW_X86_64_RSP, 8+(uctx->uc_mcontext->__ss.__rsp));
	unw_set_reg(&cursor, UNW_X86_64_R8,  uctx->uc_mcontext->__ss.__r8);
	unw_set_reg(&cursor, UNW_X86_64_R9,  uctx->uc_mcontext->__ss.__r9);
	unw_set_reg(&cursor, UNW_X86_64_R10, uctx->uc_mcontext->__ss.__r10);
	unw_set_reg(&cursor, UNW_X86_64_R11, uctx->uc_mcontext->__ss.__r11);
	unw_set_reg(&cursor, UNW_X86_64_R12, uctx->uc_mcontext->__ss.__r12);
	unw_set_reg(&cursor, UNW_X86_64_R13, uctx->uc_mcontext->__ss.__r13);
	unw_set_reg(&cursor, UNW_X86_64_R14, uctx->uc_mcontext->__ss.__r14);
	unw_set_reg(&cursor, UNW_X86_64_R15, uctx->uc_mcontext->__ss.__r15);
	ip = *(unw_word_t*)uctx->uc_mcontext->__ss.__rsp;
	unw_set_reg(&cursor, UNW_REG_IP, ip);
	trace[n++] = (void *)uctx->uc_mcontext->__ss.__rip;
	trace[n++] = (void *)ip;
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
    int n = backtrace(trace, MAX_NATIVE_TRACE);
    char **syms = backtrace_symbols(trace, n);

    if (syms) {
#ifdef USE_ELF
	rb_dump_backtrace_with_lines(n, trace, syms);
#else
	int i;
	for (i=0; i<n; i++) {
	    fprintf(stderr, "%s\n", syms[i]);
	}
#endif
	free(syms);
    }
#elif defined(_WIN32)
    DWORD tid = GetCurrentThreadId();
    HANDLE th = (HANDLE)_beginthread(dump_thread, 0, &tid);
    if (th != (HANDLE)-1)
	WaitForSingleObject(th, INFINITE);
#endif
}

void
rb_vm_bugreport(void)
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

#if defined __APPLE__
    fputs("-- Crash Report log information "
	  "--------------------------------------------\n"
	  "   See Crash Report log file under the one of following:\n"
	  "     * ~/Library/Logs/CrashReporter\n"
	  "     * /Library/Logs/CrashReporter\n"
	  "     * ~/Library/Logs/DiagnosticReports\n"
	  "     * /Library/Logs/DiagnosticReports\n"
	  "   for more details.\n"
	  "\n",
	  stderr);
#endif
    if (vm) {
	SDR();
	rb_backtrace_print_as_bugreport();
	fputs("\n", stderr);
    }

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
		name = rb_class_name(name);
		fprintf(stderr, " %4d %s:%.*s\n", i, type,
			LIMITED_NAME_LENGTH(name), RSTRING_PTR(name));
	    }
	    else {
		VALUE klass = rb_class_name(CLASS_OF(name));
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
    }
}
