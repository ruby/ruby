/**********************************************************************

  vm_dump.c -

  $Author$

  Copyright (C) 2004-2007 Koichi Sasada

**********************************************************************/


#include "ruby/ruby.h"
#include "vm_core.h"

#define MAX_POSBUF 128

#define VM_CFP_CNT(th, cfp) \
  ((rb_control_frame_t *)(th->stack + th->stack_size) - (rb_control_frame_t *)(cfp))

static void
control_frame_dump(rb_thread_t *th, rb_control_frame_t *cfp)
{
    ptrdiff_t pc = -1, bp = -1;
    ptrdiff_t lfp = cfp->lfp - th->stack;
    ptrdiff_t dfp = cfp->dfp - th->stack;
    char lfp_in_heap = ' ', dfp_in_heap = ' ';
    char posbuf[MAX_POSBUF+1];
    int line = 0;
    int nopos = 0;

    const char *magic, *iseq_name = "-", *selfstr = "-", *biseq_name = "-";
    VALUE tmp;

    if (cfp->block_iseq != 0 && BUILTIN_TYPE(cfp->block_iseq) != T_NODE) {
	biseq_name = "";	/* RSTRING(cfp->block_iseq->name)->ptr; */
    }

    if (lfp < 0 || (size_t)lfp > th->stack_size) {
	lfp = (ptrdiff_t)cfp->lfp;
	lfp_in_heap = 'p';
    }
    if (dfp < 0 || (size_t)dfp > th->stack_size) {
	dfp = (ptrdiff_t)cfp->dfp;
	dfp_in_heap = 'p';
    }
    if (cfp->bp) {
	bp = cfp->bp - th->stack;
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
      case VM_FRAME_MAGIC_FINISH:
	magic = "FINISH";
	nopos = 1;
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

    if (nopos) {
	/* no name */
    }
    else if (cfp->iseq != 0) {
	if (RUBY_VM_IFUNC_P(cfp->iseq)) {
	    iseq_name = "<ifunc>";
	}
	else {
	    int rb_vm_get_sourceline(rb_control_frame_t *);

	    pc = cfp->pc - cfp->iseq->iseq_encoded;
	    iseq_name = RSTRING_PTR(cfp->iseq->name);
	    line = rb_vm_get_sourceline(cfp);
	    if (line) {
		snprintf(posbuf, MAX_POSBUF, "%s:%d", RSTRING_PTR(cfp->iseq->filename), line);
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
    fprintf(stderr, "s:%04"PRIdPTRDIFF" b:%04"PRIdPTRDIFF" ", (cfp->sp - th->stack), bp);
    fprintf(stderr, lfp_in_heap == ' ' ? "l:%06"PRIdPTRDIFF" " : "l:%06"PRIxPTRDIFF" ", lfp % 10000);
    fprintf(stderr, dfp_in_heap == ' ' ? "d:%06"PRIdPTRDIFF" " : "d:%06"PRIxPTRDIFF" ", dfp % 10000);
    fprintf(stderr, "%-6s", magic);
    if (line && !nopos) {
	fprintf(stderr, " %s", posbuf);
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
    VALUE *sp = cfp->sp, *bp = cfp->bp;
    VALUE *lfp = cfp->lfp;
    VALUE *dfp = cfp->dfp;
    VALUE *p, *st, *t;

    fprintf(stderr, "-- stack frame ------------\n");
    for (p = st = th->stack; p < sp; p++) {
	fprintf(stderr, "%04ld (%p): %08"PRIxVALUE, (long)(p - st), p, *p);

	t = (VALUE *)*p;
	if (th->stack <= t && t < sp) {
	    fprintf(stderr, " (= %ld)", (long)((VALUE *)GC_GUARDED_PTR_REF(t) - th->stack));
	}

	if (p == lfp)
	    fprintf(stderr, " <- lfp");
	if (p == dfp)
	    fprintf(stderr, " <- dfp");
	if (p == bp)
	    fprintf(stderr, " <- bp");	/* should not be */

	fprintf(stderr, "\n");
    }
#endif

    fprintf(stderr, "-- control frame ----------\n");
    while ((void *)cfp < (void *)(th->stack + th->stack_size)) {
	control_frame_dump(th, cfp);
	cfp++;
    }
    fprintf(stderr, "---------------------------\n");
}

void
rb_vmdebug_stack_dump_raw_current(void)
{
    rb_thread_t *th = GET_THREAD();
    rb_vmdebug_stack_dump_raw(th, th->cfp);
}

void
rb_vmdebug_env_dump_raw(rb_env_t *env, VALUE *lfp, VALUE *dfp)
{
    int i;
    fprintf(stderr, "-- env --------------------\n");

    while (env) {
	fprintf(stderr, "--\n");
	for (i = 0; i < env->env_size; i++) {
	    fprintf(stderr, "%04d: %08lx (%p)", -env->local_size + i, env->env[i],
		   (void *)&env->env[i]);
	    if (&env->env[i] == lfp)
		fprintf(stderr, " <- lfp");
	    if (&env->env[i] == dfp)
		fprintf(stderr, " <- dfp");
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
    rb_vmdebug_env_dump_raw(env, proc->block.lfp, proc->block.dfp);
}

void
rb_vmdebug_stack_dump_th(VALUE thval)
{
    rb_thread_t *th;
    GetThreadPtr(thval, th);
    rb_vmdebug_stack_dump_raw(th, th->cfp);
}

#if VMDEBUG > 2
static void
vm_stack_dump_each(rb_thread_t *th, rb_control_frame_t *cfp)
{
    int i;

    VALUE rstr;
    VALUE *sp = cfp->sp;
    VALUE *lfp = cfp->lfp;
    VALUE *dfp = cfp->dfp;

    int argc = 0, local_size = 0;
    const char *name;
    rb_iseq_t *iseq = cfp->iseq;

    if (iseq == 0) {
	if (RUBYVM_CFUNC_FRAME_P(cfp)) {
	    name = rb_id2name(cfp->me->original_id);
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
	name = RSTRING_PTR(iseq->name);
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

	VALUE *ptr = dfp - local_size;

	vm_stack_dump_each(th, cfp + 1);
	control_frame_dump(th, cfp);

	if (lfp != dfp) {
	    local_size++;
	}
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

	ptr = cfp->bp;
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
    else if (VM_FRAME_TYPE(cfp) == VM_FRAME_MAGIC_FINISH) {
	if ((th)->stack + (th)->stack_size > (VALUE *)(cfp + 2)) {
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
    ptrdiff_t lfp = cfp->lfp - th->stack;
    ptrdiff_t dfp = cfp->dfp - th->stack;
    ptrdiff_t cfpi;

    if (RUBY_VM_NORMAL_ISEQ_P(cfp->iseq)) {
	pc = cfp->pc - cfp->iseq->iseq_encoded;
    }

    if (lfp < 0 || (size_t)lfp > th->stack_size)
	lfp = -1;
    if (dfp < 0 || (size_t)dfp > th->stack_size)
	dfp = -1;

    cfpi = ((rb_control_frame_t *)(th->stack + th->stack_size)) - cfp;
    fprintf(stderr, "  [PC] %04"PRIdPTRDIFF", [SP] %04"PRIdPTRDIFF", [LFP] %04"PRIdPTRDIFF", [DFP] %04"PRIdPTRDIFF", [CFP] %04"PRIdPTRDIFF"\n",
	    pc, (cfp->sp - th->stack), lfp, dfp, cfpi);
}

void
rb_vmdebug_thread_dump_regs(VALUE thval)
{
    rb_thread_t *th;
    GetThreadPtr(thval, th);
    rb_vmdebug_debug_print_register(th);
}

void
rb_vmdebug_debug_print_pre(rb_thread_t *th, rb_control_frame_t *cfp)
{
    rb_iseq_t *iseq = cfp->iseq;

    if (iseq != 0 && VM_FRAME_TYPE(cfp) != VM_FRAME_MAGIC_FINISH) {
	VALUE *seq = iseq->iseq;
	ptrdiff_t pc = cfp->pc - iseq->iseq_encoded;

	printf("%3"PRIdPTRDIFF" ", VM_CFP_CNT(th, cfp));
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

#ifdef COLLECT_USAGE_ANALYSIS
/* uh = {
 *   insn(Fixnum) => ihash(Hash)
 * }
 * ihash = {
 *   -1(Fixnum) => count,      # insn usage
 *    0(Fixnum) => ophash,     # operand usage
 * }
 * ophash = {
 *   val(interned string) => count(Fixnum)
 * }
 */
void
vm_analysis_insn(int insn)
{
    ID usage_hash;
    ID bigram_hash;
    static int prev_insn = -1;

    VALUE uh;
    VALUE ihash;
    VALUE cv;

    CONST_ID(usage_hash, "USAGE_ANALYSIS_INSN");
    CONST_ID(bigram_hash, "USAGE_ANALYSIS_INSN_BIGRAM");
    uh = rb_const_get(rb_cRubyVM, usage_hash);
    if ((ihash = rb_hash_aref(uh, INT2FIX(insn))) == Qnil) {
	ihash = rb_hash_new();
	rb_hash_aset(uh, INT2FIX(insn), ihash);
    }
    if ((cv = rb_hash_aref(ihash, INT2FIX(-1))) == Qnil) {
	cv = INT2FIX(0);
    }
    rb_hash_aset(ihash, INT2FIX(-1), INT2FIX(FIX2INT(cv) + 1));

    /* calc bigram */
    if (prev_insn != -1) {
	VALUE bi;
	VALUE ary[2];
	VALUE cv;

	ary[0] = INT2FIX(prev_insn);
	ary[1] = INT2FIX(insn);
	bi = rb_ary_new4(2, &ary[0]);

	uh = rb_const_get(rb_cRubyVM, bigram_hash);
	if ((cv = rb_hash_aref(uh, bi)) == Qnil) {
	    cv = INT2FIX(0);
	}
	rb_hash_aset(uh, bi, INT2FIX(FIX2INT(cv) + 1));
    }
    prev_insn = insn;
}

/* from disasm.c */
extern VALUE insn_operand_intern(int insn, int op_no, VALUE op,
				 int len, int pos, VALUE child);

void
vm_analysis_operand(int insn, int n, VALUE op)
{
    ID usage_hash;

    VALUE uh;
    VALUE ihash;
    VALUE ophash;
    VALUE valstr;
    VALUE cv;

    CONST_ID(usage_hash, "USAGE_ANALYSIS_INSN");

    uh = rb_const_get(rb_cRubyVM, usage_hash);
    if ((ihash = rb_hash_aref(uh, INT2FIX(insn))) == Qnil) {
	ihash = rb_hash_new();
	rb_hash_aset(uh, INT2FIX(insn), ihash);
    }
    if ((ophash = rb_hash_aref(ihash, INT2FIX(n))) == Qnil) {
	ophash = rb_hash_new();
	rb_hash_aset(ihash, INT2FIX(n), ophash);
    }
    /* intern */
    valstr = insn_operand_intern(insn, n, op, 0, 0, 0);

    /* set count */
    if ((cv = rb_hash_aref(ophash, valstr)) == Qnil) {
	cv = INT2FIX(0);
    }
    rb_hash_aset(ophash, valstr, INT2FIX(FIX2INT(cv) + 1));
}

void
vm_analysis_register(int reg, int isset)
{
    ID usage_hash;
    VALUE uh;
    VALUE rhash;
    VALUE valstr;
    static const char regstrs[][5] = {
	"pc",			/* 0 */
	"sp",			/* 1 */
	"cfp",			/* 2 */
	"lfp",			/* 3 */
	"dfp",			/* 4 */
	"self",			/* 5 */
	"iseq",			/* 6 */
    };
    static const char getsetstr[][4] = {
	"get",
	"set",
    };
    static VALUE syms[sizeof(regstrs) / sizeof(regstrs[0])][2];

    VALUE cv;

    CONST_ID(usage_hash, "USAGE_ANALYSIS_REGS");
    if (syms[0] == 0) {
	char buff[0x10];
	int i;

	for (i = 0; i < sizeof(regstrs) / sizeof(regstrs[0]); i++) {
	    int j;
	    for (j = 0; j < 2; j++) {
		snfprintf(stderr, buff, 0x10, "%d %s %-4s", i, getsetstr[j],
			 regstrs[i]);
		syms[i][j] = ID2SYM(rb_intern(buff));
	    }
	}
    }
    valstr = syms[reg][isset];

    uh = rb_const_get(rb_cRubyVM, usage_hash);
    if ((cv = rb_hash_aref(uh, valstr)) == Qnil) {
	cv = INT2FIX(0);
    }
    rb_hash_aset(uh, valstr, INT2FIX(FIX2INT(cv) + 1));
}


#endif

VALUE
rb_vmdebug_thread_dump_state(VALUE self)
{
    rb_thread_t *th;
    rb_control_frame_t *cfp;
    GetThreadPtr(self, th);
    cfp = th->cfp;

    fprintf(stderr, "Thread state dump:\n");
    fprintf(stderr, "pc : %p, sp : %p\n", (void *)cfp->pc, (void *)cfp->sp);
    fprintf(stderr, "cfp: %p, lfp: %p, dfp: %p\n", (void *)cfp, (void *)cfp->lfp, (void *)cfp->dfp);

    return Qnil;
}

static int
bugreport_backtrace(void *arg, VALUE file, int line, VALUE method)
{
    const char *filename = NIL_P(file) ? "ruby" : RSTRING_PTR(file);
    if (!*(int *)arg) {
	fprintf(stderr, "-- Ruby level backtrace information "
		"----------------------------------------\n");
	*(int *)arg = 1;
    }
    if (NIL_P(method)) {
	fprintf(stderr, "%s:%d:in unknown method\n", filename, line);
    }
    else {
	fprintf(stderr, "%s:%d:in `%s'\n", filename, line, RSTRING_PTR(method));
    }
    return 0;
}

#if HAVE_BACKTRACE
#include <execinfo.h>
#endif
void
rb_vm_bugreport(void)
{
    if (GET_THREAD()->vm) {
	int i = 0;
	SDR();

	if (rb_backtrace_each(bugreport_backtrace, &i)) {
	    fputs("\n", stderr);
	}
    }

#if HAVE_BACKTRACE
#define MAX_NATIVE_TRACE 1024
    {
	static void *trace[MAX_NATIVE_TRACE];
	int n = backtrace(trace, MAX_NATIVE_TRACE);
	char **syms = backtrace_symbols(trace, n);
	int i;

	fprintf(stderr, "-- C level backtrace information "
		"-------------------------------------------\n");
	if (syms) {
	    for (i=0; i<n; i++) {
		fprintf(stderr, "%s\n", syms[i]);
	    }
	    free(syms);
	}
	fprintf(stderr, "\n");
    }
#endif
}
