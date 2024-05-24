/**********************************************************************

  vm_insnhelper.c - instruction helper functions.

  $Author$

  Copyright (C) 2007 Koichi Sasada

**********************************************************************/

#include "ruby/internal/config.h"

#include <math.h>

#include "constant.h"
#include "debug_counter.h"
#include "internal.h"
#include "internal/class.h"
#include "internal/compar.h"
#include "internal/hash.h"
#include "internal/numeric.h"
#include "internal/proc.h"
#include "internal/random.h"
#include "internal/variable.h"
#include "internal/struct.h"
#include "variable.h"

/* finish iseq array */
#include "insns.inc"
#include "insns_info.inc"

extern rb_method_definition_t *rb_method_definition_create(rb_method_type_t type, ID mid);
extern void rb_method_definition_set(const rb_method_entry_t *me, rb_method_definition_t *def, void *opts);
extern int rb_method_definition_eq(const rb_method_definition_t *d1, const rb_method_definition_t *d2);
extern VALUE rb_make_no_method_exception(VALUE exc, VALUE format, VALUE obj,
                                         int argc, const VALUE *argv, int priv);

static const struct rb_callcache vm_empty_cc;
static const struct rb_callcache vm_empty_cc_for_super;

/* control stack frame */

static rb_control_frame_t *vm_get_ruby_level_caller_cfp(const rb_execution_context_t *ec, const rb_control_frame_t *cfp);

VALUE
ruby_vm_special_exception_copy(VALUE exc)
{
    VALUE e = rb_obj_alloc(rb_class_real(RBASIC_CLASS(exc)));
    rb_obj_copy_ivar(e, exc);
    return e;
}

NORETURN(static void ec_stack_overflow(rb_execution_context_t *ec, int));
static void
ec_stack_overflow(rb_execution_context_t *ec, int setup)
{
    VALUE mesg = rb_ec_vm_ptr(ec)->special_exceptions[ruby_error_sysstack];
    ec->raised_flag = RAISED_STACKOVERFLOW;
    if (setup) {
        VALUE at = rb_ec_backtrace_object(ec);
        mesg = ruby_vm_special_exception_copy(mesg);
        rb_ivar_set(mesg, idBt, at);
        rb_ivar_set(mesg, idBt_locations, at);
    }
    ec->errinfo = mesg;
    EC_JUMP_TAG(ec, TAG_RAISE);
}

NORETURN(static void vm_stackoverflow(void));

static void
vm_stackoverflow(void)
{
    ec_stack_overflow(GET_EC(), TRUE);
}

NORETURN(void rb_ec_stack_overflow(rb_execution_context_t *ec, int crit));
void
rb_ec_stack_overflow(rb_execution_context_t *ec, int crit)
{
    if (rb_during_gc()) {
        rb_bug("system stack overflow during GC. Faulty native extension?");
    }
    if (crit) {
        ec->raised_flag = RAISED_STACKOVERFLOW;
        ec->errinfo = rb_ec_vm_ptr(ec)->special_exceptions[ruby_error_stackfatal];
        EC_JUMP_TAG(ec, TAG_RAISE);
    }
#ifdef USE_SIGALTSTACK
    ec_stack_overflow(ec, TRUE);
#else
    ec_stack_overflow(ec, FALSE);
#endif
}

static inline void stack_check(rb_execution_context_t *ec);

#if VM_CHECK_MODE > 0
static int
callable_class_p(VALUE klass)
{
#if VM_CHECK_MODE >= 2
    if (!klass) return FALSE;
    switch (RB_BUILTIN_TYPE(klass)) {
      default:
        break;
      case T_ICLASS:
        if (!RB_TYPE_P(RCLASS_SUPER(klass), T_MODULE)) break;
      case T_MODULE:
        return TRUE;
    }
    while (klass) {
        if (klass == rb_cBasicObject) {
            return TRUE;
        }
        klass = RCLASS_SUPER(klass);
    }
    return FALSE;
#else
    return klass != 0;
#endif
}

static int
callable_method_entry_p(const rb_callable_method_entry_t *cme)
{
    if (cme == NULL) {
        return TRUE;
    }
    else {
        VM_ASSERT(IMEMO_TYPE_P((VALUE)cme, imemo_ment));

        if (callable_class_p(cme->defined_class)) {
            return TRUE;
        }
        else {
            return FALSE;
        }
    }
}

static void
vm_check_frame_detail(VALUE type, int req_block, int req_me, int req_cref, VALUE specval, VALUE cref_or_me, int is_cframe, const rb_iseq_t *iseq)
{
    unsigned int magic = (unsigned int)(type & VM_FRAME_MAGIC_MASK);
    enum imemo_type cref_or_me_type = imemo_env; /* impossible value */

    if (RB_TYPE_P(cref_or_me, T_IMEMO)) {
        cref_or_me_type = imemo_type(cref_or_me);
    }
    if (type & VM_FRAME_FLAG_BMETHOD) {
        req_me = TRUE;
    }

    if (req_block && (type & VM_ENV_FLAG_LOCAL) == 0) {
        rb_bug("vm_push_frame: specval (%p) should be a block_ptr on %x frame", (void *)specval, magic);
    }
    if (!req_block && (type & VM_ENV_FLAG_LOCAL) != 0) {
        rb_bug("vm_push_frame: specval (%p) should not be a block_ptr on %x frame", (void *)specval, magic);
    }

    if (req_me) {
        if (cref_or_me_type != imemo_ment) {
            rb_bug("vm_push_frame: (%s) should be method entry on %x frame", rb_obj_info(cref_or_me), magic);
        }
    }
    else {
        if (req_cref && cref_or_me_type != imemo_cref) {
            rb_bug("vm_push_frame: (%s) should be CREF on %x frame", rb_obj_info(cref_or_me), magic);
        }
        else { /* cref or Qfalse */
            if (cref_or_me != Qfalse && cref_or_me_type != imemo_cref) {
                if (((type & VM_FRAME_FLAG_LAMBDA) || magic == VM_FRAME_MAGIC_IFUNC) && (cref_or_me_type == imemo_ment)) {
                    /* ignore */
                }
                else {
                    rb_bug("vm_push_frame: (%s) should be false or cref on %x frame", rb_obj_info(cref_or_me), magic);
                }
            }
        }
    }

    if (cref_or_me_type == imemo_ment) {
        const rb_callable_method_entry_t *me = (const rb_callable_method_entry_t *)cref_or_me;

        if (!callable_method_entry_p(me)) {
            rb_bug("vm_push_frame: ment (%s) should be callable on %x frame.", rb_obj_info(cref_or_me), magic);
        }
    }

    if ((type & VM_FRAME_MAGIC_MASK) == VM_FRAME_MAGIC_DUMMY) {
        VM_ASSERT(iseq == NULL ||
                  RBASIC_CLASS((VALUE)iseq) == 0 || // dummy frame for loading
                  RUBY_VM_NORMAL_ISEQ_P(iseq) //argument error
                  );
    }
    else {
        VM_ASSERT(is_cframe == !RUBY_VM_NORMAL_ISEQ_P(iseq));
    }
}

static void
vm_check_frame(VALUE type,
               VALUE specval,
               VALUE cref_or_me,
               const rb_iseq_t *iseq)
{
    VALUE given_magic = type & VM_FRAME_MAGIC_MASK;
    VM_ASSERT(FIXNUM_P(type));

#define CHECK(magic, req_block, req_me, req_cref, is_cframe) \
    case magic: \
      vm_check_frame_detail(type, req_block, req_me, req_cref, \
                            specval, cref_or_me, is_cframe, iseq); \
      break
    switch (given_magic) {
        /*                           BLK    ME     CREF   CFRAME */
        CHECK(VM_FRAME_MAGIC_METHOD, TRUE,  TRUE,  FALSE, FALSE);
        CHECK(VM_FRAME_MAGIC_CLASS,  TRUE,  FALSE, TRUE,  FALSE);
        CHECK(VM_FRAME_MAGIC_TOP,    TRUE,  FALSE, TRUE,  FALSE);
        CHECK(VM_FRAME_MAGIC_CFUNC,  TRUE,  TRUE,  FALSE, TRUE);
        CHECK(VM_FRAME_MAGIC_BLOCK,  FALSE, FALSE, FALSE, FALSE);
        CHECK(VM_FRAME_MAGIC_IFUNC,  FALSE, FALSE, FALSE, TRUE);
        CHECK(VM_FRAME_MAGIC_EVAL,   FALSE, FALSE, FALSE, FALSE);
        CHECK(VM_FRAME_MAGIC_RESCUE, FALSE, FALSE, FALSE, FALSE);
        CHECK(VM_FRAME_MAGIC_DUMMY,  TRUE,  FALSE, FALSE, FALSE);
      default:
        rb_bug("vm_push_frame: unknown type (%x)", (unsigned int)given_magic);
    }
#undef CHECK
}

static VALUE vm_stack_canary; /* Initialized later */
static bool vm_stack_canary_was_born = false;

// Return the index of the instruction right before the given PC.
// This is needed because insn_entry advances PC before the insn body.
static unsigned int
previous_insn_index(const rb_iseq_t *iseq, const VALUE *pc)
{
    unsigned int pos = 0;
    while (pos < ISEQ_BODY(iseq)->iseq_size) {
        int opcode = rb_vm_insn_addr2opcode((void *)ISEQ_BODY(iseq)->iseq_encoded[pos]);
        unsigned int next_pos = pos + insn_len(opcode);
        if (ISEQ_BODY(iseq)->iseq_encoded + next_pos == pc) {
            return pos;
        }
        pos = next_pos;
    }
    rb_bug("failed to find the previous insn");
}

void
rb_vm_check_canary(const rb_execution_context_t *ec, VALUE *sp)
{
    const struct rb_control_frame_struct *reg_cfp = ec->cfp;
    const struct rb_iseq_struct *iseq;

    if (! LIKELY(vm_stack_canary_was_born)) {
        return; /* :FIXME: isn't it rather fatal to enter this branch?  */
    }
    else if ((VALUE *)reg_cfp == ec->vm_stack + ec->vm_stack_size) {
        /* This is at the very beginning of a thread. cfp does not exist. */
        return;
    }
    else if (! (iseq = GET_ISEQ())) {
        return;
    }
    else if (LIKELY(sp[0] != vm_stack_canary)) {
        return;
    }
    else {
        /* we are going to call methods below; squash the canary to
         * prevent infinite loop. */
        sp[0] = Qundef;
    }

    const VALUE *orig = rb_iseq_original_iseq(iseq);
    const VALUE iseqw = rb_iseqw_new(iseq);
    const VALUE inspection = rb_inspect(iseqw);
    const char *stri = rb_str_to_cstr(inspection);
    const VALUE disasm = rb_iseq_disasm(iseq);
    const char *strd = rb_str_to_cstr(disasm);
    const ptrdiff_t pos = previous_insn_index(iseq, GET_PC());
    const enum ruby_vminsn_type insn = (enum ruby_vminsn_type)orig[pos];
    const char *name = insn_name(insn);

    /* rb_bug() is not capable of outputting this large contents.  It
       is designed to run form a SIGSEGV handler, which tends to be
       very restricted. */
    ruby_debug_printf(
        "We are killing the stack canary set by %s, "
        "at %s@pc=%"PRIdPTR"\n"
        "watch out the C stack trace.\n"
        "%s",
        name, stri, pos, strd);
    rb_bug("see above.");
}
#define vm_check_canary(ec, sp) rb_vm_check_canary(ec, sp)

#else
#define vm_check_canary(ec, sp)
#define vm_check_frame(a, b, c, d)
#endif /* VM_CHECK_MODE > 0 */

#if USE_DEBUG_COUNTER
static void
vm_push_frame_debug_counter_inc(
    const struct rb_execution_context_struct *ec,
    const struct rb_control_frame_struct *reg_cfp,
    VALUE type)
{
    const struct rb_control_frame_struct *prev_cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(reg_cfp);

    RB_DEBUG_COUNTER_INC(frame_push);

    if (RUBY_VM_END_CONTROL_FRAME(ec) != prev_cfp) {
        const bool curr = VM_FRAME_RUBYFRAME_P(reg_cfp);
        const bool prev = VM_FRAME_RUBYFRAME_P(prev_cfp);
        if (prev) {
            if (curr) {
                RB_DEBUG_COUNTER_INC(frame_R2R);
            }
            else {
                RB_DEBUG_COUNTER_INC(frame_R2C);
            }
        }
        else {
            if (curr) {
                RB_DEBUG_COUNTER_INC(frame_C2R);
            }
            else {
                RB_DEBUG_COUNTER_INC(frame_C2C);
            }
        }
    }

    switch (type & VM_FRAME_MAGIC_MASK) {
      case VM_FRAME_MAGIC_METHOD: RB_DEBUG_COUNTER_INC(frame_push_method); return;
      case VM_FRAME_MAGIC_BLOCK:  RB_DEBUG_COUNTER_INC(frame_push_block);  return;
      case VM_FRAME_MAGIC_CLASS:  RB_DEBUG_COUNTER_INC(frame_push_class);  return;
      case VM_FRAME_MAGIC_TOP:    RB_DEBUG_COUNTER_INC(frame_push_top);    return;
      case VM_FRAME_MAGIC_CFUNC:  RB_DEBUG_COUNTER_INC(frame_push_cfunc);  return;
      case VM_FRAME_MAGIC_IFUNC:  RB_DEBUG_COUNTER_INC(frame_push_ifunc);  return;
      case VM_FRAME_MAGIC_EVAL:   RB_DEBUG_COUNTER_INC(frame_push_eval);   return;
      case VM_FRAME_MAGIC_RESCUE: RB_DEBUG_COUNTER_INC(frame_push_rescue); return;
      case VM_FRAME_MAGIC_DUMMY:  RB_DEBUG_COUNTER_INC(frame_push_dummy);  return;
    }

    rb_bug("unreachable");
}
#else
#define vm_push_frame_debug_counter_inc(ec, cfp, t) /* void */
#endif

// Return a poison value to be set above the stack top to verify leafness.
VALUE
rb_vm_stack_canary(void)
{
#if VM_CHECK_MODE > 0
    return vm_stack_canary;
#else
    return 0;
#endif
}

STATIC_ASSERT(VM_ENV_DATA_INDEX_ME_CREF, VM_ENV_DATA_INDEX_ME_CREF == -2);
STATIC_ASSERT(VM_ENV_DATA_INDEX_SPECVAL, VM_ENV_DATA_INDEX_SPECVAL == -1);
STATIC_ASSERT(VM_ENV_DATA_INDEX_FLAGS,   VM_ENV_DATA_INDEX_FLAGS   == -0);

static void
vm_push_frame(rb_execution_context_t *ec,
              const rb_iseq_t *iseq,
              VALUE type,
              VALUE self,
              VALUE specval,
              VALUE cref_or_me,
              const VALUE *pc,
              VALUE *sp,
              int local_size,
              int stack_max)
{
    rb_control_frame_t *const cfp = RUBY_VM_NEXT_CONTROL_FRAME(ec->cfp);

    vm_check_frame(type, specval, cref_or_me, iseq);
    VM_ASSERT(local_size >= 0);

    /* check stack overflow */
    CHECK_VM_STACK_OVERFLOW0(cfp, sp, local_size + stack_max);
    vm_check_canary(ec, sp);

    /* setup vm value stack */

    /* initialize local variables */
    for (int i=0; i < local_size; i++) {
        *sp++ = Qnil;
    }

    /* setup ep with managing data */
    *sp++ = cref_or_me; /* ep[-2] / Qnil or T_IMEMO(cref) or T_IMEMO(ment) */
    *sp++ = specval     /* ep[-1] / block handler or prev env ptr */;
    *sp++ = type;       /* ep[-0] / ENV_FLAGS */

    /* setup new frame */
    *cfp = (const struct rb_control_frame_struct) {
        .pc         = pc,
        .sp         = sp,
        .iseq       = iseq,
        .self       = self,
        .ep         = sp - 1,
        .block_code = NULL,
#if VM_DEBUG_BP_CHECK
        .bp_check   = sp,
#endif
        .jit_return = NULL
    };

    ec->cfp = cfp;

    if (VMDEBUG == 2) {
        SDR();
    }
    vm_push_frame_debug_counter_inc(ec, cfp, type);
}

void
rb_vm_pop_frame_no_int(rb_execution_context_t *ec)
{
    rb_control_frame_t *cfp = ec->cfp;

    if (VM_CHECK_MODE >= 4) rb_gc_verify_internal_consistency();
    if (VMDEBUG == 2)       SDR();

    ec->cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
}

/* return TRUE if the frame is finished */
static inline int
vm_pop_frame(rb_execution_context_t *ec, rb_control_frame_t *cfp, const VALUE *ep)
{
    VALUE flags = ep[VM_ENV_DATA_INDEX_FLAGS];

    if (VM_CHECK_MODE >= 4) rb_gc_verify_internal_consistency();
    if (VMDEBUG == 2)       SDR();

    RUBY_VM_CHECK_INTS(ec);
    ec->cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);

    return flags & VM_FRAME_FLAG_FINISH;
}

void
rb_vm_pop_frame(rb_execution_context_t *ec)
{
    vm_pop_frame(ec, ec->cfp, ec->cfp->ep);
}

// it pushes pseudo-frame with fname filename.
VALUE
rb_vm_push_frame_fname(rb_execution_context_t *ec, VALUE fname)
{
    VALUE tmpbuf = rb_imemo_tmpbuf_auto_free_pointer();
    void *ptr = ruby_xcalloc(sizeof(struct rb_iseq_constant_body) + sizeof(struct rb_iseq_struct), 1);
    rb_imemo_tmpbuf_set_ptr(tmpbuf, ptr);

    struct rb_iseq_struct *dmy_iseq = (struct rb_iseq_struct *)ptr;
    struct rb_iseq_constant_body *dmy_body = (struct rb_iseq_constant_body *)&dmy_iseq[1];
    dmy_iseq->body = dmy_body;
    dmy_body->type = ISEQ_TYPE_TOP;
    dmy_body->location.pathobj = fname;

    vm_push_frame(ec,
                  dmy_iseq, //const rb_iseq_t *iseq,
                  VM_FRAME_MAGIC_DUMMY | VM_ENV_FLAG_LOCAL | VM_FRAME_FLAG_FINISH, // VALUE type,
                  ec->cfp->self, // VALUE self,
                  VM_BLOCK_HANDLER_NONE, // VALUE specval,
                  Qfalse, // VALUE cref_or_me,
                  NULL, // const VALUE *pc,
                  ec->cfp->sp, // VALUE *sp,
                  0, // int local_size,
                  0); // int stack_max

    return tmpbuf;
}

/* method dispatch */
static inline VALUE
rb_arity_error_new(int argc, int min, int max)
{
    VALUE err_mess = rb_sprintf("wrong number of arguments (given %d, expected %d", argc, min);
    if (min == max) {
        /* max is not needed */
    }
    else if (max == UNLIMITED_ARGUMENTS) {
        rb_str_cat_cstr(err_mess, "+");
    }
    else {
        rb_str_catf(err_mess, "..%d", max);
    }
    rb_str_cat_cstr(err_mess, ")");
    return rb_exc_new3(rb_eArgError, err_mess);
}

void
rb_error_arity(int argc, int min, int max)
{
    rb_exc_raise(rb_arity_error_new(argc, min, max));
}

/* lvar */

NOINLINE(static void vm_env_write_slowpath(const VALUE *ep, int index, VALUE v));

static void
vm_env_write_slowpath(const VALUE *ep, int index, VALUE v)
{
    /* remember env value forcely */
    rb_gc_writebarrier_remember(VM_ENV_ENVVAL(ep));
    VM_FORCE_WRITE(&ep[index], v);
    VM_ENV_FLAGS_UNSET(ep, VM_ENV_FLAG_WB_REQUIRED);
    RB_DEBUG_COUNTER_INC(lvar_set_slowpath);
}

// YJIT assumes this function never runs GC
static inline void
vm_env_write(const VALUE *ep, int index, VALUE v)
{
    VALUE flags = ep[VM_ENV_DATA_INDEX_FLAGS];
    if (LIKELY((flags & VM_ENV_FLAG_WB_REQUIRED) == 0)) {
        VM_STACK_ENV_WRITE(ep, index, v);
    }
    else {
        vm_env_write_slowpath(ep, index, v);
    }
}

void
rb_vm_env_write(const VALUE *ep, int index, VALUE v)
{
    vm_env_write(ep, index, v);
}

VALUE
rb_vm_bh_to_procval(const rb_execution_context_t *ec, VALUE block_handler)
{
    if (block_handler == VM_BLOCK_HANDLER_NONE) {
        return Qnil;
    }
    else {
        switch (vm_block_handler_type(block_handler)) {
          case block_handler_type_iseq:
          case block_handler_type_ifunc:
            return rb_vm_make_proc(ec, VM_BH_TO_CAPT_BLOCK(block_handler), rb_cProc);
          case block_handler_type_symbol:
            return rb_sym_to_proc(VM_BH_TO_SYMBOL(block_handler));
          case block_handler_type_proc:
            return VM_BH_TO_PROC(block_handler);
          default:
            VM_UNREACHABLE(rb_vm_bh_to_procval);
        }
    }
}

/* svar */

#if VM_CHECK_MODE > 0
static int
vm_svar_valid_p(VALUE svar)
{
    if (RB_TYPE_P((VALUE)svar, T_IMEMO)) {
        switch (imemo_type(svar)) {
          case imemo_svar:
          case imemo_cref:
          case imemo_ment:
            return TRUE;
          default:
            break;
        }
    }
    rb_bug("vm_svar_valid_p: unknown type: %s", rb_obj_info(svar));
    return FALSE;
}
#endif

static inline struct vm_svar *
lep_svar(const rb_execution_context_t *ec, const VALUE *lep)
{
    VALUE svar;

    if (lep && (ec == NULL || ec->root_lep != lep)) {
        svar = lep[VM_ENV_DATA_INDEX_ME_CREF];
    }
    else {
        svar = ec->root_svar;
    }

    VM_ASSERT(svar == Qfalse || vm_svar_valid_p(svar));

    return (struct vm_svar *)svar;
}

static inline void
lep_svar_write(const rb_execution_context_t *ec, const VALUE *lep, const struct vm_svar *svar)
{
    VM_ASSERT(vm_svar_valid_p((VALUE)svar));

    if (lep && (ec == NULL || ec->root_lep != lep)) {
        vm_env_write(lep, VM_ENV_DATA_INDEX_ME_CREF, (VALUE)svar);
    }
    else {
        RB_OBJ_WRITE(rb_ec_thread_ptr(ec)->self, &ec->root_svar, svar);
    }
}

static VALUE
lep_svar_get(const rb_execution_context_t *ec, const VALUE *lep, rb_num_t key)
{
    const struct vm_svar *svar = lep_svar(ec, lep);

    if ((VALUE)svar == Qfalse || imemo_type((VALUE)svar) != imemo_svar) return Qnil;

    switch (key) {
      case VM_SVAR_LASTLINE:
        return svar->lastline;
      case VM_SVAR_BACKREF:
        return svar->backref;
      default: {
        const VALUE ary = svar->others;

        if (NIL_P(ary)) {
            return Qnil;
        }
        else {
            return rb_ary_entry(ary, key - VM_SVAR_EXTRA_START);
        }
      }
    }
}

static struct vm_svar *
svar_new(VALUE obj)
{
    struct vm_svar *svar = IMEMO_NEW(struct vm_svar, imemo_svar, obj);
    *((VALUE *)&svar->lastline) = Qnil;
    *((VALUE *)&svar->backref) = Qnil;
    *((VALUE *)&svar->others) = Qnil;

    return svar;
}

static void
lep_svar_set(const rb_execution_context_t *ec, const VALUE *lep, rb_num_t key, VALUE val)
{
    struct vm_svar *svar = lep_svar(ec, lep);

    if ((VALUE)svar == Qfalse || imemo_type((VALUE)svar) != imemo_svar) {
        lep_svar_write(ec, lep, svar = svar_new((VALUE)svar));
    }

    switch (key) {
      case VM_SVAR_LASTLINE:
        RB_OBJ_WRITE(svar, &svar->lastline, val);
        return;
      case VM_SVAR_BACKREF:
        RB_OBJ_WRITE(svar, &svar->backref, val);
        return;
      default: {
        VALUE ary = svar->others;

        if (NIL_P(ary)) {
            RB_OBJ_WRITE(svar, &svar->others, ary = rb_ary_new());
        }
        rb_ary_store(ary, key - VM_SVAR_EXTRA_START, val);
      }
    }
}

static inline VALUE
vm_getspecial(const rb_execution_context_t *ec, const VALUE *lep, rb_num_t key, rb_num_t type)
{
    VALUE val;

    if (type == 0) {
        val = lep_svar_get(ec, lep, key);
    }
    else {
        VALUE backref = lep_svar_get(ec, lep, VM_SVAR_BACKREF);

        if (type & 0x01) {
            switch (type >> 1) {
              case '&':
                val = rb_reg_last_match(backref);
                break;
              case '`':
                val = rb_reg_match_pre(backref);
                break;
              case '\'':
                val = rb_reg_match_post(backref);
                break;
              case '+':
                val = rb_reg_match_last(backref);
                break;
              default:
                rb_bug("unexpected back-ref");
            }
        }
        else {
            val = rb_reg_nth_match((int)(type >> 1), backref);
        }
    }
    return val;
}

static inline VALUE
vm_backref_defined(const rb_execution_context_t *ec, const VALUE *lep, rb_num_t type)
{
    VALUE backref = lep_svar_get(ec, lep, VM_SVAR_BACKREF);
    int nth = 0;

    if (type & 0x01) {
        switch (type >> 1) {
          case '&':
          case '`':
          case '\'':
            break;
          case '+':
            return rb_reg_last_defined(backref);
          default:
            rb_bug("unexpected back-ref");
        }
    }
    else {
        nth = (int)(type >> 1);
    }
    return rb_reg_nth_defined(nth, backref);
}

PUREFUNC(static rb_callable_method_entry_t *check_method_entry(VALUE obj, int can_be_svar));
static rb_callable_method_entry_t *
check_method_entry(VALUE obj, int can_be_svar)
{
    if (obj == Qfalse) return NULL;

#if VM_CHECK_MODE > 0
    if (!RB_TYPE_P(obj, T_IMEMO)) rb_bug("check_method_entry: unknown type: %s", rb_obj_info(obj));
#endif

    switch (imemo_type(obj)) {
      case imemo_ment:
        return (rb_callable_method_entry_t *)obj;
      case imemo_cref:
        return NULL;
      case imemo_svar:
        if (can_be_svar) {
            return check_method_entry(((struct vm_svar *)obj)->cref_or_me, FALSE);
        }
      default:
#if VM_CHECK_MODE > 0
        rb_bug("check_method_entry: svar should not be there:");
#endif
        return NULL;
    }
}

const rb_callable_method_entry_t *
rb_vm_frame_method_entry(const rb_control_frame_t *cfp)
{
    const VALUE *ep = cfp->ep;
    rb_callable_method_entry_t *me;

    while (!VM_ENV_LOCAL_P(ep)) {
        if ((me = check_method_entry(ep[VM_ENV_DATA_INDEX_ME_CREF], FALSE)) != NULL) return me;
        ep = VM_ENV_PREV_EP(ep);
    }

    return check_method_entry(ep[VM_ENV_DATA_INDEX_ME_CREF], TRUE);
}

static const rb_iseq_t *
method_entry_iseqptr(const rb_callable_method_entry_t *me)
{
    switch (me->def->type) {
      case VM_METHOD_TYPE_ISEQ:
        return me->def->body.iseq.iseqptr;
      default:
        return NULL;
    }
}

static rb_cref_t *
method_entry_cref(const rb_callable_method_entry_t *me)
{
    switch (me->def->type) {
      case VM_METHOD_TYPE_ISEQ:
        return me->def->body.iseq.cref;
      default:
        return NULL;
    }
}

#if VM_CHECK_MODE == 0
PUREFUNC(static rb_cref_t *check_cref(VALUE, int));
#endif
static rb_cref_t *
check_cref(VALUE obj, int can_be_svar)
{
    if (obj == Qfalse) return NULL;

#if VM_CHECK_MODE > 0
    if (!RB_TYPE_P(obj, T_IMEMO)) rb_bug("check_cref: unknown type: %s", rb_obj_info(obj));
#endif

    switch (imemo_type(obj)) {
      case imemo_ment:
        return method_entry_cref((rb_callable_method_entry_t *)obj);
      case imemo_cref:
        return (rb_cref_t *)obj;
      case imemo_svar:
        if (can_be_svar) {
            return check_cref(((struct vm_svar *)obj)->cref_or_me, FALSE);
        }
      default:
#if VM_CHECK_MODE > 0
        rb_bug("check_method_entry: svar should not be there:");
#endif
        return NULL;
    }
}

static inline rb_cref_t *
vm_env_cref(const VALUE *ep)
{
    rb_cref_t *cref;

    while (!VM_ENV_LOCAL_P(ep)) {
        if ((cref = check_cref(ep[VM_ENV_DATA_INDEX_ME_CREF], FALSE)) != NULL) return cref;
        ep = VM_ENV_PREV_EP(ep);
    }

    return check_cref(ep[VM_ENV_DATA_INDEX_ME_CREF], TRUE);
}

static int
is_cref(const VALUE v, int can_be_svar)
{
    if (RB_TYPE_P(v, T_IMEMO)) {
        switch (imemo_type(v)) {
          case imemo_cref:
            return TRUE;
          case imemo_svar:
            if (can_be_svar) return is_cref(((struct vm_svar *)v)->cref_or_me, FALSE);
          default:
            break;
        }
    }
    return FALSE;
}

static int
vm_env_cref_by_cref(const VALUE *ep)
{
    while (!VM_ENV_LOCAL_P(ep)) {
        if (is_cref(ep[VM_ENV_DATA_INDEX_ME_CREF], FALSE)) return TRUE;
        ep = VM_ENV_PREV_EP(ep);
    }
    return is_cref(ep[VM_ENV_DATA_INDEX_ME_CREF], TRUE);
}

static rb_cref_t *
cref_replace_with_duplicated_cref_each_frame(const VALUE *vptr, int can_be_svar, VALUE parent)
{
    const VALUE v = *vptr;
    rb_cref_t *cref, *new_cref;

    if (RB_TYPE_P(v, T_IMEMO)) {
        switch (imemo_type(v)) {
          case imemo_cref:
            cref = (rb_cref_t *)v;
            new_cref = vm_cref_dup(cref);
            if (parent) {
                RB_OBJ_WRITE(parent, vptr, new_cref);
            }
            else {
                VM_FORCE_WRITE(vptr, (VALUE)new_cref);
            }
            return (rb_cref_t *)new_cref;
          case imemo_svar:
            if (can_be_svar) {
                return cref_replace_with_duplicated_cref_each_frame(&((struct vm_svar *)v)->cref_or_me, FALSE, v);
            }
            /* fall through */
          case imemo_ment:
            rb_bug("cref_replace_with_duplicated_cref_each_frame: unreachable");
          default:
            break;
        }
    }
    return NULL;
}

static rb_cref_t *
vm_cref_replace_with_duplicated_cref(const VALUE *ep)
{
    if (vm_env_cref_by_cref(ep)) {
        rb_cref_t *cref;
        VALUE envval;

        while (!VM_ENV_LOCAL_P(ep)) {
            envval = VM_ENV_ESCAPED_P(ep) ? VM_ENV_ENVVAL(ep) : Qfalse;
            if ((cref = cref_replace_with_duplicated_cref_each_frame(&ep[VM_ENV_DATA_INDEX_ME_CREF], FALSE, envval)) != NULL) {
                return cref;
            }
            ep = VM_ENV_PREV_EP(ep);
        }
        envval = VM_ENV_ESCAPED_P(ep) ? VM_ENV_ENVVAL(ep) : Qfalse;
        return cref_replace_with_duplicated_cref_each_frame(&ep[VM_ENV_DATA_INDEX_ME_CREF], TRUE, envval);
    }
    else {
        rb_bug("vm_cref_dup: unreachable");
    }
}

static rb_cref_t *
vm_get_cref(const VALUE *ep)
{
    rb_cref_t *cref = vm_env_cref(ep);

    if (cref != NULL) {
        return cref;
    }
    else {
        rb_bug("vm_get_cref: unreachable");
    }
}

rb_cref_t *
rb_vm_get_cref(const VALUE *ep)
{
    return vm_get_cref(ep);
}

static rb_cref_t *
vm_ec_cref(const rb_execution_context_t *ec)
{
    const rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(ec, ec->cfp);

    if (cfp == NULL) {
        return NULL;
    }
    return vm_get_cref(cfp->ep);
}

static const rb_cref_t *
vm_get_const_key_cref(const VALUE *ep)
{
    const rb_cref_t *cref = vm_get_cref(ep);
    const rb_cref_t *key_cref = cref;

    while (cref) {
        if (RCLASS_SINGLETON_P(CREF_CLASS(cref)) ||
                RCLASS_EXT(CREF_CLASS(cref))->cloned) {
            return key_cref;
        }
        cref = CREF_NEXT(cref);
    }

    /* does not include singleton class */
    return NULL;
}

void
rb_vm_rewrite_cref(rb_cref_t *cref, VALUE old_klass, VALUE new_klass, rb_cref_t **new_cref_ptr)
{
    rb_cref_t *new_cref;

    while (cref) {
        if (CREF_CLASS(cref) == old_klass) {
            new_cref = vm_cref_new_use_prev(new_klass, METHOD_VISI_UNDEF, FALSE, cref, FALSE);
            *new_cref_ptr = new_cref;
            return;
        }
        new_cref = vm_cref_new_use_prev(CREF_CLASS(cref), METHOD_VISI_UNDEF, FALSE, cref, FALSE);
        cref = CREF_NEXT(cref);
        *new_cref_ptr = new_cref;
        new_cref_ptr = &new_cref->next;
    }
    *new_cref_ptr = NULL;
}

static rb_cref_t *
vm_cref_push(const rb_execution_context_t *ec, VALUE klass, const VALUE *ep, int pushed_by_eval, int singleton)
{
    rb_cref_t *prev_cref = NULL;

    if (ep) {
        prev_cref = vm_env_cref(ep);
    }
    else {
        rb_control_frame_t *cfp = vm_get_ruby_level_caller_cfp(ec, ec->cfp);

        if (cfp) {
            prev_cref = vm_env_cref(cfp->ep);
        }
    }

    return vm_cref_new(klass, METHOD_VISI_PUBLIC, FALSE, prev_cref, pushed_by_eval, singleton);
}

static inline VALUE
vm_get_cbase(const VALUE *ep)
{
    const rb_cref_t *cref = vm_get_cref(ep);

    return CREF_CLASS_FOR_DEFINITION(cref);
}

static inline VALUE
vm_get_const_base(const VALUE *ep)
{
    const rb_cref_t *cref = vm_get_cref(ep);

    while (cref) {
        if (!CREF_PUSHED_BY_EVAL(cref)) {
            return CREF_CLASS_FOR_DEFINITION(cref);
        }
        cref = CREF_NEXT(cref);
    }

    return Qundef;
}

static inline void
vm_check_if_namespace(VALUE klass)
{
    if (!RB_TYPE_P(klass, T_CLASS) && !RB_TYPE_P(klass, T_MODULE)) {
        rb_raise(rb_eTypeError, "%+"PRIsVALUE" is not a class/module", klass);
    }
}

static inline void
vm_ensure_not_refinement_module(VALUE self)
{
    if (RB_TYPE_P(self, T_MODULE) && FL_TEST(self, RMODULE_IS_REFINEMENT)) {
        rb_warn("not defined at the refinement, but at the outer class/module");
    }
}

static inline VALUE
vm_get_iclass(const rb_control_frame_t *cfp, VALUE klass)
{
    return klass;
}

static inline VALUE
vm_get_ev_const(rb_execution_context_t *ec, VALUE orig_klass, ID id, bool allow_nil, int is_defined)
{
    void rb_const_warn_if_deprecated(const rb_const_entry_t *ce, VALUE klass, ID id);
    VALUE val;

    if (NIL_P(orig_klass) && allow_nil) {
        /* in current lexical scope */
        const rb_cref_t *root_cref = vm_get_cref(ec->cfp->ep);
        const rb_cref_t *cref;
        VALUE klass = Qnil;

        while (root_cref && CREF_PUSHED_BY_EVAL(root_cref)) {
            root_cref = CREF_NEXT(root_cref);
        }
        cref = root_cref;
        while (cref && CREF_NEXT(cref)) {
            if (CREF_PUSHED_BY_EVAL(cref)) {
                klass = Qnil;
            }
            else {
                klass = CREF_CLASS(cref);
            }
            cref = CREF_NEXT(cref);

            if (!NIL_P(klass)) {
                VALUE av, am = 0;
                rb_const_entry_t *ce;
              search_continue:
                if ((ce = rb_const_lookup(klass, id))) {
                    rb_const_warn_if_deprecated(ce, klass, id);
                    val = ce->value;
                    if (UNDEF_P(val)) {
                        if (am == klass) break;
                        am = klass;
                        if (is_defined) return 1;
                        if (rb_autoloading_value(klass, id, &av, NULL)) return av;
                        rb_autoload_load(klass, id);
                        goto search_continue;
                    }
                    else {
                        if (is_defined) {
                            return 1;
                        }
                        else {
                            if (UNLIKELY(!rb_ractor_main_p())) {
                                if (!rb_ractor_shareable_p(val)) {
                                    rb_raise(rb_eRactorIsolationError,
                                             "can not access non-shareable objects in constant %"PRIsVALUE"::%s by non-main ractor.", rb_class_path(klass), rb_id2name(id));
                                }
                            }
                            return val;
                        }
                    }
                }
            }
        }

        /* search self */
        if (root_cref && !NIL_P(CREF_CLASS(root_cref))) {
            klass = vm_get_iclass(ec->cfp, CREF_CLASS(root_cref));
        }
        else {
            klass = CLASS_OF(ec->cfp->self);
        }

        if (is_defined) {
            return rb_const_defined(klass, id);
        }
        else {
            return rb_const_get(klass, id);
        }
    }
    else {
        vm_check_if_namespace(orig_klass);
        if (is_defined) {
            return rb_public_const_defined_from(orig_klass, id);
        }
        else {
            return rb_public_const_get_from(orig_klass, id);
        }
    }
}

VALUE
rb_vm_get_ev_const(rb_execution_context_t *ec, VALUE orig_klass, ID id, VALUE allow_nil)
{
    return vm_get_ev_const(ec, orig_klass, id, allow_nil == Qtrue, 0);
}

static inline VALUE
vm_get_ev_const_chain(rb_execution_context_t *ec, const ID *segments)
{
    VALUE val = Qnil;
    int idx = 0;
    int allow_nil = TRUE;
    if (segments[0] == idNULL) {
        val = rb_cObject;
        idx++;
        allow_nil = FALSE;
    }
    while (segments[idx]) {
        ID id = segments[idx++];
        val = vm_get_ev_const(ec, val, id, allow_nil, 0);
        allow_nil = FALSE;
    }
    return val;
}


static inline VALUE
vm_get_cvar_base(const rb_cref_t *cref, const rb_control_frame_t *cfp, int top_level_raise)
{
    VALUE klass;

    if (!cref) {
        rb_bug("vm_get_cvar_base: no cref");
    }

    while (CREF_NEXT(cref) &&
           (NIL_P(CREF_CLASS(cref)) || RCLASS_SINGLETON_P(CREF_CLASS(cref)) ||
            CREF_PUSHED_BY_EVAL(cref) || CREF_SINGLETON(cref))) {
        cref = CREF_NEXT(cref);
    }
    if (top_level_raise && !CREF_NEXT(cref)) {
        rb_raise(rb_eRuntimeError, "class variable access from toplevel");
    }

    klass = vm_get_iclass(cfp, CREF_CLASS(cref));

    if (NIL_P(klass)) {
        rb_raise(rb_eTypeError, "no class variables available");
    }
    return klass;
}

ALWAYS_INLINE(static void fill_ivar_cache(const rb_iseq_t *iseq, IVC ic, const struct rb_callcache *cc, int is_attr, attr_index_t index, shape_id_t shape_id));
static inline void
fill_ivar_cache(const rb_iseq_t *iseq, IVC ic, const struct rb_callcache *cc, int is_attr, attr_index_t index, shape_id_t shape_id)
{
    if (is_attr) {
        vm_cc_attr_index_set(cc, index, shape_id);
    }
    else {
        vm_ic_attr_index_set(iseq, ic, index, shape_id);
    }
}

#define ractor_incidental_shareable_p(cond, val) \
    (!(cond) || rb_ractor_shareable_p(val))
#define ractor_object_incidental_shareable_p(obj, val) \
    ractor_incidental_shareable_p(rb_ractor_shareable_p(obj), val)

#define ATTR_INDEX_NOT_SET (attr_index_t)-1

ALWAYS_INLINE(static VALUE vm_getivar(VALUE, ID, const rb_iseq_t *, IVC, const struct rb_callcache *, int, VALUE));
static inline VALUE
vm_getivar(VALUE obj, ID id, const rb_iseq_t *iseq, IVC ic, const struct rb_callcache *cc, int is_attr, VALUE default_value)
{
#if OPT_IC_FOR_IVAR
    VALUE val = Qundef;
    shape_id_t shape_id;
    VALUE * ivar_list;

    if (SPECIAL_CONST_P(obj)) {
        return default_value;
    }

#if SHAPE_IN_BASIC_FLAGS
    shape_id = RBASIC_SHAPE_ID(obj);
#endif

    switch (BUILTIN_TYPE(obj)) {
      case T_OBJECT:
        ivar_list = ROBJECT_IVPTR(obj);
        VM_ASSERT(rb_ractor_shareable_p(obj) ? rb_ractor_shareable_p(val) : true);

#if !SHAPE_IN_BASIC_FLAGS
        shape_id = ROBJECT_SHAPE_ID(obj);
#endif
        break;
      case T_CLASS:
      case T_MODULE:
        {
            if (UNLIKELY(!rb_ractor_main_p())) {
                // For two reasons we can only use the fast path on the main
                // ractor.
                // First, only the main ractor is allowed to set ivars on classes
                // and modules. So we can skip locking.
                // Second, other ractors need to check the shareability of the
                // values returned from the class ivars.
                goto general_path;
            }

            ivar_list = RCLASS_IVPTR(obj);

#if !SHAPE_IN_BASIC_FLAGS
            shape_id = RCLASS_SHAPE_ID(obj);
#endif

            break;
        }
      default:
        if (FL_TEST_RAW(obj, FL_EXIVAR)) {
            struct gen_ivtbl *ivtbl;
            rb_gen_ivtbl_get(obj, id, &ivtbl);
#if !SHAPE_IN_BASIC_FLAGS
            shape_id = ivtbl->shape_id;
#endif
            ivar_list = ivtbl->as.shape.ivptr;
        }
        else {
            return default_value;
        }
    }

    shape_id_t cached_id;
    attr_index_t index;

    if (is_attr) {
        vm_cc_atomic_shape_and_index(cc, &cached_id, &index);
    }
    else {
        vm_ic_atomic_shape_and_index(ic, &cached_id, &index);
    }

    if (LIKELY(cached_id == shape_id)) {
        RUBY_ASSERT(cached_id != OBJ_TOO_COMPLEX_SHAPE_ID);

        if (index == ATTR_INDEX_NOT_SET) {
            return default_value;
        }

        val = ivar_list[index];
#if USE_DEBUG_COUNTER
        RB_DEBUG_COUNTER_INC(ivar_get_ic_hit);

        if (RB_TYPE_P(obj, T_OBJECT)) {
            RB_DEBUG_COUNTER_INC(ivar_get_obj_hit);
        }
#endif
        RUBY_ASSERT(!UNDEF_P(val));
    }
    else { // cache miss case
#if USE_DEBUG_COUNTER
        if (is_attr) {
            if (cached_id != INVALID_SHAPE_ID) {
                RB_DEBUG_COUNTER_INC(ivar_get_cc_miss_set);
            }
            else {
                RB_DEBUG_COUNTER_INC(ivar_get_cc_miss_unset);
            }
        }
        else {
            if (cached_id != INVALID_SHAPE_ID) {
                RB_DEBUG_COUNTER_INC(ivar_get_ic_miss_set);
            }
            else {
                RB_DEBUG_COUNTER_INC(ivar_get_ic_miss_unset);
            }
        }
        RB_DEBUG_COUNTER_INC(ivar_get_ic_miss);

        if (RB_TYPE_P(obj, T_OBJECT)) {
            RB_DEBUG_COUNTER_INC(ivar_get_obj_miss);
        }
#endif

        if (shape_id == OBJ_TOO_COMPLEX_SHAPE_ID) {
            st_table *table = NULL;
            switch (BUILTIN_TYPE(obj)) {
              case T_CLASS:
              case T_MODULE:
                table = (st_table *)RCLASS_IVPTR(obj);
                break;

              case T_OBJECT:
                table = ROBJECT_IV_HASH(obj);
                break;

              default: {
                struct gen_ivtbl *ivtbl;
                if (rb_gen_ivtbl_get(obj, 0, &ivtbl)) {
                    table = ivtbl->as.complex.table;
                }
                break;
              }
            }

            if (!table || !st_lookup(table, id, &val)) {
                val = default_value;
            }
        }
        else {
            shape_id_t previous_cached_id = cached_id;
            if (rb_shape_get_iv_index_with_hint(shape_id, id, &index, &cached_id)) {
                // This fills in the cache with the shared cache object.
                // "ent" is the shared cache object
                if (cached_id != previous_cached_id) {
                    fill_ivar_cache(iseq, ic, cc, is_attr, index, cached_id);
                }

                if (index == ATTR_INDEX_NOT_SET) {
                    val = default_value;
                }
                else {
                    // We fetched the ivar list above
                    val = ivar_list[index];
                    RUBY_ASSERT(!UNDEF_P(val));
                }
            }
            else {
                if (is_attr) {
                    vm_cc_attr_index_initialize(cc, shape_id);
                }
                else {
                    vm_ic_attr_index_initialize(ic, shape_id);
                }

                val = default_value;
            }
        }

    }

    if (!UNDEF_P(default_value)) {
        RUBY_ASSERT(!UNDEF_P(val));
    }

    return val;

general_path:
#endif /* OPT_IC_FOR_IVAR */
    RB_DEBUG_COUNTER_INC(ivar_get_ic_miss);

    if (is_attr) {
        return rb_attr_get(obj, id);
    }
    else {
        return rb_ivar_get(obj, id);
    }
}

static void
populate_cache(attr_index_t index, shape_id_t next_shape_id, ID id, const rb_iseq_t *iseq, IVC ic, const struct rb_callcache *cc, bool is_attr)
{
    RUBY_ASSERT(next_shape_id != OBJ_TOO_COMPLEX_SHAPE_ID);

    // Cache population code
    if (is_attr) {
        vm_cc_attr_index_set(cc, index, next_shape_id);
    }
    else {
        vm_ic_attr_index_set(iseq, ic, index, next_shape_id);
    }
}

ALWAYS_INLINE(static VALUE vm_setivar_slowpath(VALUE obj, ID id, VALUE val, const rb_iseq_t *iseq, IVC ic, const struct rb_callcache *cc, int is_attr));
NOINLINE(static VALUE vm_setivar_slowpath_ivar(VALUE obj, ID id, VALUE val, const rb_iseq_t *iseq, IVC ic));
NOINLINE(static VALUE vm_setivar_slowpath_attr(VALUE obj, ID id, VALUE val, const struct rb_callcache *cc));

static VALUE
vm_setivar_slowpath(VALUE obj, ID id, VALUE val, const rb_iseq_t *iseq, IVC ic, const struct rb_callcache *cc, int is_attr)
{
#if OPT_IC_FOR_IVAR
    RB_DEBUG_COUNTER_INC(ivar_set_ic_miss);

    if (BUILTIN_TYPE(obj) == T_OBJECT) {
        rb_check_frozen(obj);

        attr_index_t index = rb_obj_ivar_set(obj, id, val);

        shape_id_t next_shape_id = ROBJECT_SHAPE_ID(obj);

        if (next_shape_id != OBJ_TOO_COMPLEX_SHAPE_ID) {
            populate_cache(index, next_shape_id, id, iseq, ic, cc, is_attr);
        }

        RB_DEBUG_COUNTER_INC(ivar_set_obj_miss);
        return val;
    }
#endif
    return rb_ivar_set(obj, id, val);
}

static VALUE
vm_setivar_slowpath_ivar(VALUE obj, ID id, VALUE val, const rb_iseq_t *iseq, IVC ic)
{
    return vm_setivar_slowpath(obj, id, val, iseq, ic, NULL, false);
}

static VALUE
vm_setivar_slowpath_attr(VALUE obj, ID id, VALUE val, const struct rb_callcache *cc)
{
    return vm_setivar_slowpath(obj, id, val, NULL, NULL, cc, true);
}

NOINLINE(static VALUE vm_setivar_default(VALUE obj, ID id, VALUE val, shape_id_t dest_shape_id, attr_index_t index));
static VALUE
vm_setivar_default(VALUE obj, ID id, VALUE val, shape_id_t dest_shape_id, attr_index_t index)
{
#if SHAPE_IN_BASIC_FLAGS
    shape_id_t shape_id = RBASIC_SHAPE_ID(obj);
#else
    shape_id_t shape_id = rb_generic_shape_id(obj);
#endif

    struct gen_ivtbl *ivtbl = 0;

    // Cache hit case
    if (shape_id == dest_shape_id) {
        RUBY_ASSERT(dest_shape_id != INVALID_SHAPE_ID && shape_id != INVALID_SHAPE_ID);
    }
    else if (dest_shape_id != INVALID_SHAPE_ID) {
        rb_shape_t *shape = rb_shape_get_shape_by_id(shape_id);
        rb_shape_t *dest_shape = rb_shape_get_shape_by_id(dest_shape_id);

        if (shape_id == dest_shape->parent_id && dest_shape->edge_name == id && shape->capacity == dest_shape->capacity) {
            RUBY_ASSERT(index < dest_shape->capacity);
        }
        else {
            return Qundef;
        }
    }
    else {
        return Qundef;
    }

    rb_gen_ivtbl_get(obj, 0, &ivtbl);

    if (shape_id != dest_shape_id) {
#if SHAPE_IN_BASIC_FLAGS
        RBASIC_SET_SHAPE_ID(obj, dest_shape_id);
#else
        ivtbl->shape_id = dest_shape_id;
#endif
    }

    RB_OBJ_WRITE(obj, &ivtbl->as.shape.ivptr[index], val);

    RB_DEBUG_COUNTER_INC(ivar_set_ic_hit);

    return val;
}

static inline VALUE
vm_setivar(VALUE obj, ID id, VALUE val, shape_id_t dest_shape_id, attr_index_t index)
{
#if OPT_IC_FOR_IVAR
    switch (BUILTIN_TYPE(obj)) {
      case T_OBJECT:
        {
            VM_ASSERT(!rb_ractor_shareable_p(obj) || rb_obj_frozen_p(obj));

            shape_id_t shape_id = ROBJECT_SHAPE_ID(obj);
            RUBY_ASSERT(dest_shape_id != OBJ_TOO_COMPLEX_SHAPE_ID);

            if (LIKELY(shape_id == dest_shape_id)) {
                RUBY_ASSERT(dest_shape_id != INVALID_SHAPE_ID && shape_id != INVALID_SHAPE_ID);
                VM_ASSERT(!rb_ractor_shareable_p(obj));
            }
            else if (dest_shape_id != INVALID_SHAPE_ID) {
                rb_shape_t *shape = rb_shape_get_shape_by_id(shape_id);
                rb_shape_t *dest_shape = rb_shape_get_shape_by_id(dest_shape_id);
                shape_id_t source_shape_id = dest_shape->parent_id;

                if (shape_id == source_shape_id && dest_shape->edge_name == id && shape->capacity == dest_shape->capacity) {
                    RUBY_ASSERT(dest_shape_id != INVALID_SHAPE_ID && shape_id != INVALID_SHAPE_ID);

                    ROBJECT_SET_SHAPE_ID(obj, dest_shape_id);

                    RUBY_ASSERT(rb_shape_get_next_iv_shape(rb_shape_get_shape_by_id(source_shape_id), id) == dest_shape);
                    RUBY_ASSERT(index < dest_shape->capacity);
                }
                else {
                    break;
                }
            }
            else {
                break;
            }

            VALUE *ptr = ROBJECT_IVPTR(obj);

            RUBY_ASSERT(!rb_shape_obj_too_complex(obj));
            RB_OBJ_WRITE(obj, &ptr[index], val);

            RB_DEBUG_COUNTER_INC(ivar_set_ic_hit);
            RB_DEBUG_COUNTER_INC(ivar_set_obj_hit);
            return val;
        }
        break;
      case T_CLASS:
      case T_MODULE:
        RB_DEBUG_COUNTER_INC(ivar_set_ic_miss_noobject);
      default:
        break;
    }

    return Qundef;
#endif /* OPT_IC_FOR_IVAR */
}

static VALUE
update_classvariable_cache(const rb_iseq_t *iseq, VALUE klass, ID id, const rb_cref_t * cref, ICVARC ic)
{
    VALUE defined_class = 0;
    VALUE cvar_value = rb_cvar_find(klass, id, &defined_class);

    if (RB_TYPE_P(defined_class, T_ICLASS)) {
        defined_class = RBASIC(defined_class)->klass;
    }

    struct rb_id_table *rb_cvc_tbl = RCLASS_CVC_TBL(defined_class);
    if (!rb_cvc_tbl) {
        rb_bug("the cvc table should be set");
    }

    VALUE ent_data;
    if (!rb_id_table_lookup(rb_cvc_tbl, id, &ent_data)) {
        rb_bug("should have cvar cache entry");
    }

    struct rb_cvar_class_tbl_entry *ent = (void *)ent_data;

    ent->global_cvar_state = GET_GLOBAL_CVAR_STATE();
    ent->cref = cref;
    ic->entry = ent;

    RUBY_ASSERT(BUILTIN_TYPE((VALUE)cref) == T_IMEMO && IMEMO_TYPE_P(cref, imemo_cref));
    RB_OBJ_WRITTEN(iseq, Qundef, ent->cref);
    RB_OBJ_WRITTEN(iseq, Qundef, ent->class_value);
    RB_OBJ_WRITTEN(ent->class_value, Qundef, ent->cref);

    return cvar_value;
}

static inline VALUE
vm_getclassvariable(const rb_iseq_t *iseq, const rb_control_frame_t *reg_cfp, ID id, ICVARC ic)
{
    const rb_cref_t *cref;
    cref = vm_get_cref(GET_EP());

    if (ic->entry && ic->entry->global_cvar_state == GET_GLOBAL_CVAR_STATE() && ic->entry->cref == cref && LIKELY(rb_ractor_main_p())) {
        RB_DEBUG_COUNTER_INC(cvar_read_inline_hit);

        VALUE v = rb_ivar_lookup(ic->entry->class_value, id, Qundef);
        RUBY_ASSERT(!UNDEF_P(v));

        return v;
    }

    VALUE klass = vm_get_cvar_base(cref, reg_cfp, 1);

    return update_classvariable_cache(iseq, klass, id, cref, ic);
}

VALUE
rb_vm_getclassvariable(const rb_iseq_t *iseq, const rb_control_frame_t *cfp, ID id, ICVARC ic)
{
    return vm_getclassvariable(iseq, cfp, id, ic);
}

static inline void
vm_setclassvariable(const rb_iseq_t *iseq, const rb_control_frame_t *reg_cfp, ID id, VALUE val, ICVARC ic)
{
    const rb_cref_t *cref;
    cref = vm_get_cref(GET_EP());

    if (ic->entry && ic->entry->global_cvar_state == GET_GLOBAL_CVAR_STATE() && ic->entry->cref == cref && LIKELY(rb_ractor_main_p())) {
        RB_DEBUG_COUNTER_INC(cvar_write_inline_hit);

        rb_class_ivar_set(ic->entry->class_value, id, val);
        return;
    }

    VALUE klass = vm_get_cvar_base(cref, reg_cfp, 1);

    rb_cvar_set(klass, id, val);

    update_classvariable_cache(iseq, klass, id, cref, ic);
}

void
rb_vm_setclassvariable(const rb_iseq_t *iseq, const rb_control_frame_t *cfp, ID id, VALUE val, ICVARC ic)
{
    vm_setclassvariable(iseq, cfp, id, val, ic);
}

static inline VALUE
vm_getinstancevariable(const rb_iseq_t *iseq, VALUE obj, ID id, IVC ic)
{
    return vm_getivar(obj, id, iseq, ic, NULL, FALSE, Qnil);
}

static inline void
vm_setinstancevariable(const rb_iseq_t *iseq, VALUE obj, ID id, VALUE val, IVC ic)
{
    if (RB_SPECIAL_CONST_P(obj)) {
        rb_error_frozen_object(obj);
        return;
    }

    shape_id_t dest_shape_id;
    attr_index_t index;
    vm_ic_atomic_shape_and_index(ic, &dest_shape_id, &index);

    if (UNLIKELY(UNDEF_P(vm_setivar(obj, id, val, dest_shape_id, index)))) {
        switch (BUILTIN_TYPE(obj)) {
          case T_OBJECT:
          case T_CLASS:
          case T_MODULE:
            break;
          default:
            if (!UNDEF_P(vm_setivar_default(obj, id, val, dest_shape_id, index))) {
                return;
            }
        }
        vm_setivar_slowpath_ivar(obj, id, val, iseq, ic);
    }
}

void
rb_vm_setinstancevariable(const rb_iseq_t *iseq, VALUE obj, ID id, VALUE val, IVC ic)
{
    vm_setinstancevariable(iseq, obj, id, val, ic);
}

static VALUE
vm_throw_continue(const rb_execution_context_t *ec, VALUE err)
{
    /* continue throw */

    if (FIXNUM_P(err)) {
        ec->tag->state = RUBY_TAG_FATAL;
    }
    else if (SYMBOL_P(err)) {
        ec->tag->state = TAG_THROW;
    }
    else if (THROW_DATA_P(err)) {
        ec->tag->state = THROW_DATA_STATE((struct vm_throw_data *)err);
    }
    else {
        ec->tag->state = TAG_RAISE;
    }
    return err;
}

static VALUE
vm_throw_start(const rb_execution_context_t *ec, rb_control_frame_t *const reg_cfp, enum ruby_tag_type state,
               const int flag, const VALUE throwobj)
{
    const rb_control_frame_t *escape_cfp = NULL;
    const rb_control_frame_t * const eocfp = RUBY_VM_END_CONTROL_FRAME(ec); /* end of control frame pointer */

    if (flag != 0) {
        /* do nothing */
    }
    else if (state == TAG_BREAK) {
        int is_orphan = 1;
        const VALUE *ep = GET_EP();
        const rb_iseq_t *base_iseq = GET_ISEQ();
        escape_cfp = reg_cfp;

        while (ISEQ_BODY(base_iseq)->type != ISEQ_TYPE_BLOCK) {
            if (ISEQ_BODY(escape_cfp->iseq)->type == ISEQ_TYPE_CLASS) {
                escape_cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(escape_cfp);
                ep = escape_cfp->ep;
                base_iseq = escape_cfp->iseq;
            }
            else {
                ep = VM_ENV_PREV_EP(ep);
                base_iseq = ISEQ_BODY(base_iseq)->parent_iseq;
                escape_cfp = rb_vm_search_cf_from_ep(ec, escape_cfp, ep);
                VM_ASSERT(escape_cfp->iseq == base_iseq);
            }
        }

        if (VM_FRAME_LAMBDA_P(escape_cfp)) {
            /* lambda{... break ...} */
            is_orphan = 0;
            state = TAG_RETURN;
        }
        else {
            ep = VM_ENV_PREV_EP(ep);

            while (escape_cfp < eocfp) {
                if (escape_cfp->ep == ep) {
                    const rb_iseq_t *const iseq = escape_cfp->iseq;
                    const VALUE epc = escape_cfp->pc - ISEQ_BODY(iseq)->iseq_encoded;
                    const struct iseq_catch_table *const ct = ISEQ_BODY(iseq)->catch_table;
                    unsigned int i;

                    if (!ct) break;
                    for (i=0; i < ct->size; i++) {
                        const struct iseq_catch_table_entry *const entry =
                            UNALIGNED_MEMBER_PTR(ct, entries[i]);

                        if (entry->type == CATCH_TYPE_BREAK &&
                            entry->iseq == base_iseq &&
                            entry->start < epc && entry->end >= epc) {
                            if (entry->cont == epc) { /* found! */
                                is_orphan = 0;
                            }
                            break;
                        }
                    }
                    break;
                }

                escape_cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(escape_cfp);
            }
        }

        if (is_orphan) {
            rb_vm_localjump_error("break from proc-closure", throwobj, TAG_BREAK);
        }
    }
    else if (state == TAG_RETRY) {
        const VALUE *ep = VM_ENV_PREV_EP(GET_EP());

        escape_cfp = rb_vm_search_cf_from_ep(ec, reg_cfp, ep);
    }
    else if (state == TAG_RETURN) {
        const VALUE *current_ep = GET_EP();
        const VALUE *target_ep = NULL, *target_lep, *ep = current_ep;
        int in_class_frame = 0;
        int toplevel = 1;
        escape_cfp = reg_cfp;

        // find target_lep, target_ep
        while (!VM_ENV_LOCAL_P(ep)) {
            if (VM_ENV_FLAGS(ep, VM_FRAME_FLAG_LAMBDA) && target_ep == NULL) {
                target_ep = ep;
            }
            ep = VM_ENV_PREV_EP(ep);
        }
        target_lep = ep;

        while (escape_cfp < eocfp) {
            const VALUE *lep = VM_CF_LEP(escape_cfp);

            if (!target_lep) {
                target_lep = lep;
            }

            if (lep == target_lep &&
                VM_FRAME_RUBYFRAME_P(escape_cfp) &&
                ISEQ_BODY(escape_cfp->iseq)->type == ISEQ_TYPE_CLASS) {
                in_class_frame = 1;
                target_lep = 0;
            }

            if (lep == target_lep) {
                if (VM_FRAME_LAMBDA_P(escape_cfp)) {
                    toplevel = 0;
                    if (in_class_frame) {
                        /* lambda {class A; ... return ...; end} */
                        goto valid_return;
                    }
                    else {
                        const VALUE *tep = current_ep;

                        while (target_lep != tep) {
                            if (escape_cfp->ep == tep) {
                                /* in lambda */
                                if (tep == target_ep) {
                                    goto valid_return;
                                }
                                else {
                                    goto unexpected_return;
                                }
                            }
                            tep = VM_ENV_PREV_EP(tep);
                        }
                    }
                }
                else if (VM_FRAME_RUBYFRAME_P(escape_cfp)) {
                    switch (ISEQ_BODY(escape_cfp->iseq)->type) {
                      case ISEQ_TYPE_TOP:
                      case ISEQ_TYPE_MAIN:
                        if (toplevel) {
                            if (in_class_frame) goto unexpected_return;
                            if (target_ep == NULL) {
                                goto valid_return;
                            }
                            else {
                                goto unexpected_return;
                            }
                        }
                        break;
                      case ISEQ_TYPE_EVAL: {
                        const rb_iseq_t *is = escape_cfp->iseq;
                        enum rb_iseq_type t = ISEQ_BODY(is)->type;
                        while (t == ISEQ_TYPE_RESCUE || t == ISEQ_TYPE_ENSURE || t == ISEQ_TYPE_EVAL) {
                            if (!(is = ISEQ_BODY(is)->parent_iseq)) break;
                            t = ISEQ_BODY(is)->type;
                        }
                        toplevel = t == ISEQ_TYPE_TOP || t == ISEQ_TYPE_MAIN;
                        break;
                      }
                      case ISEQ_TYPE_CLASS:
                        toplevel = 0;
                        break;
                      default:
                        break;
                    }
                }
            }

            if (escape_cfp->ep == target_lep && ISEQ_BODY(escape_cfp->iseq)->type == ISEQ_TYPE_METHOD) {
                if (target_ep == NULL) {
                    goto valid_return;
                }
                else {
                    goto unexpected_return;
                }
            }

            escape_cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(escape_cfp);
        }
      unexpected_return:;
        rb_vm_localjump_error("unexpected return", throwobj, TAG_RETURN);

      valid_return:;
        /* do nothing */
    }
    else {
        rb_bug("isns(throw): unsupported throw type");
    }

    ec->tag->state = state;
    return (VALUE)THROW_DATA_NEW(throwobj, escape_cfp, state);
}

static VALUE
vm_throw(const rb_execution_context_t *ec, rb_control_frame_t *reg_cfp,
         rb_num_t throw_state, VALUE throwobj)
{
    const int state = (int)(throw_state & VM_THROW_STATE_MASK);
    const int flag = (int)(throw_state & VM_THROW_NO_ESCAPE_FLAG);

    if (state != 0) {
        return vm_throw_start(ec, reg_cfp, state, flag, throwobj);
    }
    else {
        return vm_throw_continue(ec, throwobj);
    }
}

VALUE
rb_vm_throw(const rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, rb_num_t throw_state, VALUE throwobj)
{
    return vm_throw(ec, reg_cfp, throw_state, throwobj);
}

static inline void
vm_expandarray(struct rb_control_frame_struct *cfp, VALUE ary, rb_num_t num, int flag)
{
    int is_splat = flag & 0x01;
    const VALUE *ptr;
    rb_num_t len;
    const VALUE obj = ary;

    if (!RB_TYPE_P(ary, T_ARRAY) && NIL_P(ary = rb_check_array_type(ary))) {
        ary = obj;
        ptr = &ary;
        len = 1;
    }
    else {
        ptr = RARRAY_CONST_PTR(ary);
        len = (rb_num_t)RARRAY_LEN(ary);
    }

    if (num + is_splat == 0) {
        /* no space left on stack */
    }
    else if (flag & 0x02) {
        /* post: ..., nil ,ary[-1], ..., ary[0..-num] # top */
        rb_num_t i = 0, j;

        if (len < num) {
            for (i = 0; i < num - len; i++) {
                *cfp->sp++ = Qnil;
            }
        }

        for (j = 0; i < num; i++, j++) {
            VALUE v = ptr[len - j - 1];
            *cfp->sp++ = v;
        }

        if (is_splat) {
            *cfp->sp++ = rb_ary_new4(len - j, ptr);
        }
    }
    else {
        /* normal: ary[num..-1], ary[num-2], ary[num-3], ..., ary[0] # top */
        if (is_splat) {
            if (num > len) {
                *cfp->sp++ = rb_ary_new();
            }
            else {
                *cfp->sp++ = rb_ary_new4(len - num, ptr + num);
            }
        }

        if (num > len) {
            rb_num_t i = 0;
            for (; i < num - len; i++) {
                *cfp->sp++ = Qnil;
            }

            for (rb_num_t j = 0; i < num; i++, j++) {
                *cfp->sp++ = ptr[len - j - 1];
            }
        }
        else {
            for (rb_num_t j = 0; j < num; j++) {
                *cfp->sp++ = ptr[num - j - 1];
            }
        }
    }

    RB_GC_GUARD(ary);
}

static VALUE vm_call_general(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling);

static VALUE vm_mtbl_dump(VALUE klass, ID target_mid);

static struct rb_class_cc_entries *
vm_ccs_create(VALUE klass, struct rb_id_table *cc_tbl, ID mid, const rb_callable_method_entry_t *cme)
{
    struct rb_class_cc_entries *ccs = ALLOC(struct rb_class_cc_entries);
#if VM_CHECK_MODE > 0
    ccs->debug_sig = ~(VALUE)ccs;
#endif
    ccs->capa = 0;
    ccs->len = 0;
    ccs->cme = cme;
    METHOD_ENTRY_CACHED_SET((rb_callable_method_entry_t *)cme);
    ccs->entries = NULL;

    rb_id_table_insert(cc_tbl, mid, (VALUE)ccs);
    RB_OBJ_WRITTEN(klass, Qundef, cme);
    return ccs;
}

static void
vm_ccs_push(VALUE klass, struct rb_class_cc_entries *ccs, const struct rb_callinfo *ci, const struct rb_callcache *cc)
{
    if (! vm_cc_markable(cc)) {
        return;
    }

    if (UNLIKELY(ccs->len == ccs->capa)) {
        if (ccs->capa == 0) {
            ccs->capa = 1;
            ccs->entries = ALLOC_N(struct rb_class_cc_entries_entry, ccs->capa);
        }
        else {
            ccs->capa *= 2;
            REALLOC_N(ccs->entries, struct rb_class_cc_entries_entry, ccs->capa);
        }
    }
    VM_ASSERT(ccs->len < ccs->capa);

    const int pos = ccs->len++;
    ccs->entries[pos].argc = vm_ci_argc(ci);
    ccs->entries[pos].flag = vm_ci_flag(ci);
    RB_OBJ_WRITE(klass, &ccs->entries[pos].cc, cc);

    if (RB_DEBUG_COUNTER_SETMAX(ccs_maxlen, ccs->len)) {
        // for tuning
        // vm_mtbl_dump(klass, 0);
    }
}

#if VM_CHECK_MODE > 0
void
rb_vm_ccs_dump(struct rb_class_cc_entries *ccs)
{
    ruby_debug_printf("ccs:%p (%d,%d)\n", (void *)ccs, ccs->len, ccs->capa);
    for (int i=0; i<ccs->len; i++) {
        ruby_debug_printf("CCS CI ID:flag:%x argc:%u\n",
                ccs->entries[i].flag,
                ccs->entries[i].argc);
        rp(ccs->entries[i].cc);
    }
}

static int
vm_ccs_verify(struct rb_class_cc_entries *ccs, ID mid, VALUE klass)
{
    VM_ASSERT(vm_ccs_p(ccs));
    VM_ASSERT(ccs->len <= ccs->capa);

    for (int i=0; i<ccs->len; i++) {
        const struct rb_callcache *cc = ccs->entries[i].cc;

        VM_ASSERT(IMEMO_TYPE_P(cc, imemo_callcache));
        VM_ASSERT(vm_cc_class_check(cc, klass));
        VM_ASSERT(vm_cc_check_cme(cc, ccs->cme));
        VM_ASSERT(!vm_cc_super_p(cc));
        VM_ASSERT(!vm_cc_refinement_p(cc));
    }
    return TRUE;
}
#endif

const rb_callable_method_entry_t *rb_check_overloaded_cme(const rb_callable_method_entry_t *cme, const struct rb_callinfo * const ci);

static const struct rb_callcache *
vm_search_cc(const VALUE klass, const struct rb_callinfo * const ci)
{
    const ID mid = vm_ci_mid(ci);
    struct rb_id_table *cc_tbl = RCLASS_CC_TBL(klass);
    struct rb_class_cc_entries *ccs = NULL;
    VALUE ccs_data;

    if (cc_tbl) {
        // CCS data is keyed on method id, so we don't need the method id
        // for doing comparisons in the `for` loop below.
        if (rb_id_table_lookup(cc_tbl, mid, &ccs_data)) {
            ccs = (struct rb_class_cc_entries *)ccs_data;
            const int ccs_len = ccs->len;

            if (UNLIKELY(METHOD_ENTRY_INVALIDATED(ccs->cme))) {
                rb_vm_ccs_free(ccs);
                rb_id_table_delete(cc_tbl, mid);
                ccs = NULL;
            }
            else {
                VM_ASSERT(vm_ccs_verify(ccs, mid, klass));

                // We already know the method id is correct because we had
                // to look up the ccs_data by method id.  All we need to
                // compare is argc and flag
                unsigned int argc = vm_ci_argc(ci);
                unsigned int flag = vm_ci_flag(ci);

                for (int i=0; i<ccs_len; i++) {
                    unsigned int ccs_ci_argc = ccs->entries[i].argc;
                    unsigned int ccs_ci_flag = ccs->entries[i].flag;
                    const struct rb_callcache *ccs_cc = ccs->entries[i].cc;

                    VM_ASSERT(IMEMO_TYPE_P(ccs_cc, imemo_callcache));

                    if (ccs_ci_argc == argc && ccs_ci_flag == flag) {
                        RB_DEBUG_COUNTER_INC(cc_found_in_ccs);

                        VM_ASSERT(vm_cc_cme(ccs_cc)->called_id == mid);
                        VM_ASSERT(ccs_cc->klass == klass);
                        VM_ASSERT(!METHOD_ENTRY_INVALIDATED(vm_cc_cme(ccs_cc)));

                        return ccs_cc;
                    }
                }
            }
        }
    }
    else {
        cc_tbl = RCLASS_CC_TBL(klass) = rb_id_table_create(2);
    }

    RB_DEBUG_COUNTER_INC(cc_not_found_in_ccs);

    const rb_callable_method_entry_t *cme;

    if (ccs) {
        cme = ccs->cme;
        cme = UNDEFINED_METHOD_ENTRY_P(cme) ? NULL : cme;

        VM_ASSERT(cme == rb_callable_method_entry(klass, mid));
    }
    else {
        cme = rb_callable_method_entry(klass, mid);
    }

    VM_ASSERT(cme == NULL || IMEMO_TYPE_P(cme, imemo_ment));

    if (cme == NULL) {
        // undef or not found: can't cache the information
        VM_ASSERT(vm_cc_cme(&vm_empty_cc) == NULL);
        return &vm_empty_cc;
    }

    VM_ASSERT(cme == rb_callable_method_entry(klass, mid));

    METHOD_ENTRY_CACHED_SET((struct rb_callable_method_entry_struct *)cme);

    if (ccs == NULL) {
        VM_ASSERT(cc_tbl != NULL);

        if (LIKELY(rb_id_table_lookup(cc_tbl, mid, &ccs_data))) {
            // rb_callable_method_entry() prepares ccs.
            ccs = (struct rb_class_cc_entries *)ccs_data;
        }
        else {
            // TODO: required?
            ccs = vm_ccs_create(klass, cc_tbl, mid, cme);
        }
    }

    cme = rb_check_overloaded_cme(cme, ci);

    const struct rb_callcache *cc = vm_cc_new(klass, cme, vm_call_general, cc_type_normal);
    vm_ccs_push(klass, ccs, ci, cc);

    VM_ASSERT(vm_cc_cme(cc) != NULL);
    VM_ASSERT(cme->called_id == mid);
    VM_ASSERT(vm_cc_cme(cc)->called_id == mid);

    return cc;
}

const struct rb_callcache *
rb_vm_search_method_slowpath(const struct rb_callinfo *ci, VALUE klass)
{
    const struct rb_callcache *cc;

    VM_ASSERT(RB_TYPE_P(klass, T_CLASS) || RB_TYPE_P(klass, T_ICLASS));

    RB_VM_LOCK_ENTER();
    {
        cc = vm_search_cc(klass, ci);

        VM_ASSERT(cc);
        VM_ASSERT(IMEMO_TYPE_P(cc, imemo_callcache));
        VM_ASSERT(cc == vm_cc_empty() || cc->klass == klass);
        VM_ASSERT(cc == vm_cc_empty() || callable_method_entry_p(vm_cc_cme(cc)));
        VM_ASSERT(cc == vm_cc_empty() || !METHOD_ENTRY_INVALIDATED(vm_cc_cme(cc)));
        VM_ASSERT(cc == vm_cc_empty() || vm_cc_cme(cc)->called_id == vm_ci_mid(ci));
    }
    RB_VM_LOCK_LEAVE();

    return cc;
}

static const struct rb_callcache *
vm_search_method_slowpath0(VALUE cd_owner, struct rb_call_data *cd, VALUE klass)
{
#if USE_DEBUG_COUNTER
    const struct rb_callcache *old_cc = cd->cc;
#endif

    const struct rb_callcache *cc = rb_vm_search_method_slowpath(cd->ci, klass);

#if OPT_INLINE_METHOD_CACHE
    cd->cc = cc;

    const struct rb_callcache *empty_cc = &vm_empty_cc;
    if (cd_owner && cc != empty_cc) {
        RB_OBJ_WRITTEN(cd_owner, Qundef, cc);
    }

#if USE_DEBUG_COUNTER
    if (!old_cc || old_cc == empty_cc) {
        // empty
        RB_DEBUG_COUNTER_INC(mc_inline_miss_empty);
    }
    else if (old_cc == cc) {
        RB_DEBUG_COUNTER_INC(mc_inline_miss_same_cc);
    }
    else if (vm_cc_cme(old_cc) == vm_cc_cme(cc)) {
        RB_DEBUG_COUNTER_INC(mc_inline_miss_same_cme);
    }
    else if (vm_cc_cme(old_cc) && vm_cc_cme(cc) &&
             vm_cc_cme(old_cc)->def == vm_cc_cme(cc)->def) {
        RB_DEBUG_COUNTER_INC(mc_inline_miss_same_def);
    }
    else {
        RB_DEBUG_COUNTER_INC(mc_inline_miss_diff);
    }
#endif
#endif // OPT_INLINE_METHOD_CACHE

    VM_ASSERT(vm_cc_cme(cc) == NULL ||
              vm_cc_cme(cc)->called_id == vm_ci_mid(cd->ci));

    return cc;
}

ALWAYS_INLINE(static const struct rb_callcache *vm_search_method_fastpath(VALUE cd_owner, struct rb_call_data *cd, VALUE klass));
static const struct rb_callcache *
vm_search_method_fastpath(VALUE cd_owner, struct rb_call_data *cd, VALUE klass)
{
    const struct rb_callcache *cc = cd->cc;

#if OPT_INLINE_METHOD_CACHE
    if (LIKELY(vm_cc_class_check(cc, klass))) {
        if (LIKELY(!METHOD_ENTRY_INVALIDATED(vm_cc_cme(cc)))) {
            VM_ASSERT(callable_method_entry_p(vm_cc_cme(cc)));
            RB_DEBUG_COUNTER_INC(mc_inline_hit);
            VM_ASSERT(vm_cc_cme(cc) == NULL ||                        // not found
                      (vm_ci_flag(cd->ci) & VM_CALL_SUPER) ||         // search_super w/ define_method
                      vm_cc_cme(cc)->called_id == vm_ci_mid(cd->ci)); // cme->called_id == ci->mid

            return cc;
        }
        RB_DEBUG_COUNTER_INC(mc_inline_miss_invalidated);
    }
    else {
        RB_DEBUG_COUNTER_INC(mc_inline_miss_klass);
    }
#endif

    return vm_search_method_slowpath0(cd_owner, cd, klass);
}

static const struct rb_callcache *
vm_search_method(VALUE cd_owner, struct rb_call_data *cd, VALUE recv)
{
    VALUE klass = CLASS_OF(recv);
    VM_ASSERT(klass != Qfalse);
    VM_ASSERT(RBASIC_CLASS(klass) == 0 || rb_obj_is_kind_of(klass, rb_cClass));

    return vm_search_method_fastpath(cd_owner, cd, klass);
}

#if __has_attribute(transparent_union)
typedef union {
    VALUE (*anyargs)(ANYARGS);
    VALUE (*f00)(VALUE);
    VALUE (*f01)(VALUE, VALUE);
    VALUE (*f02)(VALUE, VALUE, VALUE);
    VALUE (*f03)(VALUE, VALUE, VALUE, VALUE);
    VALUE (*f04)(VALUE, VALUE, VALUE, VALUE, VALUE);
    VALUE (*f05)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE);
    VALUE (*f06)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE);
    VALUE (*f07)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE);
    VALUE (*f08)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE);
    VALUE (*f09)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE);
    VALUE (*f10)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE);
    VALUE (*f11)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE);
    VALUE (*f12)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE);
    VALUE (*f13)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE);
    VALUE (*f14)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE);
    VALUE (*f15)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE);
    VALUE (*fm1)(int, union { VALUE *x; const VALUE *y; } __attribute__((__transparent_union__)), VALUE);
} __attribute__((__transparent_union__)) cfunc_type;
#else
typedef VALUE (*cfunc_type)(ANYARGS);
#endif

static inline int
check_cfunc(const rb_callable_method_entry_t *me, cfunc_type func)
{
    if (! me) {
        return false;
    }
    else {
        VM_ASSERT(IMEMO_TYPE_P(me, imemo_ment));
        VM_ASSERT(callable_method_entry_p(me));
        VM_ASSERT(me->def);
        if (me->def->type != VM_METHOD_TYPE_CFUNC) {
            return false;
        }
        else {
#if __has_attribute(transparent_union)
            return me->def->body.cfunc.func == func.anyargs;
#else
            return me->def->body.cfunc.func == func;
#endif
        }
    }
}

static inline int
vm_method_cfunc_is(const rb_iseq_t *iseq, CALL_DATA cd, VALUE recv, cfunc_type func)
{
    VM_ASSERT(iseq != NULL);
    const struct rb_callcache *cc = vm_search_method((VALUE)iseq, cd, recv);
    return check_cfunc(vm_cc_cme(cc), func);
}

#define EQ_UNREDEFINED_P(t) BASIC_OP_UNREDEFINED_P(BOP_EQ, t##_REDEFINED_OP_FLAG)

static inline bool
FIXNUM_2_P(VALUE a, VALUE b)
{
    /* FIXNUM_P(a) && FIXNUM_P(b)
     * == ((a & 1) && (b & 1))
     * == a & b & 1 */
    SIGNED_VALUE x = a;
    SIGNED_VALUE y = b;
    SIGNED_VALUE z = x & y & 1;
    return z == 1;
}

static inline bool
FLONUM_2_P(VALUE a, VALUE b)
{
#if USE_FLONUM
    /* FLONUM_P(a) && FLONUM_P(b)
     * == ((a & 3) == 2) && ((b & 3) == 2)
     * == ! ((a ^ 2) | (b ^ 2) & 3)
     */
    SIGNED_VALUE x = a;
    SIGNED_VALUE y = b;
    SIGNED_VALUE z = ((x ^ 2) | (y ^ 2)) & 3;
    return !z;
#else
    return false;
#endif
}

static VALUE
opt_equality_specialized(VALUE recv, VALUE obj)
{
    if (FIXNUM_2_P(recv, obj) && EQ_UNREDEFINED_P(INTEGER)) {
        goto compare_by_identity;
    }
    else if (FLONUM_2_P(recv, obj) && EQ_UNREDEFINED_P(FLOAT)) {
        goto compare_by_identity;
    }
    else if (STATIC_SYM_P(recv) && STATIC_SYM_P(obj) && EQ_UNREDEFINED_P(SYMBOL)) {
        goto compare_by_identity;
    }
    else if (SPECIAL_CONST_P(recv)) {
        //
    }
    else if (RBASIC_CLASS(recv) == rb_cFloat && RB_FLOAT_TYPE_P(obj) && EQ_UNREDEFINED_P(FLOAT)) {
        double a = RFLOAT_VALUE(recv);
        double b = RFLOAT_VALUE(obj);

#if MSC_VERSION_BEFORE(1300)
        if (isnan(a)) {
            return Qfalse;
        }
        else if (isnan(b)) {
            return Qfalse;
        }
        else
#endif
        return RBOOL(a == b);
    }
    else if (RBASIC_CLASS(recv) == rb_cString && EQ_UNREDEFINED_P(STRING)) {
        if (recv == obj) {
            return Qtrue;
        }
        else if (RB_TYPE_P(obj, T_STRING)) {
            return rb_str_eql_internal(obj, recv);
        }
    }
    return Qundef;

  compare_by_identity:
    return RBOOL(recv == obj);
}

static VALUE
opt_equality(const rb_iseq_t *cd_owner, VALUE recv, VALUE obj, CALL_DATA cd)
{
    VM_ASSERT(cd_owner != NULL);

    VALUE val = opt_equality_specialized(recv, obj);
    if (!UNDEF_P(val)) return val;

    if (!vm_method_cfunc_is(cd_owner, cd, recv, rb_obj_equal)) {
        return Qundef;
    }
    else {
        return RBOOL(recv == obj);
    }
}

#undef EQ_UNREDEFINED_P

static inline const struct rb_callcache *gccct_method_search(rb_execution_context_t *ec, VALUE recv, ID mid, const struct rb_callinfo *ci); // vm_eval.c
NOINLINE(static VALUE opt_equality_by_mid_slowpath(VALUE recv, VALUE obj, ID mid));

static VALUE
opt_equality_by_mid_slowpath(VALUE recv, VALUE obj, ID mid)
{
    const struct rb_callcache *cc = gccct_method_search(GET_EC(), recv, mid, &VM_CI_ON_STACK(mid, 0, 1, NULL));

    if (cc && check_cfunc(vm_cc_cme(cc), rb_obj_equal)) {
        return RBOOL(recv == obj);
    }
    else {
        return Qundef;
    }
}

static VALUE
opt_equality_by_mid(VALUE recv, VALUE obj, ID mid)
{
    VALUE val = opt_equality_specialized(recv, obj);
    if (!UNDEF_P(val)) {
        return val;
    }
    else {
        return opt_equality_by_mid_slowpath(recv, obj, mid);
    }
}

VALUE
rb_equal_opt(VALUE obj1, VALUE obj2)
{
    return opt_equality_by_mid(obj1, obj2, idEq);
}

VALUE
rb_eql_opt(VALUE obj1, VALUE obj2)
{
    return opt_equality_by_mid(obj1, obj2, idEqlP);
}

extern VALUE rb_vm_call0(rb_execution_context_t *ec, VALUE, ID, int, const VALUE*, const rb_callable_method_entry_t *, int kw_splat);
extern VALUE rb_vm_call_with_refinements(rb_execution_context_t *, VALUE, ID, int, const VALUE *, int);

static VALUE
check_match(rb_execution_context_t *ec, VALUE pattern, VALUE target, enum vm_check_match_type type)
{
    switch (type) {
      case VM_CHECKMATCH_TYPE_WHEN:
        return pattern;
      case VM_CHECKMATCH_TYPE_RESCUE:
        if (!rb_obj_is_kind_of(pattern, rb_cModule)) {
            rb_raise(rb_eTypeError, "class or module required for rescue clause");
        }
        /* fall through */
      case VM_CHECKMATCH_TYPE_CASE: {
        return rb_vm_call_with_refinements(ec, pattern, idEqq, 1, &target, RB_NO_KEYWORDS);
      }
      default:
        rb_bug("check_match: unreachable");
    }
}


#if MSC_VERSION_BEFORE(1300)
#define CHECK_CMP_NAN(a, b) if (isnan(a) || isnan(b)) return Qfalse;
#else
#define CHECK_CMP_NAN(a, b) /* do nothing */
#endif

static inline VALUE
double_cmp_lt(double a, double b)
{
    CHECK_CMP_NAN(a, b);
    return RBOOL(a < b);
}

static inline VALUE
double_cmp_le(double a, double b)
{
    CHECK_CMP_NAN(a, b);
    return RBOOL(a <= b);
}

static inline VALUE
double_cmp_gt(double a, double b)
{
    CHECK_CMP_NAN(a, b);
    return RBOOL(a > b);
}

static inline VALUE
double_cmp_ge(double a, double b)
{
    CHECK_CMP_NAN(a, b);
    return RBOOL(a >= b);
}

// Copied by vm_dump.c
static inline VALUE *
vm_base_ptr(const rb_control_frame_t *cfp)
{
    const rb_control_frame_t *prev_cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);

    if (cfp->iseq && VM_FRAME_RUBYFRAME_P(cfp)) {
        VALUE *bp = prev_cfp->sp + ISEQ_BODY(cfp->iseq)->local_table_size + VM_ENV_DATA_SIZE;

        if (ISEQ_BODY(cfp->iseq)->param.flags.forwardable && VM_ENV_LOCAL_P(cfp->ep)) {
            int lts = ISEQ_BODY(cfp->iseq)->local_table_size;
            int params = ISEQ_BODY(cfp->iseq)->param.size;

            CALL_INFO ci = (CALL_INFO)cfp->ep[-(VM_ENV_DATA_SIZE + (lts - params))]; // skip EP stuff, CI should be last local
            bp += vm_ci_argc(ci);
        }

        if (ISEQ_BODY(cfp->iseq)->type == ISEQ_TYPE_METHOD || VM_FRAME_BMETHOD_P(cfp)) {
            /* adjust `self' */
            bp += 1;
        }
#if VM_DEBUG_BP_CHECK
        if (bp != cfp->bp_check) {
            ruby_debug_printf("bp_check: %ld, bp: %ld\n",
                    (long)(cfp->bp_check - GET_EC()->vm_stack),
                    (long)(bp - GET_EC()->vm_stack));
            rb_bug("vm_base_ptr: unreachable");
        }
#endif
        return bp;
    }
    else {
        return NULL;
    }
}

VALUE *
rb_vm_base_ptr(const rb_control_frame_t *cfp)
{
    return vm_base_ptr(cfp);
}

/* method call processes with call_info */

#include "vm_args.c"

static inline VALUE vm_call_iseq_setup_2(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling, int opt_pc, int param_size, int local_size);
ALWAYS_INLINE(static VALUE vm_call_iseq_setup_normal(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling, const rb_callable_method_entry_t *me, int opt_pc, int param_size, int local_size));
static inline VALUE vm_call_iseq_setup_tailcall(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling, int opt_pc);
static VALUE vm_call_super_method(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling);
static VALUE vm_call_method_nome(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling);
static VALUE vm_call_method_each_type(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling);
static inline VALUE vm_call_method(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling);

static vm_call_handler vm_call_iseq_setup_func(const struct rb_callinfo *ci, const int param_size, const int local_size);

static VALUE
vm_call_iseq_setup_tailcall_0start(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    RB_DEBUG_COUNTER_INC(ccf_iseq_setup_tailcall_0start);

    return vm_call_iseq_setup_tailcall(ec, cfp, calling, 0);
}

static VALUE
vm_call_iseq_setup_normal_0start(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    RB_DEBUG_COUNTER_INC(ccf_iseq_setup_0start);

    const struct rb_callcache *cc = calling->cc;
    const rb_iseq_t *iseq = def_iseq_ptr(vm_cc_cme(cc)->def);
    int param = ISEQ_BODY(iseq)->param.size;
    int local = ISEQ_BODY(iseq)->local_table_size;
    return vm_call_iseq_setup_normal(ec, cfp, calling, vm_cc_cme(cc), 0, param, local);
}

bool
rb_simple_iseq_p(const rb_iseq_t *iseq)
{
    return ISEQ_BODY(iseq)->param.flags.has_opt == FALSE &&
           ISEQ_BODY(iseq)->param.flags.has_rest == FALSE &&
           ISEQ_BODY(iseq)->param.flags.has_post == FALSE &&
           ISEQ_BODY(iseq)->param.flags.has_kw == FALSE &&
           ISEQ_BODY(iseq)->param.flags.has_kwrest == FALSE &&
           ISEQ_BODY(iseq)->param.flags.accepts_no_kwarg == FALSE &&
           ISEQ_BODY(iseq)->param.flags.forwardable == FALSE &&
           ISEQ_BODY(iseq)->param.flags.has_block == FALSE;
}

bool
rb_iseq_only_optparam_p(const rb_iseq_t *iseq)
{
    return ISEQ_BODY(iseq)->param.flags.has_opt == TRUE &&
           ISEQ_BODY(iseq)->param.flags.has_rest == FALSE &&
           ISEQ_BODY(iseq)->param.flags.has_post == FALSE &&
           ISEQ_BODY(iseq)->param.flags.has_kw == FALSE &&
           ISEQ_BODY(iseq)->param.flags.has_kwrest == FALSE &&
           ISEQ_BODY(iseq)->param.flags.accepts_no_kwarg == FALSE &&
           ISEQ_BODY(iseq)->param.flags.forwardable == FALSE &&
           ISEQ_BODY(iseq)->param.flags.has_block == FALSE;
}

bool
rb_iseq_only_kwparam_p(const rb_iseq_t *iseq)
{
    return ISEQ_BODY(iseq)->param.flags.has_opt == FALSE &&
           ISEQ_BODY(iseq)->param.flags.has_rest == FALSE &&
           ISEQ_BODY(iseq)->param.flags.has_post == FALSE &&
           ISEQ_BODY(iseq)->param.flags.has_kw == TRUE &&
           ISEQ_BODY(iseq)->param.flags.has_kwrest == FALSE &&
           ISEQ_BODY(iseq)->param.flags.forwardable == FALSE &&
           ISEQ_BODY(iseq)->param.flags.has_block == FALSE;
}

#define ALLOW_HEAP_ARGV (-2)
#define ALLOW_HEAP_ARGV_KEEP_KWSPLAT (-3)

static inline bool
vm_caller_setup_arg_splat(rb_control_frame_t *cfp, struct rb_calling_info *calling, VALUE ary, int max_args)
{
    vm_check_canary(GET_EC(), cfp->sp);
    bool ret = false;

    if (!NIL_P(ary)) {
        const VALUE *ptr = RARRAY_CONST_PTR(ary);
        long len = RARRAY_LEN(ary);
        int argc = calling->argc;

        if (UNLIKELY(max_args <= ALLOW_HEAP_ARGV && len + argc > VM_ARGC_STACK_MAX)) {
            /* Avoid SystemStackError when splatting large arrays by storing arguments in
             * a temporary array, instead of trying to keeping arguments on the VM stack.
             */
            VALUE *argv = cfp->sp - argc;
            VALUE argv_ary = rb_ary_hidden_new(len + argc + 1);
            rb_ary_cat(argv_ary, argv, argc);
            rb_ary_cat(argv_ary, ptr, len);
            cfp->sp -= argc - 1;
            cfp->sp[-1] = argv_ary;
            calling->argc = 1;
            calling->heap_argv = argv_ary;
            RB_GC_GUARD(ary);
        }
        else {
            long i;

            if (max_args >= 0 && len + argc > max_args) {
                /* If only a given max_args is allowed, copy up to max args.
                 * Used by vm_callee_setup_block_arg for non-lambda blocks,
                 * where additional arguments are ignored.
                 *
                 * Also, copy up to one more argument than the maximum,
                 * in case it is an empty keyword hash that will be removed.
                 */
                calling->argc += len - (max_args - argc + 1);
                len = max_args - argc + 1;
                ret = true;
            }
            else {
                /* Unset heap_argv if set originally.  Can happen when
                 * forwarding modified arguments, where heap_argv was used
                 * originally, but heap_argv not supported by the forwarded
                 * method in all cases.
                 */
                calling->heap_argv = 0;
            }
            CHECK_VM_STACK_OVERFLOW(cfp, len);

            for (i = 0; i < len; i++) {
                *cfp->sp++ = ptr[i];
            }
            calling->argc += i;
        }
    }

    return ret;
}

static inline void
vm_caller_setup_arg_kw(rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_callinfo *ci)
{
    const VALUE *const passed_keywords = vm_ci_kwarg(ci)->keywords;
    const int kw_len = vm_ci_kwarg(ci)->keyword_len;
    const VALUE h = rb_hash_new_with_size(kw_len);
    VALUE *sp = cfp->sp;
    int i;

    for (i=0; i<kw_len; i++) {
        rb_hash_aset(h, passed_keywords[i], (sp - kw_len)[i]);
    }
    (sp-kw_len)[0] = h;

    cfp->sp -= kw_len - 1;
    calling->argc -= kw_len - 1;
    calling->kw_splat = 1;
}

static inline VALUE
vm_caller_setup_keyword_hash(const struct rb_callinfo *ci, VALUE keyword_hash)
{
    if (UNLIKELY(!RB_TYPE_P(keyword_hash, T_HASH))) {
        if (keyword_hash != Qnil) {
            /* Convert a non-hash keyword splat to a new hash */
            keyword_hash = rb_hash_dup(rb_to_hash_type(keyword_hash));
        }
    }
    else if (!IS_ARGS_KW_SPLAT_MUT(ci)) {
        /* Convert a hash keyword splat to a new hash unless
         * a mutable keyword splat was passed.
         */
        keyword_hash = rb_hash_dup(keyword_hash);
    }
    return keyword_hash;
}

static inline void
CALLER_SETUP_ARG(struct rb_control_frame_struct *restrict cfp,
                 struct rb_calling_info *restrict calling,
                 const struct rb_callinfo *restrict ci, int max_args)
{
    if (UNLIKELY(IS_ARGS_SPLAT(ci))) {
        if (IS_ARGS_KW_SPLAT(ci)) {
            // f(*a, **kw)
            VM_ASSERT(calling->kw_splat == 1);

            cfp->sp -= 2;
            calling->argc -= 2;
            VALUE ary = cfp->sp[0];
            VALUE kwh = vm_caller_setup_keyword_hash(ci, cfp->sp[1]);

            // splat a
            if (vm_caller_setup_arg_splat(cfp, calling, ary, max_args)) return;

            // put kw
            if (kwh != Qnil && !RHASH_EMPTY_P(kwh)) {
                if (UNLIKELY(calling->heap_argv)) {
                    rb_ary_push(calling->heap_argv, kwh);
                    ((struct RHash *)kwh)->basic.flags |= RHASH_PASS_AS_KEYWORDS;
                    if (max_args != ALLOW_HEAP_ARGV_KEEP_KWSPLAT) {
                        calling->kw_splat = 0;
                    }
                }
                else {
                    cfp->sp[0] = kwh;
                    cfp->sp++;
                    calling->argc++;

                    VM_ASSERT(calling->kw_splat == 1);
                }
            }
            else {
                calling->kw_splat = 0;
            }
        }
        else {
            // f(*a)
            VM_ASSERT(calling->kw_splat == 0);

            cfp->sp -= 1;
            calling->argc -= 1;
            VALUE ary = cfp->sp[0];

            if (vm_caller_setup_arg_splat(cfp, calling, ary, max_args)) {
                goto check_keyword;
            }

            // check the last argument
            VALUE last_hash, argv_ary;
            if (UNLIKELY(argv_ary = calling->heap_argv)) {
                if (!IS_ARGS_KEYWORD(ci) &&
                    RARRAY_LEN(argv_ary) > 0 &&
                    RB_TYPE_P((last_hash = rb_ary_last(0, NULL, argv_ary)), T_HASH) &&
                    (((struct RHash *)last_hash)->basic.flags & RHASH_PASS_AS_KEYWORDS)) {

                    rb_ary_pop(argv_ary);
                    if (!RHASH_EMPTY_P(last_hash)) {
                        rb_ary_push(argv_ary, rb_hash_dup(last_hash));
                        calling->kw_splat = 1;
                    }
                }
            }
            else {
check_keyword:
                if (!IS_ARGS_KEYWORD(ci) &&
                    calling->argc > 0 &&
                    RB_TYPE_P((last_hash = cfp->sp[-1]), T_HASH) &&
                    (((struct RHash *)last_hash)->basic.flags & RHASH_PASS_AS_KEYWORDS)) {

                    if (RHASH_EMPTY_P(last_hash)) {
                        calling->argc--;
                        cfp->sp -= 1;
                    }
                    else {
                        cfp->sp[-1] = rb_hash_dup(last_hash);
                        calling->kw_splat = 1;
                    }
                }
            }
        }
    }
    else if (UNLIKELY(IS_ARGS_KW_SPLAT(ci))) {
        // f(**kw)
        VM_ASSERT(calling->kw_splat == 1);
        VALUE kwh = vm_caller_setup_keyword_hash(ci, cfp->sp[-1]);

        if (kwh == Qnil || RHASH_EMPTY_P(kwh)) {
            cfp->sp--;
            calling->argc--;
            calling->kw_splat = 0;
        }
        else {
            cfp->sp[-1] = kwh;
        }
    }
    else if (UNLIKELY(IS_ARGS_KEYWORD(ci))) {
        // f(k1:1, k2:2)
        VM_ASSERT(calling->kw_splat == 0);

        /* This converts VM_CALL_KWARG style to VM_CALL_KW_SPLAT style
         * by creating a keyword hash.
         * So, vm_ci_flag(ci) & VM_CALL_KWARG is now inconsistent.
         */
        vm_caller_setup_arg_kw(cfp, calling, ci);
    }
}

#define USE_OPT_HIST 0

#if USE_OPT_HIST
#define OPT_HIST_MAX 64
static int opt_hist[OPT_HIST_MAX+1];

__attribute__((destructor))
static void
opt_hist_show_results_at_exit(void)
{
    for (int i=0; i<OPT_HIST_MAX; i++) {
        ruby_debug_printf("opt_hist\t%d\t%d\n", i, opt_hist[i]);
    }
}
#endif

static VALUE
vm_call_iseq_setup_normal_opt_start(rb_execution_context_t *ec, rb_control_frame_t *cfp,
                                    struct rb_calling_info *calling)
{
    const struct rb_callcache *cc = calling->cc;
    const rb_iseq_t *iseq = def_iseq_ptr(vm_cc_cme(cc)->def);
    const int lead_num = ISEQ_BODY(iseq)->param.lead_num;
    const int opt = calling->argc - lead_num;
    const int opt_num = ISEQ_BODY(iseq)->param.opt_num;
    const int opt_pc = (int)ISEQ_BODY(iseq)->param.opt_table[opt];
    const int param = ISEQ_BODY(iseq)->param.size;
    const int local = ISEQ_BODY(iseq)->local_table_size;
    const int delta = opt_num - opt;

    RB_DEBUG_COUNTER_INC(ccf_iseq_opt);

#if USE_OPT_HIST
    if (opt_pc < OPT_HIST_MAX) {
        opt_hist[opt]++;
    }
    else {
        opt_hist[OPT_HIST_MAX]++;
    }
#endif

    return vm_call_iseq_setup_normal(ec, cfp, calling, vm_cc_cme(cc), opt_pc, param - delta, local);
}

static VALUE
vm_call_iseq_setup_tailcall_opt_start(rb_execution_context_t *ec, rb_control_frame_t *cfp,
                                      struct rb_calling_info *calling)
{
    const struct rb_callcache *cc = calling->cc;
    const rb_iseq_t *iseq = def_iseq_ptr(vm_cc_cme(cc)->def);
    const int lead_num = ISEQ_BODY(iseq)->param.lead_num;
    const int opt = calling->argc - lead_num;
    const int opt_pc = (int)ISEQ_BODY(iseq)->param.opt_table[opt];

    RB_DEBUG_COUNTER_INC(ccf_iseq_opt);

#if USE_OPT_HIST
    if (opt_pc < OPT_HIST_MAX) {
        opt_hist[opt]++;
    }
    else {
        opt_hist[OPT_HIST_MAX]++;
    }
#endif

    return vm_call_iseq_setup_tailcall(ec, cfp, calling, opt_pc);
}

static void
args_setup_kw_parameters(rb_execution_context_t *const ec, const rb_iseq_t *const iseq,
                         VALUE *const passed_values, const int passed_keyword_len, const VALUE *const passed_keywords,
                         VALUE *const locals);

static VALUE
vm_call_iseq_forwardable(rb_execution_context_t *ec, rb_control_frame_t *cfp,
                                struct rb_calling_info *calling)
{
    const struct rb_callcache *cc = calling->cc;
    const rb_iseq_t *iseq = def_iseq_ptr(vm_cc_cme(cc)->def);
    int param_size = ISEQ_BODY(iseq)->param.size;
    int local_size = ISEQ_BODY(iseq)->local_table_size;

    // Setting up local size and param size
    VM_ASSERT(ISEQ_BODY(iseq)->param.flags.forwardable);

    local_size = local_size + vm_ci_argc(calling->cd->ci);
    param_size = param_size + vm_ci_argc(calling->cd->ci);

    cfp->sp[0] = (VALUE)calling->cd->ci;

    return vm_call_iseq_setup_normal(ec, cfp, calling, vm_cc_cme(cc), 0, param_size, local_size);
}

static VALUE
vm_call_iseq_setup_kwparm_kwarg(rb_execution_context_t *ec, rb_control_frame_t *cfp,
                                struct rb_calling_info *calling)
{
    const struct rb_callinfo *ci = calling->cd->ci;
    const struct rb_callcache *cc = calling->cc;

    VM_ASSERT(vm_ci_flag(ci) & VM_CALL_KWARG);
    RB_DEBUG_COUNTER_INC(ccf_iseq_kw1);

    const rb_iseq_t *iseq = def_iseq_ptr(vm_cc_cme(cc)->def);
    const struct rb_iseq_param_keyword *kw_param = ISEQ_BODY(iseq)->param.keyword;
    const struct rb_callinfo_kwarg *kw_arg = vm_ci_kwarg(ci);
    const int ci_kw_len = kw_arg->keyword_len;
    const VALUE * const ci_keywords = kw_arg->keywords;
    VALUE *argv = cfp->sp - calling->argc;
    VALUE *const klocals = argv + kw_param->bits_start - kw_param->num;
    const int lead_num = ISEQ_BODY(iseq)->param.lead_num;
    VALUE * const ci_kws = ALLOCA_N(VALUE, ci_kw_len);
    MEMCPY(ci_kws, argv + lead_num, VALUE, ci_kw_len);
    args_setup_kw_parameters(ec, iseq, ci_kws, ci_kw_len, ci_keywords, klocals);

    int param = ISEQ_BODY(iseq)->param.size;
    int local = ISEQ_BODY(iseq)->local_table_size;
    return vm_call_iseq_setup_normal(ec, cfp, calling, vm_cc_cme(cc), 0, param, local);
}

static VALUE
vm_call_iseq_setup_kwparm_nokwarg(rb_execution_context_t *ec, rb_control_frame_t *cfp,
                                  struct rb_calling_info *calling)
{
    const struct rb_callinfo *MAYBE_UNUSED(ci) = calling->cd->ci;
    const struct rb_callcache *cc = calling->cc;

    VM_ASSERT((vm_ci_flag(ci) & VM_CALL_KWARG) == 0);
    RB_DEBUG_COUNTER_INC(ccf_iseq_kw2);

    const rb_iseq_t *iseq = def_iseq_ptr(vm_cc_cme(cc)->def);
    const struct rb_iseq_param_keyword *kw_param = ISEQ_BODY(iseq)->param.keyword;
    VALUE * const argv = cfp->sp - calling->argc;
    VALUE * const klocals = argv + kw_param->bits_start - kw_param->num;

    int i;
    for (i=0; i<kw_param->num; i++) {
        klocals[i] = kw_param->default_values[i];
    }
    klocals[i] = INT2FIX(0); // kw specify flag
    // NOTE:
    //   nobody check this value, but it should be cleared because it can
    //   points invalid VALUE (T_NONE objects, raw pointer and so on).

    int param = ISEQ_BODY(iseq)->param.size;
    int local = ISEQ_BODY(iseq)->local_table_size;
    return vm_call_iseq_setup_normal(ec, cfp, calling, vm_cc_cme(cc), 0, param, local);
}

static VALUE builtin_invoker0(rb_execution_context_t *ec, VALUE self, const VALUE *argv, rb_insn_func_t funcptr);

static VALUE
vm_call_single_noarg_leaf_builtin(rb_execution_context_t *ec, rb_control_frame_t *cfp,
                                    struct rb_calling_info *calling)
{
    const struct rb_builtin_function *bf = calling->cc->aux_.bf;
    cfp->sp -= (calling->argc + 1);
    return builtin_invoker0(ec, calling->recv, NULL, (rb_insn_func_t)bf->func_ptr);
}

VALUE rb_gen_method_name(VALUE owner, VALUE name); // in vm_backtrace.c

static void
warn_unused_block(const rb_callable_method_entry_t *cme, const rb_iseq_t *iseq, void *pc)
{
    rb_vm_t *vm = GET_VM();
    st_table *dup_check_table = vm->unused_block_warning_table;
    st_data_t key;

    union {
        VALUE v;
        unsigned char b[SIZEOF_VALUE];
    } k1 = {
        .v = (VALUE)pc,
    }, k2 = {
        .v = (VALUE)cme->def,
    };

    // relax check
    if (!vm->unused_block_warning_strict) {
        key = (st_data_t)cme->def->original_id;

        if (st_lookup(dup_check_table, key, NULL)) {
            return;
        }
    }

    // strict check
    // make unique key from pc and me->def pointer
    key = 0;
    for (int i=0; i<SIZEOF_VALUE; i++) {
        // fprintf(stderr, "k1:%3d k2:%3d\n", k1.b[i], k2.b[SIZEOF_VALUE-1-i]);
        key |= (st_data_t)(k1.b[i] ^ k2.b[SIZEOF_VALUE-1-i]) << (8 * i);
    }

    if (0) {
        fprintf(stderr, "SIZEOF_VALUE:%d\n", SIZEOF_VALUE);
        fprintf(stderr, "pc:%p def:%p\n", pc, (void *)cme->def);
        fprintf(stderr, "key:%p\n", (void *)key);
    }

    // duplication check
    if (st_insert(dup_check_table, key, 1)) {
        // already shown
    }
    else {
        VALUE m_loc = rb_method_entry_location((const rb_method_entry_t *)cme);
        VALUE name = rb_gen_method_name(cme->defined_class, ISEQ_BODY(iseq)->location.base_label);

        if (!NIL_P(m_loc)) {
            rb_warning("the block passed to '%"PRIsVALUE"' defined at %"PRIsVALUE":%"PRIsVALUE" may be ignored",
                       name, RARRAY_AREF(m_loc, 0), RARRAY_AREF(m_loc, 1));
        }
        else {
            rb_warning("the block may be ignored because '%"PRIsVALUE"' does not use a block", name);
        }
    }
}

static inline int
vm_callee_setup_arg(rb_execution_context_t *ec, struct rb_calling_info *calling,
                    const rb_iseq_t *iseq, VALUE *argv, int param_size, int local_size)
{
    const struct rb_callinfo *ci = calling->cd->ci;
    const struct rb_callcache *cc = calling->cc;

    if (UNLIKELY(!ISEQ_BODY(iseq)->param.flags.use_block &&
                 calling->block_handler != VM_BLOCK_HANDLER_NONE &&
                 !(vm_ci_flag(calling->cd->ci) & VM_CALL_SUPER))) {
        warn_unused_block(vm_cc_cme(cc), iseq, (void *)ec->cfp->pc);
    }

    if (LIKELY(!(vm_ci_flag(ci) & VM_CALL_KW_SPLAT))) {
        if (LIKELY(rb_simple_iseq_p(iseq))) {
            rb_control_frame_t *cfp = ec->cfp;
            int lead_num = ISEQ_BODY(iseq)->param.lead_num;
            CALLER_SETUP_ARG(cfp, calling, ci, lead_num);

            if (calling->argc != lead_num) {
                argument_arity_error(ec, iseq, calling->argc, lead_num, lead_num);
            }

            //VM_ASSERT(ci == calling->cd->ci);
            VM_ASSERT(cc == calling->cc);

            if (vm_call_iseq_optimizable_p(ci, cc)) {
                if ((iseq->body->builtin_attrs & BUILTIN_ATTR_SINGLE_NOARG_LEAF) &&
                    !(ruby_vm_event_flags & (RUBY_EVENT_C_CALL | RUBY_EVENT_C_RETURN))) {
                    VM_ASSERT(iseq->body->builtin_attrs & BUILTIN_ATTR_LEAF);
                    vm_cc_bf_set(cc, (void *)iseq->body->iseq_encoded[1]);
                    CC_SET_FASTPATH(cc, vm_call_single_noarg_leaf_builtin, true);
                }
                else {
                    CC_SET_FASTPATH(cc, vm_call_iseq_setup_func(ci, param_size, local_size), true);
                }
            }
            return 0;
        }
        else if (rb_iseq_only_optparam_p(iseq)) {
            rb_control_frame_t *cfp = ec->cfp;

            const int lead_num = ISEQ_BODY(iseq)->param.lead_num;
            const int opt_num = ISEQ_BODY(iseq)->param.opt_num;

            CALLER_SETUP_ARG(cfp, calling, ci, lead_num + opt_num);
            const int argc = calling->argc;
            const int opt = argc - lead_num;

            if (opt < 0 || opt > opt_num) {
                argument_arity_error(ec, iseq, argc, lead_num, lead_num + opt_num);
            }

            if (LIKELY(!(vm_ci_flag(ci) & VM_CALL_TAILCALL))) {
                CC_SET_FASTPATH(cc, vm_call_iseq_setup_normal_opt_start,
                                !IS_ARGS_SPLAT(ci) && !IS_ARGS_KEYWORD(ci) &&
                                vm_call_cacheable(ci, cc));
            }
            else {
                CC_SET_FASTPATH(cc, vm_call_iseq_setup_tailcall_opt_start,
                                !IS_ARGS_SPLAT(ci) && !IS_ARGS_KEYWORD(ci) &&
                                vm_call_cacheable(ci, cc));
            }

            /* initialize opt vars for self-references */
            VM_ASSERT((int)ISEQ_BODY(iseq)->param.size == lead_num + opt_num);
            for (int i=argc; i<lead_num + opt_num; i++) {
                argv[i] = Qnil;
            }
            return (int)ISEQ_BODY(iseq)->param.opt_table[opt];
        }
        else if (rb_iseq_only_kwparam_p(iseq) && !IS_ARGS_SPLAT(ci)) {
            const int lead_num = ISEQ_BODY(iseq)->param.lead_num;
            const int argc = calling->argc;
            const struct rb_iseq_param_keyword *kw_param = ISEQ_BODY(iseq)->param.keyword;

            if (vm_ci_flag(ci) & VM_CALL_KWARG) {
                const struct rb_callinfo_kwarg *kw_arg = vm_ci_kwarg(ci);

                if (argc - kw_arg->keyword_len == lead_num) {
                    const int ci_kw_len = kw_arg->keyword_len;
                    const VALUE * const ci_keywords = kw_arg->keywords;
                    VALUE * const ci_kws = ALLOCA_N(VALUE, ci_kw_len);
                    MEMCPY(ci_kws, argv + lead_num, VALUE, ci_kw_len);

                    VALUE *const klocals = argv + kw_param->bits_start - kw_param->num;
                    args_setup_kw_parameters(ec, iseq, ci_kws, ci_kw_len, ci_keywords, klocals);

                    CC_SET_FASTPATH(cc, vm_call_iseq_setup_kwparm_kwarg,
                                    vm_call_cacheable(ci, cc));

                    return 0;
                }
            }
            else if (argc == lead_num) {
                /* no kwarg */
                VALUE *const klocals = argv + kw_param->bits_start - kw_param->num;
                args_setup_kw_parameters(ec, iseq, NULL, 0, NULL, klocals);

                if (klocals[kw_param->num] == INT2FIX(0)) {
                    /* copy from default_values */
                    CC_SET_FASTPATH(cc, vm_call_iseq_setup_kwparm_nokwarg,
                                    vm_call_cacheable(ci, cc));
                }

                return 0;
            }
        }
    }

    // Called iseq is using ... param
    // def foo(...) # <- iseq for foo will have "forwardable"
    //
    // We want to set the `...` local to the caller's CI
    //   foo(1, 2) # <- the ci for this should end up as `...`
    //
    // So hopefully the stack looks like:
    //
    //   => 1
    //   => 2
    //   => *
    //   => **
    //   => &
    //   => ... # <- points at `foo`s CI
    //   => cref_or_me
    //   => specval
    //   => type
    //
    if (ISEQ_BODY(iseq)->param.flags.forwardable) {
        bool can_fastpath = true;

        if ((vm_ci_flag(ci) & VM_CALL_FORWARDING)) {
            struct rb_forwarding_call_data * forward_cd = (struct rb_forwarding_call_data *)calling->cd;
            if (vm_ci_argc(ci) != vm_ci_argc(forward_cd->caller_ci)) {
                ci = vm_ci_new_runtime(
                        vm_ci_mid(ci),
                        vm_ci_flag(ci),
                        vm_ci_argc(ci),
                        vm_ci_kwarg(ci));
            } else {
                ci = forward_cd->caller_ci;
            }
            can_fastpath = false;
        }
        // C functions calling iseqs will stack allocate a CI,
        // so we need to convert it to heap allocated
        if (!vm_ci_markable(ci)) {
            ci = vm_ci_new_runtime(
                    vm_ci_mid(ci),
                    vm_ci_flag(ci),
                    vm_ci_argc(ci),
                    vm_ci_kwarg(ci));
            can_fastpath = false;
        }
        argv[param_size - 1] = (VALUE)ci;
        CC_SET_FASTPATH(cc, vm_call_iseq_forwardable, can_fastpath);
        return 0;
    }

    return setup_parameters_complex(ec, iseq, calling, ci, argv, arg_setup_method);
}

static void
vm_adjust_stack_forwarding(const struct rb_execution_context_struct *ec, struct rb_control_frame_struct *cfp, CALL_INFO callers_info, VALUE splat)
{
    // This case is when the caller is using a ... parameter.
    // For example `bar(...)`. The call info will have VM_CALL_FORWARDING
    // In this case the caller's caller's CI will be on the stack.
    //
    // For example:
    //
    // def bar(a, b); a + b; end
    // def foo(...); bar(...); end
    // foo(1, 2) # <- this CI will be on the stack when we call `bar(...)`
    //
    // Stack layout will be:
    //
    // > 1
    // > 2
    // > CI for foo(1, 2)
    // > cref_or_me
    // > specval
    // > type
    // > receiver
    // > CI for foo(1, 2), via `getlocal ...`
    // >      ( SP points here )
    const VALUE * lep = VM_CF_LEP(cfp);

    // We'll need to copy argc args to this SP
    int argc = vm_ci_argc(callers_info);

    const rb_iseq_t *iseq;

    // If we're in an escaped environment (lambda for example), get the iseq
    // from the captured env.
    if (VM_ENV_FLAGS(lep, VM_ENV_FLAG_ESCAPED)) {
        rb_env_t * env = (rb_env_t *)lep[VM_ENV_DATA_INDEX_ENV];
        iseq = env->iseq;
    }
    else { // Otherwise use the lep to find the caller
        iseq = rb_vm_search_cf_from_ep(ec, cfp, lep)->iseq;
    }

    // Our local storage is below the args we need to copy
    int local_size = ISEQ_BODY(iseq)->local_table_size + argc;

    const VALUE * from = lep - (local_size + VM_ENV_DATA_SIZE - 1); // 2 for EP values
    VALUE * to = cfp->sp - 1; // clobber the CI

    if (RTEST(splat)) {
        to -= 1; // clobber the splat array
        CHECK_VM_STACK_OVERFLOW0(cfp, to, RARRAY_LEN(splat));
        MEMCPY(to, RARRAY_CONST_PTR(splat), VALUE, RARRAY_LEN(splat));
        to += RARRAY_LEN(splat);
    }

    CHECK_VM_STACK_OVERFLOW0(cfp, to, argc);
    MEMCPY(to, from, VALUE, argc);
    cfp->sp = to + argc;

    // Stack layout should now be:
    //
    // > 1
    // > 2
    // > CI for foo(1, 2)
    // > cref_or_me
    // > specval
    // > type
    // > receiver
    // > 1
    // > 2
    // >      ( SP points here )
}

static VALUE
vm_call_iseq_setup(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    RB_DEBUG_COUNTER_INC(ccf_iseq_setup);

    const struct rb_callcache *cc = calling->cc;
    const rb_iseq_t *iseq = def_iseq_ptr(vm_cc_cme(cc)->def);
    int param_size = ISEQ_BODY(iseq)->param.size;
    int local_size = ISEQ_BODY(iseq)->local_table_size;

    RUBY_ASSERT(!ISEQ_BODY(iseq)->param.flags.forwardable);

    const int opt_pc = vm_callee_setup_arg(ec, calling, iseq, cfp->sp - calling->argc, param_size, local_size);
    return vm_call_iseq_setup_2(ec, cfp, calling, opt_pc, param_size, local_size);
}

static VALUE
vm_call_iseq_fwd_setup(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    RB_DEBUG_COUNTER_INC(ccf_iseq_setup);

    const struct rb_callcache *cc = calling->cc;
    const rb_iseq_t *iseq = def_iseq_ptr(vm_cc_cme(cc)->def);
    int param_size = ISEQ_BODY(iseq)->param.size;
    int local_size = ISEQ_BODY(iseq)->local_table_size;

    RUBY_ASSERT(ISEQ_BODY(iseq)->param.flags.forwardable);

    // Setting up local size and param size
    local_size = local_size + vm_ci_argc(calling->cd->ci);
    param_size = param_size + vm_ci_argc(calling->cd->ci);

    const int opt_pc = vm_callee_setup_arg(ec, calling, iseq, cfp->sp - calling->argc, param_size, local_size);
    return vm_call_iseq_setup_2(ec, cfp, calling, opt_pc, param_size, local_size);
}

static inline VALUE
vm_call_iseq_setup_2(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling,
                     int opt_pc, int param_size, int local_size)
{
    const struct rb_callinfo *ci = calling->cd->ci;
    const struct rb_callcache *cc = calling->cc;

    if (LIKELY(!(vm_ci_flag(ci) & VM_CALL_TAILCALL))) {
        return vm_call_iseq_setup_normal(ec, cfp, calling, vm_cc_cme(cc), opt_pc, param_size, local_size);
    }
    else {
        return vm_call_iseq_setup_tailcall(ec, cfp, calling, opt_pc);
    }
}

static inline VALUE
vm_call_iseq_setup_normal(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling, const rb_callable_method_entry_t *me,
                          int opt_pc, int param_size, int local_size)
{
    const rb_iseq_t *iseq = def_iseq_ptr(me->def);
    VALUE *argv = cfp->sp - calling->argc;
    VALUE *sp = argv + param_size;
    cfp->sp = argv - 1 /* recv */;

    vm_push_frame(ec, iseq, VM_FRAME_MAGIC_METHOD | VM_ENV_FLAG_LOCAL, calling->recv,
                  calling->block_handler, (VALUE)me,
                  ISEQ_BODY(iseq)->iseq_encoded + opt_pc, sp,
                  local_size - param_size,
                  ISEQ_BODY(iseq)->stack_max);
    return Qundef;
}

static inline VALUE
vm_call_iseq_setup_tailcall(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling, int opt_pc)
{
    const struct rb_callcache *cc = calling->cc;
    unsigned int i;
    VALUE *argv = cfp->sp - calling->argc;
    const rb_callable_method_entry_t *me = vm_cc_cme(cc);
    const rb_iseq_t *iseq = def_iseq_ptr(me->def);
    VALUE *src_argv = argv;
    VALUE *sp_orig, *sp;
    VALUE finish_flag = VM_FRAME_FINISHED_P(cfp) ? VM_FRAME_FLAG_FINISH : 0;

    if (VM_BH_FROM_CFP_P(calling->block_handler, cfp)) {
        struct rb_captured_block *dst_captured = VM_CFP_TO_CAPTURED_BLOCK(RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp));
        const struct rb_captured_block *src_captured = VM_BH_TO_CAPT_BLOCK(calling->block_handler);
        dst_captured->code.val = src_captured->code.val;
        if (VM_BH_ISEQ_BLOCK_P(calling->block_handler)) {
            calling->block_handler = VM_BH_FROM_ISEQ_BLOCK(dst_captured);
        }
        else {
            calling->block_handler = VM_BH_FROM_IFUNC_BLOCK(dst_captured);
        }
    }

    vm_pop_frame(ec, cfp, cfp->ep);
    cfp = ec->cfp;

    sp_orig = sp = cfp->sp;

    /* push self */
    sp[0] = calling->recv;
    sp++;

    /* copy arguments */
    for (i=0; i < ISEQ_BODY(iseq)->param.size; i++) {
        *sp++ = src_argv[i];
    }

    vm_push_frame(ec, iseq, VM_FRAME_MAGIC_METHOD | VM_ENV_FLAG_LOCAL | finish_flag,
                  calling->recv, calling->block_handler, (VALUE)me,
                  ISEQ_BODY(iseq)->iseq_encoded + opt_pc, sp,
                  ISEQ_BODY(iseq)->local_table_size - ISEQ_BODY(iseq)->param.size,
                  ISEQ_BODY(iseq)->stack_max);

    cfp->sp = sp_orig;

    return Qundef;
}

static void
ractor_unsafe_check(void)
{
    if (!rb_ractor_main_p()) {
        rb_raise(rb_eRactorUnsafeError, "ractor unsafe method called from not main ractor");
    }
}

static VALUE
call_cfunc_m2(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    ractor_unsafe_check();
    VALUE(*f)(VALUE, VALUE) = (VALUE(*)(VALUE, VALUE))func;
    return (*f)(recv, rb_ary_new4(argc, argv));
}

static VALUE
call_cfunc_m1(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    ractor_unsafe_check();
    VALUE(*f)(int, const VALUE *, VALUE) = (VALUE(*)(int, const VALUE *, VALUE))func;
    return (*f)(argc, argv, recv);
}

static VALUE
call_cfunc_0(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    ractor_unsafe_check();
    VALUE(*f)(VALUE) = (VALUE(*)(VALUE))func;
    return (*f)(recv);
}

static VALUE
call_cfunc_1(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    ractor_unsafe_check();
    VALUE(*f)(VALUE, VALUE) = (VALUE(*)(VALUE, VALUE))func;
    return (*f)(recv, argv[0]);
}

static VALUE
call_cfunc_2(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    ractor_unsafe_check();
    VALUE(*f)(VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1]);
}

static VALUE
call_cfunc_3(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    ractor_unsafe_check();
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2]);
}

static VALUE
call_cfunc_4(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    ractor_unsafe_check();
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3]);
}

static VALUE
call_cfunc_5(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    ractor_unsafe_check();
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4]);
}

static VALUE
call_cfunc_6(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    ractor_unsafe_check();
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5]);
}

static VALUE
call_cfunc_7(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    ractor_unsafe_check();
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6]);
}

static VALUE
call_cfunc_8(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    ractor_unsafe_check();
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7]);
}

static VALUE
call_cfunc_9(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    ractor_unsafe_check();
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8]);
}

static VALUE
call_cfunc_10(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    ractor_unsafe_check();
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9]);
}

static VALUE
call_cfunc_11(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    ractor_unsafe_check();
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10]);
}

static VALUE
call_cfunc_12(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    ractor_unsafe_check();
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10], argv[11]);
}

static VALUE
call_cfunc_13(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    ractor_unsafe_check();
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10], argv[11], argv[12]);
}

static VALUE
call_cfunc_14(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    ractor_unsafe_check();
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10], argv[11], argv[12], argv[13]);
}

static VALUE
call_cfunc_15(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    ractor_unsafe_check();
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10], argv[11], argv[12], argv[13], argv[14]);
}

static VALUE
ractor_safe_call_cfunc_m2(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    VALUE(*f)(VALUE, VALUE) = (VALUE(*)(VALUE, VALUE))func;
    return (*f)(recv, rb_ary_new4(argc, argv));
}

static VALUE
ractor_safe_call_cfunc_m1(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    VALUE(*f)(int, const VALUE *, VALUE) = (VALUE(*)(int, const VALUE *, VALUE))func;
    return (*f)(argc, argv, recv);
}

static VALUE
ractor_safe_call_cfunc_0(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    VALUE(*f)(VALUE) = (VALUE(*)(VALUE))func;
    return (*f)(recv);
}

static VALUE
ractor_safe_call_cfunc_1(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    VALUE(*f)(VALUE, VALUE) = (VALUE(*)(VALUE, VALUE))func;
    return (*f)(recv, argv[0]);
}

static VALUE
ractor_safe_call_cfunc_2(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    VALUE(*f)(VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1]);
}

static VALUE
ractor_safe_call_cfunc_3(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2]);
}

static VALUE
ractor_safe_call_cfunc_4(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3]);
}

static VALUE
ractor_safe_call_cfunc_5(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4]);
}

static VALUE
ractor_safe_call_cfunc_6(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5]);
}

static VALUE
ractor_safe_call_cfunc_7(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6]);
}

static VALUE
ractor_safe_call_cfunc_8(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7]);
}

static VALUE
ractor_safe_call_cfunc_9(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8]);
}

static VALUE
ractor_safe_call_cfunc_10(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9]);
}

static VALUE
ractor_safe_call_cfunc_11(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10]);
}

static VALUE
ractor_safe_call_cfunc_12(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10], argv[11]);
}

static VALUE
ractor_safe_call_cfunc_13(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10], argv[11], argv[12]);
}

static VALUE
ractor_safe_call_cfunc_14(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10], argv[11], argv[12], argv[13]);
}

static VALUE
ractor_safe_call_cfunc_15(VALUE recv, int argc, const VALUE *argv, VALUE (*func)(ANYARGS))
{
    VALUE(*f)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE) = (VALUE(*)(VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE, VALUE))func;
    return (*f)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10], argv[11], argv[12], argv[13], argv[14]);
}

static inline int
vm_cfp_consistent_p(rb_execution_context_t *ec, const rb_control_frame_t *reg_cfp)
{
    const int ov_flags = RAISED_STACKOVERFLOW;
    if (LIKELY(reg_cfp == ec->cfp + 1)) return TRUE;
    if (rb_ec_raised_p(ec, ov_flags)) {
        rb_ec_raised_reset(ec, ov_flags);
        return TRUE;
    }
    return FALSE;
}

#define CHECK_CFP_CONSISTENCY(func) \
    (LIKELY(vm_cfp_consistent_p(ec, reg_cfp)) ? (void)0 : \
     rb_bug(func ": cfp consistency error (%p, %p)", (void *)reg_cfp, (void *)(ec->cfp+1)))

static inline
const rb_method_cfunc_t *
vm_method_cfunc_entry(const rb_callable_method_entry_t *me)
{
#if VM_DEBUG_VERIFY_METHOD_CACHE
    switch (me->def->type) {
      case VM_METHOD_TYPE_CFUNC:
      case VM_METHOD_TYPE_NOTIMPLEMENTED:
        break;
# define METHOD_BUG(t) case VM_METHOD_TYPE_##t: rb_bug("wrong method type: " #t)
        METHOD_BUG(ISEQ);
        METHOD_BUG(ATTRSET);
        METHOD_BUG(IVAR);
        METHOD_BUG(BMETHOD);
        METHOD_BUG(ZSUPER);
        METHOD_BUG(UNDEF);
        METHOD_BUG(OPTIMIZED);
        METHOD_BUG(MISSING);
        METHOD_BUG(REFINED);
        METHOD_BUG(ALIAS);
# undef METHOD_BUG
      default:
        rb_bug("wrong method type: %d", me->def->type);
    }
#endif
    return UNALIGNED_MEMBER_PTR(me->def, body.cfunc);
}

static inline VALUE
vm_call_cfunc_with_frame_(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling,
                          int argc, VALUE *argv, VALUE *stack_bottom)
{
    RB_DEBUG_COUNTER_INC(ccf_cfunc_with_frame);
    const struct rb_callinfo *ci = calling->cd->ci;
    const struct rb_callcache *cc = calling->cc;
    VALUE val;
    const rb_callable_method_entry_t *me = vm_cc_cme(cc);
    const rb_method_cfunc_t *cfunc = vm_method_cfunc_entry(me);

    VALUE recv = calling->recv;
    VALUE block_handler = calling->block_handler;
    VALUE frame_type = VM_FRAME_MAGIC_CFUNC | VM_FRAME_FLAG_CFRAME | VM_ENV_FLAG_LOCAL;

    if (UNLIKELY(calling->kw_splat)) {
        frame_type |= VM_FRAME_FLAG_CFRAME_KW;
    }

    VM_ASSERT(reg_cfp == ec->cfp);

    RUBY_DTRACE_CMETHOD_ENTRY_HOOK(ec, me->owner, me->def->original_id);
    EXEC_EVENT_HOOK(ec, RUBY_EVENT_C_CALL, recv, me->def->original_id, vm_ci_mid(ci), me->owner, Qundef);

    vm_push_frame(ec, NULL, frame_type, recv,
                  block_handler, (VALUE)me,
                  0, ec->cfp->sp, 0, 0);

    int len = cfunc->argc;
    if (len >= 0) rb_check_arity(argc, len, len);

    reg_cfp->sp = stack_bottom;
    val = (*cfunc->invoker)(recv, argc, argv, cfunc->func);

    CHECK_CFP_CONSISTENCY("vm_call_cfunc");

    rb_vm_pop_frame(ec);

    VM_ASSERT(ec->cfp->sp == stack_bottom);

    EXEC_EVENT_HOOK(ec, RUBY_EVENT_C_RETURN, recv, me->def->original_id, vm_ci_mid(ci), me->owner, val);
    RUBY_DTRACE_CMETHOD_RETURN_HOOK(ec, me->owner, me->def->original_id);

    return val;
}

// Push a C method frame for a given cme. This is called when JIT code skipped
// pushing a frame but the C method reached a point where a frame is needed.
void
rb_vm_push_cfunc_frame(const rb_callable_method_entry_t *cme, int recv_idx)
{
    VM_ASSERT(cme->def->type == VM_METHOD_TYPE_CFUNC);
    rb_execution_context_t *ec = GET_EC();
    VALUE *sp = ec->cfp->sp;
    VALUE recv = *(sp - recv_idx - 1);
    VALUE frame_type = VM_FRAME_MAGIC_CFUNC | VM_FRAME_FLAG_CFRAME | VM_ENV_FLAG_LOCAL;
    VALUE block_handler = VM_BLOCK_HANDLER_NONE;
#if VM_CHECK_MODE > 0
    // Clean up the stack canary since we're about to satisfy the "leaf or lazy push" assumption
    *(GET_EC()->cfp->sp) = Qfalse;
#endif
    vm_push_frame(ec, NULL, frame_type, recv, block_handler, (VALUE)cme, 0, ec->cfp->sp, 0, 0);
}

// If true, cc->call needs to include `CALLER_SETUP_ARG` (i.e. can't be skipped in fastpath)
bool
rb_splat_or_kwargs_p(const struct rb_callinfo *restrict ci)
{
    return IS_ARGS_SPLAT(ci) || IS_ARGS_KW_OR_KW_SPLAT(ci);
}

static VALUE
vm_call_cfunc_with_frame(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling)
{
    int argc = calling->argc;
    VALUE *stack_bottom = reg_cfp->sp - argc - 1;
    VALUE *argv = &stack_bottom[1];

    return vm_call_cfunc_with_frame_(ec, reg_cfp, calling, argc, argv, stack_bottom);
}

static VALUE
vm_call_cfunc_other(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling)
{
    const struct rb_callinfo *ci = calling->cd->ci;
    RB_DEBUG_COUNTER_INC(ccf_cfunc_other);

    CALLER_SETUP_ARG(reg_cfp, calling, ci, ALLOW_HEAP_ARGV_KEEP_KWSPLAT);
    VALUE argv_ary;
    if (UNLIKELY(argv_ary = calling->heap_argv)) {
        VM_ASSERT(!IS_ARGS_KEYWORD(ci));
        int argc = RARRAY_LENINT(argv_ary);
        VALUE *argv = (VALUE *)RARRAY_CONST_PTR(argv_ary);
        VALUE *stack_bottom = reg_cfp->sp - 2;

        VM_ASSERT(calling->argc == 1);
        VM_ASSERT(RB_TYPE_P(argv_ary, T_ARRAY));
        VM_ASSERT(RBASIC_CLASS(argv_ary) == 0); // hidden ary

        return vm_call_cfunc_with_frame_(ec, reg_cfp, calling, argc, argv, stack_bottom);
    }
    else {
        CC_SET_FASTPATH(calling->cc, vm_call_cfunc_with_frame, !rb_splat_or_kwargs_p(ci) && !calling->kw_splat && !(vm_ci_flag(ci) & VM_CALL_FORWARDING));

        return vm_call_cfunc_with_frame(ec, reg_cfp, calling);
    }
}

static inline VALUE
vm_call_cfunc_array_argv(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling, int stack_offset, int argc_offset)
{
    VALUE argv_ary = reg_cfp->sp[-1 - stack_offset];
    int argc = RARRAY_LENINT(argv_ary) - argc_offset;

    if (UNLIKELY(argc > VM_ARGC_STACK_MAX)) {
        return vm_call_cfunc_other(ec, reg_cfp, calling);
    }

    VALUE *argv = (VALUE *)RARRAY_CONST_PTR(argv_ary);
    calling->kw_splat = 0;
    int i;
    VALUE *stack_bottom = reg_cfp->sp - 2 - stack_offset;
    VALUE *sp = stack_bottom;
    CHECK_VM_STACK_OVERFLOW(reg_cfp, argc);
    for(i = 0; i < argc; i++) {
        *++sp = argv[i];
    }
    reg_cfp->sp = sp+1;

    return vm_call_cfunc_with_frame_(ec, reg_cfp, calling, argc, stack_bottom+1, stack_bottom);
}

static inline VALUE
vm_call_cfunc_only_splat(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling)
{
    RB_DEBUG_COUNTER_INC(ccf_cfunc_only_splat);
    VALUE argv_ary = reg_cfp->sp[-1];
    int argc = RARRAY_LENINT(argv_ary);
    VALUE *argv = (VALUE *)RARRAY_CONST_PTR(argv_ary);
    VALUE last_hash;
    int argc_offset = 0;

    if (UNLIKELY(argc > 0 &&
        RB_TYPE_P((last_hash = argv[argc-1]), T_HASH) &&
        (((struct RHash *)last_hash)->basic.flags & RHASH_PASS_AS_KEYWORDS))) {
        if (!RHASH_EMPTY_P(last_hash)) {
            return vm_call_cfunc_other(ec, reg_cfp, calling);
        }
        argc_offset++;
    }
    return vm_call_cfunc_array_argv(ec, reg_cfp, calling, 0, argc_offset);
}

static inline VALUE
vm_call_cfunc_only_splat_kw(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling)
{
    RB_DEBUG_COUNTER_INC(ccf_cfunc_only_splat_kw);
    VALUE keyword_hash = reg_cfp->sp[-1];

    if (keyword_hash == Qnil || (RB_TYPE_P(keyword_hash, T_HASH) && RHASH_EMPTY_P(keyword_hash))) {
        return vm_call_cfunc_array_argv(ec, reg_cfp, calling, 1, 0);
    }

    return vm_call_cfunc_other(ec, reg_cfp, calling);
}

static VALUE
vm_call_cfunc(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling)
{
    const struct rb_callinfo *ci = calling->cd->ci;
    RB_DEBUG_COUNTER_INC(ccf_cfunc);

    if (IS_ARGS_SPLAT(ci)) {
        if (!IS_ARGS_KW_SPLAT(ci) && vm_ci_argc(ci) == 1) {
            // f(*a)
            CC_SET_FASTPATH(calling->cc, vm_call_cfunc_only_splat, TRUE);
            return vm_call_cfunc_only_splat(ec, reg_cfp, calling);
        }
        if (IS_ARGS_KW_SPLAT(ci) && vm_ci_argc(ci) == 2) {
            // f(*a, **kw)
            CC_SET_FASTPATH(calling->cc, vm_call_cfunc_only_splat_kw, TRUE);
            return vm_call_cfunc_only_splat_kw(ec, reg_cfp, calling);
        }
    }

    CC_SET_FASTPATH(calling->cc, vm_call_cfunc_other, TRUE);
    return vm_call_cfunc_other(ec, reg_cfp, calling);
}

static VALUE
vm_call_ivar(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    const struct rb_callcache *cc = calling->cc;
    RB_DEBUG_COUNTER_INC(ccf_ivar);
    cfp->sp -= 1;
    VALUE ivar = vm_getivar(calling->recv, vm_cc_cme(cc)->def->body.attr.id, NULL, NULL, cc, TRUE, Qnil);
    return ivar;
}

static VALUE
vm_call_attrset_direct(rb_execution_context_t *ec, rb_control_frame_t *cfp, const struct rb_callcache *cc, VALUE obj)
{
    RB_DEBUG_COUNTER_INC(ccf_attrset);
    VALUE val = *(cfp->sp - 1);
    cfp->sp -= 2;
    attr_index_t index = vm_cc_attr_index(cc);
    shape_id_t dest_shape_id = vm_cc_attr_index_dest_shape_id(cc);
    ID id = vm_cc_cme(cc)->def->body.attr.id;
    rb_check_frozen(obj);
    VALUE res = vm_setivar(obj, id, val, dest_shape_id, index);
    if (UNDEF_P(res)) {
        switch (BUILTIN_TYPE(obj)) {
          case T_OBJECT:
          case T_CLASS:
          case T_MODULE:
            break;
          default:
            {
                res = vm_setivar_default(obj, id, val, dest_shape_id, index);
                if (!UNDEF_P(res)) {
                    return res;
                }
            }
        }
        res = vm_setivar_slowpath_attr(obj, id, val, cc);
    }
    return res;
}

static VALUE
vm_call_attrset(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    return vm_call_attrset_direct(ec, cfp, calling->cc, calling->recv);
}

static inline VALUE
vm_call_bmethod_body(rb_execution_context_t *ec, struct rb_calling_info *calling, const VALUE *argv)
{
    rb_proc_t *proc;
    VALUE val;
    const struct rb_callcache *cc = calling->cc;
    const rb_callable_method_entry_t *cme = vm_cc_cme(cc);
    VALUE procv = cme->def->body.bmethod.proc;

    if (!RB_OBJ_SHAREABLE_P(procv) &&
        cme->def->body.bmethod.defined_ractor != rb_ractor_self(rb_ec_ractor_ptr(ec))) {
        rb_raise(rb_eRuntimeError, "defined with an un-shareable Proc in a different Ractor");
    }

    /* control block frame */
    GetProcPtr(procv, proc);
    val = rb_vm_invoke_bmethod(ec, proc, calling->recv, CALLING_ARGC(calling), argv, calling->kw_splat, calling->block_handler, vm_cc_cme(cc));

    return val;
}

static int vm_callee_setup_block_arg(rb_execution_context_t *ec, struct rb_calling_info *calling, const struct rb_callinfo *ci, const rb_iseq_t *iseq, VALUE *argv, const enum arg_setup_type arg_setup_type);
static VALUE invoke_bmethod(rb_execution_context_t *ec, const rb_iseq_t *iseq, VALUE self, const struct rb_captured_block *captured, const rb_callable_method_entry_t *me, VALUE type, int opt_pc);

static VALUE
vm_call_iseq_bmethod(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    RB_DEBUG_COUNTER_INC(ccf_iseq_bmethod);

    const struct rb_callcache *cc = calling->cc;
    const rb_callable_method_entry_t *cme = vm_cc_cme(cc);
    VALUE procv = cme->def->body.bmethod.proc;

    if (!RB_OBJ_SHAREABLE_P(procv) &&
        cme->def->body.bmethod.defined_ractor != rb_ractor_self(rb_ec_ractor_ptr(ec))) {
        rb_raise(rb_eRuntimeError, "defined with an un-shareable Proc in a different Ractor");
    }

    rb_proc_t *proc;
    GetProcPtr(procv, proc);
    const struct rb_block *block = &proc->block;

    while (vm_block_type(block) == block_type_proc) {
        block = vm_proc_block(block->as.proc);
    }
    VM_ASSERT(vm_block_type(block) == block_type_iseq);

    const struct rb_captured_block *captured = &block->as.captured;
    const rb_iseq_t *iseq = rb_iseq_check(captured->code.iseq);
    VALUE * const argv = cfp->sp - calling->argc;
    const int arg_size = ISEQ_BODY(iseq)->param.size;

    int opt_pc;
    if (vm_ci_flag(calling->cd->ci) & VM_CALL_ARGS_SIMPLE) {
        opt_pc = vm_callee_setup_block_arg(ec, calling, calling->cd->ci, iseq, argv, arg_setup_method);
    }
    else {
        opt_pc = setup_parameters_complex(ec, iseq, calling, calling->cd->ci, argv, arg_setup_method);
    }

    cfp->sp = argv - 1; // -1 for the receiver

    vm_push_frame(ec, iseq,
                  VM_FRAME_MAGIC_BLOCK | VM_FRAME_FLAG_BMETHOD | VM_FRAME_FLAG_LAMBDA,
                  calling->recv,
                  VM_GUARDED_PREV_EP(captured->ep),
                  (VALUE)cme,
                  ISEQ_BODY(iseq)->iseq_encoded + opt_pc,
                  argv + arg_size,
                  ISEQ_BODY(iseq)->local_table_size - arg_size,
                  ISEQ_BODY(iseq)->stack_max);

    return Qundef;
}

static VALUE
vm_call_noniseq_bmethod(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    RB_DEBUG_COUNTER_INC(ccf_noniseq_bmethod);

    VALUE *argv;
    int argc;
    CALLER_SETUP_ARG(cfp, calling, calling->cd->ci, ALLOW_HEAP_ARGV);
    if (UNLIKELY(calling->heap_argv)) {
        argv = RARRAY_PTR(calling->heap_argv);
        cfp->sp -= 2;
    }
    else {
        argc = calling->argc;
        argv = ALLOCA_N(VALUE, argc);
        MEMCPY(argv, cfp->sp - argc, VALUE, argc);
        cfp->sp += - argc - 1;
    }

    return vm_call_bmethod_body(ec, calling, argv);
}

static VALUE
vm_call_bmethod(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    RB_DEBUG_COUNTER_INC(ccf_bmethod);

    const struct rb_callcache *cc = calling->cc;
    const rb_callable_method_entry_t *cme = vm_cc_cme(cc);
    VALUE procv = cme->def->body.bmethod.proc;
    rb_proc_t *proc;
    GetProcPtr(procv, proc);
    const struct rb_block *block = &proc->block;

    while (vm_block_type(block) == block_type_proc) {
        block = vm_proc_block(block->as.proc);
    }
    if (vm_block_type(block) == block_type_iseq) {
        CC_SET_FASTPATH(cc, vm_call_iseq_bmethod, TRUE);
        return vm_call_iseq_bmethod(ec, cfp, calling);
    }

    CC_SET_FASTPATH(cc, vm_call_noniseq_bmethod, TRUE);
    return vm_call_noniseq_bmethod(ec, cfp, calling);
}

VALUE
rb_find_defined_class_by_owner(VALUE current_class, VALUE target_owner)
{
    VALUE klass = current_class;

    /* for prepended Module, then start from cover class */
    if (RB_TYPE_P(klass, T_ICLASS) && FL_TEST(klass, RICLASS_IS_ORIGIN) &&
            RB_TYPE_P(RBASIC_CLASS(klass), T_CLASS)) {
        klass = RBASIC_CLASS(klass);
    }

    while (RTEST(klass)) {
        VALUE owner = RB_TYPE_P(klass, T_ICLASS) ? RBASIC_CLASS(klass) : klass;
        if (owner == target_owner) {
            return klass;
        }
        klass = RCLASS_SUPER(klass);
    }

    return current_class; /* maybe module function */
}

static const rb_callable_method_entry_t *
aliased_callable_method_entry(const rb_callable_method_entry_t *me)
{
    const rb_method_entry_t *orig_me = me->def->body.alias.original_me;
    const rb_callable_method_entry_t *cme;

    if (orig_me->defined_class == 0) {
        VALUE defined_class = rb_find_defined_class_by_owner(me->defined_class, orig_me->owner);
        VM_ASSERT(RB_TYPE_P(orig_me->owner, T_MODULE));
        cme = rb_method_entry_complement_defined_class(orig_me, me->called_id, defined_class);

        if (me->def->reference_count == 1) {
            RB_OBJ_WRITE(me, &me->def->body.alias.original_me, cme);
        }
        else {
            rb_method_definition_t *def =
                rb_method_definition_create(VM_METHOD_TYPE_ALIAS, me->def->original_id);
            rb_method_definition_set((rb_method_entry_t *)me, def, (void *)cme);
        }
    }
    else {
        cme = (const rb_callable_method_entry_t *)orig_me;
    }

    VM_ASSERT(callable_method_entry_p(cme));
    return cme;
}

const rb_callable_method_entry_t *
rb_aliased_callable_method_entry(const rb_callable_method_entry_t *me)
{
    return aliased_callable_method_entry(me);
}

static VALUE
vm_call_alias(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    calling->cc = &VM_CC_ON_STACK(Qundef,
                                  vm_call_general,
                                  {{0}},
                                  aliased_callable_method_entry(vm_cc_cme(calling->cc)));

    return vm_call_method_each_type(ec, cfp, calling);
}

static enum method_missing_reason
ci_missing_reason(const struct rb_callinfo *ci)
{
    enum method_missing_reason stat = MISSING_NOENTRY;
    if (vm_ci_flag(ci) & VM_CALL_VCALL) stat |= MISSING_VCALL;
    if (vm_ci_flag(ci) & VM_CALL_FCALL) stat |= MISSING_FCALL;
    if (vm_ci_flag(ci) & VM_CALL_SUPER) stat |= MISSING_SUPER;
    return stat;
}

static VALUE vm_call_method_missing(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling);

static VALUE
vm_call_symbol(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp,
               struct rb_calling_info *calling, const struct rb_callinfo *ci, VALUE symbol, int flags)
{
    ASSUME(calling->argc >= 0);

    enum method_missing_reason missing_reason = MISSING_NOENTRY;
    int argc = calling->argc;
    VALUE recv = calling->recv;
    VALUE klass = CLASS_OF(recv);
    ID mid = rb_check_id(&symbol);
    flags |= VM_CALL_OPT_SEND;

    if (UNLIKELY(! mid)) {
        mid = idMethodMissing;
        missing_reason = ci_missing_reason(ci);
        ec->method_missing_reason = missing_reason;

        VALUE argv_ary;
        if (UNLIKELY(argv_ary = calling->heap_argv)) {
            if (rb_method_basic_definition_p(klass, idMethodMissing)) {
                rb_ary_unshift(argv_ary, symbol);

                /* Inadvertent symbol creation shall be forbidden, see [Feature #5112] */
                int priv = vm_ci_flag(ci) & (VM_CALL_FCALL | VM_CALL_VCALL);
                VALUE exc = rb_make_no_method_exception(
                    rb_eNoMethodError, 0, recv, RARRAY_LENINT(argv_ary), RARRAY_CONST_PTR(argv_ary), priv);

                rb_exc_raise(exc);
            }
            rb_ary_unshift(argv_ary, rb_str_intern(symbol));
        }
        else {
            /* E.g. when argc == 2
             *
             *   |      |        |      |  TOPN
             *   |      |        +------+
             *   |      |  +---> | arg1 |    0
             *   +------+  |     +------+
             *   | arg1 | -+ +-> | arg0 |    1
             *   +------+    |   +------+
             *   | arg0 | ---+   | sym  |    2
             *   +------+        +------+
             *   | recv |        | recv |    3
             * --+------+--------+------+------
             */
            int i = argc;
            CHECK_VM_STACK_OVERFLOW(reg_cfp, 1);
            INC_SP(1);
            MEMMOVE(&TOPN(i - 1), &TOPN(i), VALUE, i);
            argc = ++calling->argc;

            if (rb_method_basic_definition_p(klass, idMethodMissing)) {
                /* Inadvertent symbol creation shall be forbidden, see [Feature #5112] */
                TOPN(i) = symbol;
                int priv = vm_ci_flag(ci) & (VM_CALL_FCALL | VM_CALL_VCALL);
                const VALUE *argv = STACK_ADDR_FROM_TOP(argc);
                VALUE exc = rb_make_no_method_exception(
                    rb_eNoMethodError, 0, recv, argc, argv, priv);

                rb_exc_raise(exc);
            }
            else {
                TOPN(i) = rb_str_intern(symbol);
            }
        }
    }

    calling->cd = &(struct rb_call_data) {
        .ci = &VM_CI_ON_STACK(mid, flags, argc, vm_ci_kwarg(ci)),
        .cc = NULL,
    };
    calling->cc = &VM_CC_ON_STACK(klass,
                                  vm_call_general,
                                  { .method_missing_reason = missing_reason },
                                  rb_callable_method_entry_with_refinements(klass, mid, NULL));

    if (flags & VM_CALL_FCALL) {
        return vm_call_method(ec, reg_cfp, calling);
    }

    const struct rb_callcache *cc = calling->cc;
    VM_ASSERT(callable_method_entry_p(vm_cc_cme(cc)));

    if (vm_cc_cme(cc) != NULL) {
        switch (METHOD_ENTRY_VISI(vm_cc_cme(cc))) {
          case METHOD_VISI_PUBLIC: /* likely */
            return vm_call_method_each_type(ec, reg_cfp, calling);
          case METHOD_VISI_PRIVATE:
            vm_cc_method_missing_reason_set(cc, MISSING_PRIVATE);
            break;
          case METHOD_VISI_PROTECTED:
            vm_cc_method_missing_reason_set(cc, MISSING_PROTECTED);
            break;
          default:
            VM_UNREACHABLE(vm_call_method);
        }
        return vm_call_method_missing(ec, reg_cfp, calling);
    }

    return vm_call_method_nome(ec, reg_cfp, calling);
}

static VALUE
vm_call_opt_send0(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling, int flags)
{
    const struct rb_callinfo *ci = calling->cd->ci;
    int i;
    VALUE sym;

    i = calling->argc - 1;

    if (calling->argc == 0) {
        rb_raise(rb_eArgError, "no method name given");
    }

    sym = TOPN(i);
    /* E.g. when i == 2
     *
     *   |      |        |      |  TOPN
     *   +------+        |      |
     *   | arg1 | ---+   |      |    0
     *   +------+    |   +------+
     *   | arg0 | -+ +-> | arg1 |    1
     *   +------+  |     +------+
     *   | sym  |  +---> | arg0 |    2
     *   +------+        +------+
     *   | recv |        | recv |    3
     * --+------+--------+------+------
     */
    /* shift arguments */
    if (i > 0) {
        MEMMOVE(&TOPN(i), &TOPN(i-1), VALUE, i);
    }
    calling->argc -= 1;
    DEC_SP(1);

    return vm_call_symbol(ec, reg_cfp, calling, ci, sym, flags);
}

static VALUE
vm_call_opt_send_complex(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling)
{
    RB_DEBUG_COUNTER_INC(ccf_opt_send_complex);
    const struct rb_callinfo *ci = calling->cd->ci;
    int flags = VM_CALL_FCALL;
    VALUE sym;

    VALUE argv_ary;
    CALLER_SETUP_ARG(reg_cfp, calling, ci, ALLOW_HEAP_ARGV);
    if (UNLIKELY(argv_ary = calling->heap_argv)) {
        sym = rb_ary_shift(argv_ary);
        flags |= VM_CALL_ARGS_SPLAT;
        if (calling->kw_splat) {
            VALUE last_hash = rb_ary_last(0, NULL, argv_ary);
            ((struct RHash *)last_hash)->basic.flags |= RHASH_PASS_AS_KEYWORDS;
            calling->kw_splat = 0;
        }
        return vm_call_symbol(ec, reg_cfp, calling, ci, sym, flags);
    }

    if (calling->kw_splat) flags |= VM_CALL_KW_SPLAT;
    return vm_call_opt_send0(ec, reg_cfp, calling, flags);
}

static VALUE
vm_call_opt_send_simple(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling)
{
    RB_DEBUG_COUNTER_INC(ccf_opt_send_simple);
    return vm_call_opt_send0(ec, reg_cfp, calling, vm_ci_flag(calling->cd->ci) | VM_CALL_FCALL);
}

static VALUE
vm_call_opt_send(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling)
{
    RB_DEBUG_COUNTER_INC(ccf_opt_send);

    const struct rb_callinfo *ci = calling->cd->ci;
    int flags = vm_ci_flag(ci);

    if (UNLIKELY(!(flags & VM_CALL_ARGS_SIMPLE) &&
        ((calling->argc == 1 && (flags & (VM_CALL_ARGS_SPLAT | VM_CALL_KW_SPLAT))) ||
         (calling->argc == 2 && (flags & VM_CALL_ARGS_SPLAT) && (flags & VM_CALL_KW_SPLAT)) ||
         ((flags & VM_CALL_KWARG) && (vm_ci_kwarg(ci)->keyword_len == calling->argc))))) {
        CC_SET_FASTPATH(calling->cc, vm_call_opt_send_complex, TRUE);
        return vm_call_opt_send_complex(ec, reg_cfp, calling);
    }

    CC_SET_FASTPATH(calling->cc, vm_call_opt_send_simple, TRUE);
    return vm_call_opt_send_simple(ec, reg_cfp, calling);
}

static VALUE
vm_call_method_missing_body(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling,
                            const struct rb_callinfo *orig_ci, enum method_missing_reason reason)
{
    RB_DEBUG_COUNTER_INC(ccf_method_missing);

    VALUE *argv = STACK_ADDR_FROM_TOP(calling->argc);
    unsigned int argc, flag;

    flag = VM_CALL_FCALL | VM_CALL_OPT_SEND | vm_ci_flag(orig_ci);
    argc = ++calling->argc;

    /* shift arguments: m(a, b, c) #=> method_missing(:m, a, b, c) */
    CHECK_VM_STACK_OVERFLOW(reg_cfp, 1);
    vm_check_canary(ec, reg_cfp->sp);
    if (argc > 1) {
        MEMMOVE(argv+1, argv, VALUE, argc-1);
    }
    argv[0] = ID2SYM(vm_ci_mid(orig_ci));
    INC_SP(1);

    ec->method_missing_reason = reason;
    calling->cd = &(struct rb_call_data) {
        .ci = &VM_CI_ON_STACK(idMethodMissing, flag, argc, vm_ci_kwarg(orig_ci)),
        .cc = NULL,
    };
    calling->cc = &VM_CC_ON_STACK(Qundef, vm_call_general, {{ 0 }},
                                  rb_callable_method_entry_without_refinements(CLASS_OF(calling->recv), idMethodMissing, NULL));
    return vm_call_method(ec, reg_cfp, calling);
}

static VALUE
vm_call_method_missing(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling)
{
    return vm_call_method_missing_body(ec, reg_cfp, calling, calling->cd->ci, vm_cc_cmethod_missing_reason(calling->cc));
}

static const rb_callable_method_entry_t *refined_method_callable_without_refinement(const rb_callable_method_entry_t *me);
static VALUE
vm_call_zsuper(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling, VALUE klass)
{
    klass = RCLASS_SUPER(klass);

    const rb_callable_method_entry_t *cme = klass ? rb_callable_method_entry(klass, vm_ci_mid(calling->cd->ci)) : NULL;
    if (cme == NULL) {
        return vm_call_method_nome(ec, cfp, calling);
    }
    if (cme->def->type == VM_METHOD_TYPE_REFINED &&
        cme->def->body.refined.orig_me) {
        cme = refined_method_callable_without_refinement(cme);
    }

    calling->cc = &VM_CC_ON_STACK(Qundef, vm_call_general, {{ 0 }}, cme);

    return vm_call_method_each_type(ec, cfp, calling);
}

static inline VALUE
find_refinement(VALUE refinements, VALUE klass)
{
    if (NIL_P(refinements)) {
        return Qnil;
    }
    return rb_hash_lookup(refinements, klass);
}

PUREFUNC(static rb_control_frame_t * current_method_entry(const rb_execution_context_t *ec, rb_control_frame_t *cfp));
static rb_control_frame_t *
current_method_entry(const rb_execution_context_t *ec, rb_control_frame_t *cfp)
{
    rb_control_frame_t *top_cfp = cfp;

    if (cfp->iseq && ISEQ_BODY(cfp->iseq)->type == ISEQ_TYPE_BLOCK) {
        const rb_iseq_t *local_iseq = ISEQ_BODY(cfp->iseq)->local_iseq;

        do {
            cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
            if (RUBY_VM_CONTROL_FRAME_STACK_OVERFLOW_P(ec, cfp)) {
                /* TODO: orphan block */
                return top_cfp;
            }
        } while (cfp->iseq != local_iseq);
    }
    return cfp;
}

static const rb_callable_method_entry_t *
refined_method_callable_without_refinement(const rb_callable_method_entry_t *me)
{
    const rb_method_entry_t *orig_me = me->def->body.refined.orig_me;
    const rb_callable_method_entry_t *cme;

    if (orig_me->defined_class == 0) {
        cme = NULL;
        rb_notimplement();
    }
    else {
        cme = (const rb_callable_method_entry_t *)orig_me;
    }

    VM_ASSERT(callable_method_entry_p(cme));

    if (UNDEFINED_METHOD_ENTRY_P(cme)) {
        cme = NULL;
    }

    return cme;
}

static const rb_callable_method_entry_t *
search_refined_method(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    ID mid = vm_ci_mid(calling->cd->ci);
    const rb_cref_t *cref = vm_get_cref(cfp->ep);
    const struct rb_callcache * const cc = calling->cc;
    const rb_callable_method_entry_t *cme = vm_cc_cme(cc);

    for (; cref; cref = CREF_NEXT(cref)) {
        const VALUE refinement = find_refinement(CREF_REFINEMENTS(cref), vm_cc_cme(cc)->owner);
        if (NIL_P(refinement)) continue;

        const rb_callable_method_entry_t *const ref_me =
            rb_callable_method_entry(refinement, mid);

        if (ref_me) {
            if (vm_cc_call(cc) == vm_call_super_method) {
                const rb_control_frame_t *top_cfp = current_method_entry(ec, cfp);
                const rb_callable_method_entry_t *top_me = rb_vm_frame_method_entry(top_cfp);
                if (top_me && rb_method_definition_eq(ref_me->def, top_me->def)) {
                    continue;
                }
            }

            if (cme->def->type != VM_METHOD_TYPE_REFINED ||
                cme->def != ref_me->def) {
                cme = ref_me;
            }
            if (ref_me->def->type != VM_METHOD_TYPE_REFINED) {
                return cme;
            }
        }
        else {
            return NULL;
        }
    }

    if (vm_cc_cme(cc)->def->body.refined.orig_me) {
        return refined_method_callable_without_refinement(vm_cc_cme(cc));
    }
    else {
        VALUE klass = RCLASS_SUPER(vm_cc_cme(cc)->defined_class);
        const rb_callable_method_entry_t *cme = klass ? rb_callable_method_entry(klass, mid) : NULL;
        return cme;
    }
}

static VALUE
vm_call_refined(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    const rb_callable_method_entry_t *ref_cme = search_refined_method(ec, cfp, calling);

    if (ref_cme) {
        if (calling->cd->cc) {
            const struct rb_callcache *cc = calling->cc = vm_cc_new(vm_cc_cme(calling->cc)->defined_class, ref_cme, vm_call_general, cc_type_refinement);
            RB_OBJ_WRITE(cfp->iseq, &calling->cd->cc, cc);
            return vm_call_method(ec, cfp, calling);
        }
        else {
            struct rb_callcache *ref_cc =  &VM_CC_ON_STACK(Qundef, vm_call_general, {{ 0 }}, ref_cme);
            calling->cc= ref_cc;
            return vm_call_method(ec, cfp, calling);
        }
    }
    else {
        return vm_call_method_nome(ec, cfp, calling);
    }
}

static inline VALUE vm_invoke_block(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling, const struct rb_callinfo *ci, bool is_lambda, VALUE block_handler);

NOINLINE(static VALUE
         vm_invoke_block_opt_call(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp,
                                  struct rb_calling_info *calling, const struct rb_callinfo *ci, VALUE block_handler));

static VALUE
vm_invoke_block_opt_call(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp,
                         struct rb_calling_info *calling, const struct rb_callinfo *ci, VALUE block_handler)
{
    int argc = calling->argc;

    /* remove self */
    if (argc > 0) MEMMOVE(&TOPN(argc), &TOPN(argc-1), VALUE, argc);
    DEC_SP(1);

    return vm_invoke_block(ec, reg_cfp, calling, ci, false, block_handler);
}

static VALUE
vm_call_opt_call(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling)
{
    RB_DEBUG_COUNTER_INC(ccf_opt_call);

    const struct rb_callinfo *ci = calling->cd->ci;
    VALUE procval = calling->recv;
    return vm_invoke_block_opt_call(ec, reg_cfp, calling, ci, VM_BH_FROM_PROC(procval));
}

static VALUE
vm_call_opt_block_call(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling)
{
    RB_DEBUG_COUNTER_INC(ccf_opt_block_call);

    VALUE block_handler = VM_ENV_BLOCK_HANDLER(VM_CF_LEP(reg_cfp));
    const struct rb_callinfo *ci = calling->cd->ci;

    if (BASIC_OP_UNREDEFINED_P(BOP_CALL, PROC_REDEFINED_OP_FLAG)) {
        return vm_invoke_block_opt_call(ec, reg_cfp, calling, ci, block_handler);
    }
    else {
        calling->recv = rb_vm_bh_to_procval(ec, block_handler);
        calling->cc = rb_vm_search_method_slowpath(ci, CLASS_OF(calling->recv));
        return vm_call_general(ec, reg_cfp, calling);
    }
}

static VALUE
vm_call_opt_struct_aref0(rb_execution_context_t *ec, struct rb_calling_info *calling)
{
    VALUE recv = calling->recv;

    VM_ASSERT(RB_TYPE_P(recv, T_STRUCT));
    VM_ASSERT(vm_cc_cme(calling->cc)->def->type == VM_METHOD_TYPE_OPTIMIZED);
    VM_ASSERT(vm_cc_cme(calling->cc)->def->body.optimized.type == OPTIMIZED_METHOD_TYPE_STRUCT_AREF);

    const unsigned int off = vm_cc_cme(calling->cc)->def->body.optimized.index;
    return internal_RSTRUCT_GET(recv, off);
}

static VALUE
vm_call_opt_struct_aref(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling)
{
    RB_DEBUG_COUNTER_INC(ccf_opt_struct_aref);

    VALUE ret = vm_call_opt_struct_aref0(ec, calling);
    reg_cfp->sp -= 1;
    return ret;
}

static VALUE
vm_call_opt_struct_aset0(rb_execution_context_t *ec, struct rb_calling_info *calling, VALUE val)
{
    VALUE recv = calling->recv;

    VM_ASSERT(RB_TYPE_P(recv, T_STRUCT));
    VM_ASSERT(vm_cc_cme(calling->cc)->def->type == VM_METHOD_TYPE_OPTIMIZED);
    VM_ASSERT(vm_cc_cme(calling->cc)->def->body.optimized.type == OPTIMIZED_METHOD_TYPE_STRUCT_ASET);

    rb_check_frozen(recv);

    const unsigned int off = vm_cc_cme(calling->cc)->def->body.optimized.index;
    internal_RSTRUCT_SET(recv, off, val);

    return val;
}

static VALUE
vm_call_opt_struct_aset(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling)
{
    RB_DEBUG_COUNTER_INC(ccf_opt_struct_aset);

    VALUE ret = vm_call_opt_struct_aset0(ec, calling, *(reg_cfp->sp - 1));
    reg_cfp->sp -= 2;
    return ret;
}

NOINLINE(static VALUE vm_call_optimized(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling,
                                        const struct rb_callinfo *ci, const struct rb_callcache *cc));

#define VM_CALL_METHOD_ATTR(var, func, nohook) \
    if (UNLIKELY(ruby_vm_event_flags & (RUBY_EVENT_C_CALL | RUBY_EVENT_C_RETURN))) { \
        EXEC_EVENT_HOOK(ec, RUBY_EVENT_C_CALL, calling->recv, vm_cc_cme(cc)->def->original_id, \
                        vm_ci_mid(ci), vm_cc_cme(cc)->owner, Qundef); \
        var = func; \
        EXEC_EVENT_HOOK(ec, RUBY_EVENT_C_RETURN, calling->recv, vm_cc_cme(cc)->def->original_id, \
                        vm_ci_mid(ci), vm_cc_cme(cc)->owner, (var)); \
    } \
    else { \
        nohook; \
        var = func; \
    }

static VALUE
vm_call_optimized(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling,
                  const struct rb_callinfo *ci, const struct rb_callcache *cc)
{
    switch (vm_cc_cme(cc)->def->body.optimized.type) {
      case OPTIMIZED_METHOD_TYPE_SEND:
        CC_SET_FASTPATH(cc, vm_call_opt_send, TRUE);
        return vm_call_opt_send(ec, cfp, calling);
      case OPTIMIZED_METHOD_TYPE_CALL:
        CC_SET_FASTPATH(cc, vm_call_opt_call, TRUE);
        return vm_call_opt_call(ec, cfp, calling);
      case OPTIMIZED_METHOD_TYPE_BLOCK_CALL:
        CC_SET_FASTPATH(cc, vm_call_opt_block_call, TRUE);
        return vm_call_opt_block_call(ec, cfp, calling);
      case OPTIMIZED_METHOD_TYPE_STRUCT_AREF: {
        CALLER_SETUP_ARG(cfp, calling, ci, 0);
        rb_check_arity(calling->argc, 0, 0);

        VALUE v;
        VM_CALL_METHOD_ATTR(v,
                            vm_call_opt_struct_aref(ec, cfp, calling),
                            set_vm_cc_ivar(cc); \
                            CC_SET_FASTPATH(cc, vm_call_opt_struct_aref, (vm_ci_flag(ci) & VM_CALL_ARGS_SIMPLE)))
        return v;
      }
      case OPTIMIZED_METHOD_TYPE_STRUCT_ASET: {
        CALLER_SETUP_ARG(cfp, calling, ci, 1);
        rb_check_arity(calling->argc, 1, 1);

        VALUE v;
        VM_CALL_METHOD_ATTR(v,
                            vm_call_opt_struct_aset(ec, cfp, calling),
                            set_vm_cc_ivar(cc); \
                            CC_SET_FASTPATH(cc, vm_call_opt_struct_aset, (vm_ci_flag(ci) & VM_CALL_ARGS_SIMPLE)))
        return v;
      }
      default:
        rb_bug("vm_call_method: unsupported optimized method type (%d)", vm_cc_cme(cc)->def->body.optimized.type);
    }
}

static VALUE
vm_call_method_each_type(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    const struct rb_callinfo *ci = calling->cd->ci;
    const struct rb_callcache *cc = calling->cc;
    const rb_callable_method_entry_t *cme = vm_cc_cme(cc);
    VALUE v;

    VM_ASSERT(! METHOD_ENTRY_INVALIDATED(cme));

    switch (cme->def->type) {
      case VM_METHOD_TYPE_ISEQ:
        if (ISEQ_BODY(def_iseq_ptr(cme->def))->param.flags.forwardable) {
            CC_SET_FASTPATH(cc, vm_call_iseq_fwd_setup, TRUE);
            return vm_call_iseq_fwd_setup(ec, cfp, calling);
        }
        else {
            CC_SET_FASTPATH(cc, vm_call_iseq_setup, TRUE);
            return vm_call_iseq_setup(ec, cfp, calling);
        }

      case VM_METHOD_TYPE_NOTIMPLEMENTED:
      case VM_METHOD_TYPE_CFUNC:
        CC_SET_FASTPATH(cc, vm_call_cfunc, TRUE);
        return vm_call_cfunc(ec, cfp, calling);

      case VM_METHOD_TYPE_ATTRSET:
        CALLER_SETUP_ARG(cfp, calling, ci, 1);

        rb_check_arity(calling->argc, 1, 1);

        const unsigned int aset_mask = (VM_CALL_ARGS_SPLAT | VM_CALL_KW_SPLAT | VM_CALL_KWARG | VM_CALL_FORWARDING);

        if (vm_cc_markable(cc)) {
            vm_cc_attr_index_initialize(cc, INVALID_SHAPE_ID);
            VM_CALL_METHOD_ATTR(v,
                                vm_call_attrset_direct(ec, cfp, cc, calling->recv),
                                CC_SET_FASTPATH(cc, vm_call_attrset, !(vm_ci_flag(ci) & aset_mask)));
        }
        else {
            cc = &((struct rb_callcache) {
                .flags = T_IMEMO |
                    (imemo_callcache << FL_USHIFT) |
                    VM_CALLCACHE_UNMARKABLE |
                    VM_CALLCACHE_ON_STACK,
                    .klass = cc->klass,
                    .cme_  = cc->cme_,
                    .call_ = cc->call_,
                    .aux_  = {
                        .attr = {
                            .value = INVALID_SHAPE_ID << SHAPE_FLAG_SHIFT,
                        }
                    },
            });

            VM_CALL_METHOD_ATTR(v,
                                vm_call_attrset_direct(ec, cfp, cc, calling->recv),
                                CC_SET_FASTPATH(cc, vm_call_attrset, !(vm_ci_flag(ci) & aset_mask)));
        }
        return v;

      case VM_METHOD_TYPE_IVAR:
        CALLER_SETUP_ARG(cfp, calling, ci, 0);
        rb_check_arity(calling->argc, 0, 0);
        vm_cc_attr_index_initialize(cc, INVALID_SHAPE_ID);
        const unsigned int ivar_mask = (VM_CALL_ARGS_SPLAT | VM_CALL_KW_SPLAT | VM_CALL_FORWARDING);
        VM_CALL_METHOD_ATTR(v,
                            vm_call_ivar(ec, cfp, calling),
                            CC_SET_FASTPATH(cc, vm_call_ivar, !(vm_ci_flag(ci) & ivar_mask)));
        return v;

      case VM_METHOD_TYPE_MISSING:
        vm_cc_method_missing_reason_set(cc, 0);
        CC_SET_FASTPATH(cc, vm_call_method_missing, TRUE);
        return vm_call_method_missing(ec, cfp, calling);

      case VM_METHOD_TYPE_BMETHOD:
        CC_SET_FASTPATH(cc, vm_call_bmethod, TRUE);
        return vm_call_bmethod(ec, cfp, calling);

      case VM_METHOD_TYPE_ALIAS:
        CC_SET_FASTPATH(cc, vm_call_alias, TRUE);
        return vm_call_alias(ec, cfp, calling);

      case VM_METHOD_TYPE_OPTIMIZED:
        return vm_call_optimized(ec, cfp, calling, ci, cc);

      case VM_METHOD_TYPE_UNDEF:
        break;

      case VM_METHOD_TYPE_ZSUPER:
        return vm_call_zsuper(ec, cfp, calling, RCLASS_ORIGIN(vm_cc_cme(cc)->defined_class));

      case VM_METHOD_TYPE_REFINED:
        // CC_SET_FASTPATH(cc, vm_call_refined, TRUE);
        // should not set FASTPATH since vm_call_refined assumes cc->call is vm_call_super_method on invokesuper.
        return vm_call_refined(ec, cfp, calling);
    }

    rb_bug("vm_call_method: unsupported method type (%d)", vm_cc_cme(cc)->def->type);
}

NORETURN(static void vm_raise_method_missing(rb_execution_context_t *ec, int argc, const VALUE *argv, VALUE obj, int call_status));

static VALUE
vm_call_method_nome(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    /* method missing */
    const struct rb_callinfo *ci = calling->cd->ci;
    const int stat = ci_missing_reason(ci);

    if (vm_ci_mid(ci) == idMethodMissing) {
        if (UNLIKELY(calling->heap_argv)) {
            vm_raise_method_missing(ec, RARRAY_LENINT(calling->heap_argv), RARRAY_CONST_PTR(calling->heap_argv), calling->recv, stat);
        }
        else {
            rb_control_frame_t *reg_cfp = cfp;
            VALUE *argv = STACK_ADDR_FROM_TOP(calling->argc);
            vm_raise_method_missing(ec, calling->argc, argv, calling->recv, stat);
        }
    }
    else {
        return vm_call_method_missing_body(ec, cfp, calling, ci, stat);
    }
}

/* Protected method calls and super invocations need to check that the receiver
 * (self for super) inherits the module on which the method is defined.
 * In the case of refinements, it should consider the original class not the
 * refinement.
 */
static VALUE
vm_defined_class_for_protected_call(const rb_callable_method_entry_t *me)
{
    VALUE defined_class = me->defined_class;
    VALUE refined_class = RCLASS_REFINED_CLASS(defined_class);
    return NIL_P(refined_class) ? defined_class : refined_class;
}

static inline VALUE
vm_call_method(rb_execution_context_t *ec, rb_control_frame_t *cfp, struct rb_calling_info *calling)
{
    const struct rb_callinfo *ci = calling->cd->ci;
    const struct rb_callcache *cc = calling->cc;

    VM_ASSERT(callable_method_entry_p(vm_cc_cme(cc)));

    if (vm_cc_cme(cc) != NULL) {
        switch (METHOD_ENTRY_VISI(vm_cc_cme(cc))) {
          case METHOD_VISI_PUBLIC: /* likely */
            return vm_call_method_each_type(ec, cfp, calling);

          case METHOD_VISI_PRIVATE:
            if (!(vm_ci_flag(ci) & VM_CALL_FCALL)) {
                enum method_missing_reason stat = MISSING_PRIVATE;
                if (vm_ci_flag(ci) & VM_CALL_VCALL) stat |= MISSING_VCALL;

                vm_cc_method_missing_reason_set(cc, stat);
                CC_SET_FASTPATH(cc, vm_call_method_missing, TRUE);
                return vm_call_method_missing(ec, cfp, calling);
            }
            return vm_call_method_each_type(ec, cfp, calling);

          case METHOD_VISI_PROTECTED:
            if (!(vm_ci_flag(ci) & (VM_CALL_OPT_SEND | VM_CALL_FCALL))) {
                VALUE defined_class = vm_defined_class_for_protected_call(vm_cc_cme(cc));
                if (!rb_obj_is_kind_of(cfp->self, defined_class)) {
                    vm_cc_method_missing_reason_set(cc, MISSING_PROTECTED);
                    return vm_call_method_missing(ec, cfp, calling);
                }
                else {
                    /* caching method info to dummy cc */
                    VM_ASSERT(vm_cc_cme(cc) != NULL);
                    struct rb_callcache cc_on_stack = *cc;
                    FL_SET_RAW((VALUE)&cc_on_stack, VM_CALLCACHE_UNMARKABLE);
                    calling->cc = &cc_on_stack;
                    return vm_call_method_each_type(ec, cfp, calling);
                }
            }
            return vm_call_method_each_type(ec, cfp, calling);

          default:
            rb_bug("unreachable");
        }
    }
    else {
        return vm_call_method_nome(ec, cfp, calling);
    }
}

static VALUE
vm_call_general(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling)
{
    RB_DEBUG_COUNTER_INC(ccf_general);
    return vm_call_method(ec, reg_cfp, calling);
}

void
rb_vm_cc_general(const struct rb_callcache *cc)
{
    VM_ASSERT(IMEMO_TYPE_P(cc, imemo_callcache));
    VM_ASSERT(cc != vm_cc_empty());

    *(vm_call_handler *)&cc->call_ = vm_call_general;
}

static VALUE
vm_call_super_method(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling)
{
    RB_DEBUG_COUNTER_INC(ccf_super_method);

    // This line is introduced to make different from `vm_call_general` because some compilers (VC we found)
    // can merge the function and the address of the function becomes same.
    // The address of `vm_call_super_method` is used in `search_refined_method`, so it should be different.
    if (ec == NULL) rb_bug("unreachable");

    /* this check is required to distinguish with other functions. */
    VM_ASSERT(vm_cc_call(calling->cc) == vm_call_super_method);
    return vm_call_method(ec, reg_cfp, calling);
}

/* super */

static inline VALUE
vm_search_normal_superclass(VALUE klass)
{
    if (BUILTIN_TYPE(klass) == T_ICLASS &&
            RB_TYPE_P(RBASIC(klass)->klass, T_MODULE) &&
        FL_TEST_RAW(RBASIC(klass)->klass, RMODULE_IS_REFINEMENT)) {
        klass = RBASIC(klass)->klass;
    }
    klass = RCLASS_ORIGIN(klass);
    return RCLASS_SUPER(klass);
}

NORETURN(static void vm_super_outside(void));

static void
vm_super_outside(void)
{
    rb_raise(rb_eNoMethodError, "super called outside of method");
}

static const struct rb_callcache *
empty_cc_for_super(void)
{
    return &vm_empty_cc_for_super;
}

static const struct rb_callcache *
vm_search_super_method(const rb_control_frame_t *reg_cfp, struct rb_call_data *cd, VALUE recv)
{
    VALUE current_defined_class;
    const rb_callable_method_entry_t *me = rb_vm_frame_method_entry(reg_cfp);

    if (!me) {
        vm_super_outside();
    }

    current_defined_class = vm_defined_class_for_protected_call(me);

    if (BUILTIN_TYPE(current_defined_class) != T_MODULE &&
        reg_cfp->iseq != method_entry_iseqptr(me) &&
        !rb_obj_is_kind_of(recv, current_defined_class)) {
        VALUE m = RB_TYPE_P(current_defined_class, T_ICLASS) ?
            RCLASS_INCLUDER(current_defined_class) : current_defined_class;

        if (m) { /* not bound UnboundMethod */
            rb_raise(rb_eTypeError,
                     "self has wrong type to call super in this context: "
                     "%"PRIsVALUE" (expected %"PRIsVALUE")",
                     rb_obj_class(recv), m);
        }
    }

    if (me->def->type == VM_METHOD_TYPE_BMETHOD && (vm_ci_flag(cd->ci) & VM_CALL_ZSUPER)) {
        rb_raise(rb_eRuntimeError,
                 "implicit argument passing of super from method defined"
                 " by define_method() is not supported."
                 " Specify all arguments explicitly.");
    }

    ID mid = me->def->original_id;

    if (!vm_ci_markable(cd->ci)) {
        VM_FORCE_WRITE((const VALUE *)&cd->ci->mid, (VALUE)mid);
    }
    else {
        // update iseq. really? (TODO)
        cd->ci = vm_ci_new_runtime(mid,
                                   vm_ci_flag(cd->ci),
                                   vm_ci_argc(cd->ci),
                                   vm_ci_kwarg(cd->ci));

        RB_OBJ_WRITTEN(reg_cfp->iseq, Qundef, cd->ci);
    }

    const struct rb_callcache *cc;

    VALUE klass = vm_search_normal_superclass(me->defined_class);

    if (!klass) {
        /* bound instance method of module */
        cc = vm_cc_new(klass, NULL, vm_call_method_missing, cc_type_super);
        RB_OBJ_WRITE(reg_cfp->iseq, &cd->cc, cc);
    }
    else {
        cc = vm_search_method_fastpath((VALUE)reg_cfp->iseq, cd, klass);
        const rb_callable_method_entry_t *cached_cme = vm_cc_cme(cc);

        // define_method can cache for different method id
        if (cached_cme == NULL) {
            // empty_cc_for_super is not markable object
            cd->cc = empty_cc_for_super();
        }
        else if (cached_cme->called_id != mid) {
            const rb_callable_method_entry_t *cme = rb_callable_method_entry(klass, mid);
            if (cme) {
                cc = vm_cc_new(klass, cme, vm_call_super_method, cc_type_super);
                RB_OBJ_WRITE(reg_cfp->iseq, &cd->cc, cc);
            }
            else {
                cd->cc = cc = empty_cc_for_super();
            }
        }
        else {
            switch (cached_cme->def->type) {
              // vm_call_refined (search_refined_method) assumes cc->call is vm_call_super_method on invokesuper
              case VM_METHOD_TYPE_REFINED:
              // cc->klass is superclass of receiver class. Checking cc->klass is not enough to invalidate IVC for the receiver class.
              case VM_METHOD_TYPE_ATTRSET:
              case VM_METHOD_TYPE_IVAR:
                vm_cc_call_set(cc, vm_call_super_method); // invalidate fastpath
                break;
              default:
                break; // use fastpath
            }
        }
    }

    VM_ASSERT((vm_cc_cme(cc), true));

    return cc;
}

/* yield */

static inline int
block_proc_is_lambda(const VALUE procval)
{
    rb_proc_t *proc;

    if (procval) {
        GetProcPtr(procval, proc);
        return proc->is_lambda;
    }
    else {
        return 0;
    }
}

static VALUE
vm_yield_with_cfunc(rb_execution_context_t *ec,
                    const struct rb_captured_block *captured,
                    VALUE self, int argc, const VALUE *argv, int kw_splat, VALUE block_handler,
                    const rb_callable_method_entry_t *me)
{
    int is_lambda = FALSE; /* TODO */
    VALUE val, arg, blockarg;
    int frame_flag;
    const struct vm_ifunc *ifunc = captured->code.ifunc;

    if (is_lambda) {
        arg = rb_ary_new4(argc, argv);
    }
    else if (argc == 0) {
        arg = Qnil;
    }
    else {
        arg = argv[0];
    }

    blockarg = rb_vm_bh_to_procval(ec, block_handler);

    frame_flag = VM_FRAME_MAGIC_IFUNC | VM_FRAME_FLAG_CFRAME | (me ? VM_FRAME_FLAG_BMETHOD : 0);
    if (kw_splat) {
        frame_flag |= VM_FRAME_FLAG_CFRAME_KW;
    }

    vm_push_frame(ec, (const rb_iseq_t *)captured->code.ifunc,
                  frame_flag,
                  self,
                  VM_GUARDED_PREV_EP(captured->ep),
                  (VALUE)me,
                  0, ec->cfp->sp, 0, 0);
    val = (*ifunc->func)(arg, (VALUE)ifunc->data, argc, argv, blockarg);
    rb_vm_pop_frame(ec);

    return val;
}

VALUE
rb_vm_yield_with_cfunc(rb_execution_context_t *ec, const struct rb_captured_block *captured, int argc, const VALUE *argv)
{
    return vm_yield_with_cfunc(ec, captured, captured->self, argc, argv, 0, VM_BLOCK_HANDLER_NONE, NULL);
}

static VALUE
vm_yield_with_symbol(rb_execution_context_t *ec,  VALUE symbol, int argc, const VALUE *argv, int kw_splat, VALUE block_handler)
{
    return rb_sym_proc_call(SYM2ID(symbol), argc, argv, kw_splat, rb_vm_bh_to_procval(ec, block_handler));
}

static inline int
vm_callee_setup_block_arg_arg0_splat(rb_control_frame_t *cfp, const rb_iseq_t *iseq, VALUE *argv, VALUE ary)
{
    int i;
    long len = RARRAY_LEN(ary);

    CHECK_VM_STACK_OVERFLOW(cfp, ISEQ_BODY(iseq)->param.lead_num);

    for (i=0; i<len && i<ISEQ_BODY(iseq)->param.lead_num; i++) {
        argv[i] = RARRAY_AREF(ary, i);
    }

    return i;
}

static inline VALUE
vm_callee_setup_block_arg_arg0_check(VALUE *argv)
{
    VALUE ary, arg0 = argv[0];
    ary = rb_check_array_type(arg0);
#if 0
    argv[0] = arg0;
#else
    VM_ASSERT(argv[0] == arg0);
#endif
    return ary;
}

static int
vm_callee_setup_block_arg(rb_execution_context_t *ec, struct rb_calling_info *calling, const struct rb_callinfo *ci, const rb_iseq_t *iseq, VALUE *argv, const enum arg_setup_type arg_setup_type)
{
    if (rb_simple_iseq_p(iseq)) {
        rb_control_frame_t *cfp = ec->cfp;
        VALUE arg0;

        CALLER_SETUP_ARG(cfp, calling, ci, ISEQ_BODY(iseq)->param.lead_num);

        if (arg_setup_type == arg_setup_block &&
            calling->argc == 1 &&
            ISEQ_BODY(iseq)->param.flags.has_lead &&
            !ISEQ_BODY(iseq)->param.flags.ambiguous_param0 &&
            !NIL_P(arg0 = vm_callee_setup_block_arg_arg0_check(argv))) {
            calling->argc = vm_callee_setup_block_arg_arg0_splat(cfp, iseq, argv, arg0);
        }

        if (calling->argc != ISEQ_BODY(iseq)->param.lead_num) {
            if (arg_setup_type == arg_setup_block) {
                if (calling->argc < ISEQ_BODY(iseq)->param.lead_num) {
                    int i;
                    CHECK_VM_STACK_OVERFLOW(cfp, ISEQ_BODY(iseq)->param.lead_num);
                    for (i=calling->argc; i<ISEQ_BODY(iseq)->param.lead_num; i++) argv[i] = Qnil;
                    calling->argc = ISEQ_BODY(iseq)->param.lead_num; /* fill rest parameters */
                }
                else if (calling->argc > ISEQ_BODY(iseq)->param.lead_num) {
                    calling->argc = ISEQ_BODY(iseq)->param.lead_num; /* simply truncate arguments */
                }
            }
            else {
                argument_arity_error(ec, iseq, calling->argc, ISEQ_BODY(iseq)->param.lead_num, ISEQ_BODY(iseq)->param.lead_num);
            }
        }

        return 0;
    }
    else {
        return setup_parameters_complex(ec, iseq, calling, ci, argv, arg_setup_type);
    }
}

static int
vm_yield_setup_args(rb_execution_context_t *ec, const rb_iseq_t *iseq, const int argc, VALUE *argv, int flags, VALUE block_handler, enum arg_setup_type arg_setup_type)
{
    struct rb_calling_info calling_entry, *calling;

    calling = &calling_entry;
    calling->argc = argc;
    calling->block_handler = block_handler;
    calling->kw_splat = (flags & VM_CALL_KW_SPLAT) ?  1 : 0;
    calling->recv = Qundef;
    calling->heap_argv = 0;
    struct rb_callinfo dummy_ci = VM_CI_ON_STACK(0, flags, 0, 0);

    return vm_callee_setup_block_arg(ec, calling, &dummy_ci, iseq, argv, arg_setup_type);
}

/* ruby iseq -> ruby block */

static VALUE
vm_invoke_iseq_block(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp,
                     struct rb_calling_info *calling, const struct rb_callinfo *ci,
                     bool is_lambda, VALUE block_handler)
{
    const struct rb_captured_block *captured = VM_BH_TO_ISEQ_BLOCK(block_handler);
    const rb_iseq_t *iseq = rb_iseq_check(captured->code.iseq);
    const int arg_size = ISEQ_BODY(iseq)->param.size;
    VALUE * const rsp = GET_SP() - calling->argc;
    VALUE * const argv = rsp;
    int opt_pc = vm_callee_setup_block_arg(ec, calling, ci, iseq, argv, is_lambda ? arg_setup_method : arg_setup_block);

    SET_SP(rsp);

    vm_push_frame(ec, iseq,
                  VM_FRAME_MAGIC_BLOCK | (is_lambda ? VM_FRAME_FLAG_LAMBDA : 0),
                  captured->self,
                  VM_GUARDED_PREV_EP(captured->ep), 0,
                  ISEQ_BODY(iseq)->iseq_encoded + opt_pc,
                  rsp + arg_size,
                  ISEQ_BODY(iseq)->local_table_size - arg_size, ISEQ_BODY(iseq)->stack_max);

    return Qundef;
}

static VALUE
vm_invoke_symbol_block(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp,
                       struct rb_calling_info *calling, const struct rb_callinfo *ci,
                       MAYBE_UNUSED(bool is_lambda), VALUE block_handler)
{
    VALUE symbol = VM_BH_TO_SYMBOL(block_handler);
    int flags = vm_ci_flag(ci);

    if (UNLIKELY(!(flags & VM_CALL_ARGS_SIMPLE) &&
        ((calling->argc == 0) ||
         (calling->argc == 1 && (flags & (VM_CALL_ARGS_SPLAT | VM_CALL_KW_SPLAT))) ||
         (calling->argc == 2 && (flags & VM_CALL_ARGS_SPLAT) && (flags & VM_CALL_KW_SPLAT)) ||
         ((flags & VM_CALL_KWARG) && (vm_ci_kwarg(ci)->keyword_len == calling->argc))))) {
        CALLER_SETUP_ARG(reg_cfp, calling, ci, ALLOW_HEAP_ARGV);
        flags = 0;
        if (UNLIKELY(calling->heap_argv)) {
#if VM_ARGC_STACK_MAX < 0
            if (RARRAY_LEN(calling->heap_argv) < 1) {
                rb_raise(rb_eArgError, "no receiver given");
            }
#endif
            calling->recv = rb_ary_shift(calling->heap_argv);
            // Modify stack to avoid cfp consistency error
            reg_cfp->sp++;
            reg_cfp->sp[-1] = reg_cfp->sp[-2];
            reg_cfp->sp[-2] = calling->recv;
            flags |= VM_CALL_ARGS_SPLAT;
        }
        else {
            if (calling->argc < 1) {
                rb_raise(rb_eArgError, "no receiver given");
            }
            calling->recv = TOPN(--calling->argc);
        }
        if (calling->kw_splat) {
            flags |= VM_CALL_KW_SPLAT;
        }
    }
    else {
        if (calling->argc < 1) {
            rb_raise(rb_eArgError, "no receiver given");
        }
        calling->recv = TOPN(--calling->argc);
    }

    return vm_call_symbol(ec, reg_cfp, calling, ci, symbol, flags);
}

static VALUE
vm_invoke_ifunc_block(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp,
                      struct rb_calling_info *calling, const struct rb_callinfo *ci,
                      MAYBE_UNUSED(bool is_lambda), VALUE block_handler)
{
    VALUE val;
    int argc;
    const struct rb_captured_block *captured = VM_BH_TO_IFUNC_BLOCK(block_handler);
    CALLER_SETUP_ARG(ec->cfp, calling, ci, ALLOW_HEAP_ARGV_KEEP_KWSPLAT);
    argc = calling->argc;
    val = vm_yield_with_cfunc(ec, captured, captured->self, CALLING_ARGC(calling), calling->heap_argv ? RARRAY_CONST_PTR(calling->heap_argv) : STACK_ADDR_FROM_TOP(argc), calling->kw_splat, calling->block_handler, NULL);
    POPN(argc); /* TODO: should put before C/yield? */
    return val;
}

static VALUE
vm_proc_to_block_handler(VALUE procval)
{
    const struct rb_block *block = vm_proc_block(procval);

    switch (vm_block_type(block)) {
      case block_type_iseq:
        return VM_BH_FROM_ISEQ_BLOCK(&block->as.captured);
      case block_type_ifunc:
        return VM_BH_FROM_IFUNC_BLOCK(&block->as.captured);
      case block_type_symbol:
        return VM_BH_FROM_SYMBOL(block->as.symbol);
      case block_type_proc:
        return VM_BH_FROM_PROC(block->as.proc);
    }
    VM_UNREACHABLE(vm_yield_with_proc);
    return Qundef;
}

static VALUE
vm_invoke_proc_block(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp,
                     struct rb_calling_info *calling, const struct rb_callinfo *ci,
                     bool is_lambda, VALUE block_handler)
{
    while (vm_block_handler_type(block_handler) == block_handler_type_proc) {
        VALUE proc = VM_BH_TO_PROC(block_handler);
        is_lambda = block_proc_is_lambda(proc);
        block_handler = vm_proc_to_block_handler(proc);
    }

    return vm_invoke_block(ec, reg_cfp, calling, ci, is_lambda, block_handler);
}

static inline VALUE
vm_invoke_block(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp,
                struct rb_calling_info *calling, const struct rb_callinfo *ci,
                bool is_lambda, VALUE block_handler)
{
    VALUE (*func)(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp,
                  struct rb_calling_info *calling, const struct rb_callinfo *ci,
                  bool is_lambda, VALUE block_handler);

    switch (vm_block_handler_type(block_handler)) {
      case block_handler_type_iseq:   func = vm_invoke_iseq_block;   break;
      case block_handler_type_ifunc:  func = vm_invoke_ifunc_block;  break;
      case block_handler_type_proc:   func = vm_invoke_proc_block;   break;
      case block_handler_type_symbol: func = vm_invoke_symbol_block; break;
      default: rb_bug("vm_invoke_block: unreachable");
    }

    return func(ec, reg_cfp, calling, ci, is_lambda, block_handler);
}

static VALUE
vm_make_proc_with_iseq(const rb_iseq_t *blockiseq)
{
    const rb_execution_context_t *ec = GET_EC();
    const rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(ec, ec->cfp);
    struct rb_captured_block *captured;

    if (cfp == 0) {
        rb_bug("vm_make_proc_with_iseq: unreachable");
    }

    captured = VM_CFP_TO_CAPTURED_BLOCK(cfp);
    captured->code.iseq = blockiseq;

    return rb_vm_make_proc(ec, captured, rb_cProc);
}

static VALUE
vm_once_exec(VALUE iseq)
{
    VALUE proc = vm_make_proc_with_iseq((rb_iseq_t *)iseq);
    return rb_proc_call_with_block(proc, 0, 0, Qnil);
}

static VALUE
vm_once_clear(VALUE data)
{
    union iseq_inline_storage_entry *is = (union iseq_inline_storage_entry *)data;
    is->once.running_thread = NULL;
    return Qnil;
}

/* defined insn */

static bool
check_respond_to_missing(VALUE obj, VALUE v)
{
    VALUE args[2];
    VALUE r;

    args[0] = obj; args[1] = Qfalse;
    r = rb_check_funcall(v, idRespond_to_missing, 2, args);
    if (!UNDEF_P(r) && RTEST(r)) {
        return true;
    }
    else {
        return false;
    }
}

static bool
vm_defined(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, rb_num_t op_type, VALUE obj, VALUE v)
{
    VALUE klass;
    enum defined_type type = (enum defined_type)op_type;

    switch (type) {
      case DEFINED_IVAR:
        return rb_ivar_defined(GET_SELF(), SYM2ID(obj));
        break;
      case DEFINED_GVAR:
        return rb_gvar_defined(SYM2ID(obj));
        break;
      case DEFINED_CVAR: {
        const rb_cref_t *cref = vm_get_cref(GET_EP());
        klass = vm_get_cvar_base(cref, GET_CFP(), 0);
        return rb_cvar_defined(klass, SYM2ID(obj));
        break;
      }
      case DEFINED_CONST:
      case DEFINED_CONST_FROM: {
        bool allow_nil = type == DEFINED_CONST;
        klass = v;
        return vm_get_ev_const(ec, klass, SYM2ID(obj), allow_nil, true);
        break;
      }
      case DEFINED_FUNC:
        klass = CLASS_OF(v);
        return rb_ec_obj_respond_to(ec, v, SYM2ID(obj), TRUE);
        break;
      case DEFINED_METHOD:{
        VALUE klass = CLASS_OF(v);
        const rb_method_entry_t *me = rb_method_entry_with_refinements(klass, SYM2ID(obj), NULL);

        if (me) {
            switch (METHOD_ENTRY_VISI(me)) {
              case METHOD_VISI_PRIVATE:
                break;
              case METHOD_VISI_PROTECTED:
                if (!rb_obj_is_kind_of(GET_SELF(), rb_class_real(me->defined_class))) {
                    break;
                }
              case METHOD_VISI_PUBLIC:
                return true;
                break;
              default:
                rb_bug("vm_defined: unreachable: %u", (unsigned int)METHOD_ENTRY_VISI(me));
            }
        }
        else {
            return check_respond_to_missing(obj, v);
        }
        break;
      }
      case DEFINED_YIELD:
        if (GET_BLOCK_HANDLER() != VM_BLOCK_HANDLER_NONE) {
            return true;
        }
        break;
      case DEFINED_ZSUPER:
        {
            const rb_callable_method_entry_t *me = rb_vm_frame_method_entry(GET_CFP());

            if (me) {
                VALUE klass = vm_search_normal_superclass(me->defined_class);
                if (!klass) return false;

                ID id = me->def->original_id;

                return rb_method_boundp(klass, id, 0);
            }
        }
        break;
      case DEFINED_REF:
        return RTEST(vm_backref_defined(ec, GET_LEP(), FIX2INT(obj)));
      default:
        rb_bug("unimplemented defined? type (VM)");
        break;
    }

    return false;
}

bool
rb_vm_defined(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, rb_num_t op_type, VALUE obj, VALUE v)
{
    return vm_defined(ec, reg_cfp, op_type, obj, v);
}

static const VALUE *
vm_get_ep(const VALUE *const reg_ep, rb_num_t lv)
{
    rb_num_t i;
    const VALUE *ep = reg_ep;
    for (i = 0; i < lv; i++) {
        ep = GET_PREV_EP(ep);
    }
    return ep;
}

static VALUE
vm_get_special_object(const VALUE *const reg_ep,
                      enum vm_special_object_type type)
{
    switch (type) {
      case VM_SPECIAL_OBJECT_VMCORE:
        return rb_mRubyVMFrozenCore;
      case VM_SPECIAL_OBJECT_CBASE:
        return vm_get_cbase(reg_ep);
      case VM_SPECIAL_OBJECT_CONST_BASE:
        return vm_get_const_base(reg_ep);
      default:
        rb_bug("putspecialobject insn: unknown value_type %d", type);
    }
}

static VALUE
vm_concat_array(VALUE ary1, VALUE ary2st)
{
    const VALUE ary2 = ary2st;
    VALUE tmp1 = rb_check_to_array(ary1);
    VALUE tmp2 = rb_check_to_array(ary2);

    if (NIL_P(tmp1)) {
        tmp1 = rb_ary_new3(1, ary1);
    }
    if (tmp1 == ary1) {
        tmp1 = rb_ary_dup(ary1);
    }

    if (NIL_P(tmp2)) {
        return rb_ary_push(tmp1, ary2);
    } else {
        return rb_ary_concat(tmp1, tmp2);
    }
}

static VALUE
vm_concat_to_array(VALUE ary1, VALUE ary2st)
{
    /* ary1 must be a newly created array */
    const VALUE ary2 = ary2st;
    VALUE tmp2 = rb_check_to_array(ary2);

    if (NIL_P(tmp2)) {
        return rb_ary_push(ary1, ary2);
    } else {
        return rb_ary_concat(ary1, tmp2);
    }
}

// YJIT implementation is using the C function
// and needs to call a non-static function
VALUE
rb_vm_concat_array(VALUE ary1, VALUE ary2st)
{
    return vm_concat_array(ary1, ary2st);
}

VALUE
rb_vm_concat_to_array(VALUE ary1, VALUE ary2st)
{
    return vm_concat_to_array(ary1, ary2st);
}

static VALUE
vm_splat_array(VALUE flag, VALUE ary)
{
    VALUE tmp = rb_check_to_array(ary);
    if (NIL_P(tmp)) {
        return rb_ary_new3(1, ary);
    }
    else if (RTEST(flag)) {
        return rb_ary_dup(tmp);
    }
    else {
        return tmp;
    }
}

// YJIT implementation is using the C function
// and needs to call a non-static function
VALUE
rb_vm_splat_array(VALUE flag, VALUE ary)
{
    return vm_splat_array(flag, ary);
}

static VALUE
vm_check_match(rb_execution_context_t *ec, VALUE target, VALUE pattern, rb_num_t flag)
{
    enum vm_check_match_type type = ((int)flag) & VM_CHECKMATCH_TYPE_MASK;

    if (flag & VM_CHECKMATCH_ARRAY) {
        long i;
        const long n = RARRAY_LEN(pattern);

        for (i = 0; i < n; i++) {
            VALUE v = RARRAY_AREF(pattern, i);
            VALUE c = check_match(ec, v, target, type);

            if (RTEST(c)) {
                return c;
            }
        }
        return Qfalse;
    }
    else {
        return check_match(ec, pattern, target, type);
    }
}

VALUE
rb_vm_check_match(rb_execution_context_t *ec, VALUE target, VALUE pattern, rb_num_t flag)
{
    return vm_check_match(ec, target, pattern, flag);
}

static VALUE
vm_check_keyword(lindex_t bits, lindex_t idx, const VALUE *ep)
{
    const VALUE kw_bits = *(ep - bits);

    if (FIXNUM_P(kw_bits)) {
        unsigned int b = (unsigned int)FIX2ULONG(kw_bits);
        if ((idx < KW_SPECIFIED_BITS_MAX) && (b & (0x01 << idx)))
            return Qfalse;
    }
    else {
        VM_ASSERT(RB_TYPE_P(kw_bits, T_HASH));
        if (rb_hash_has_key(kw_bits, INT2FIX(idx))) return Qfalse;
    }
    return Qtrue;
}

static void
vm_dtrace(rb_event_flag_t flag, rb_execution_context_t *ec)
{
    if (RUBY_DTRACE_METHOD_ENTRY_ENABLED() ||
        RUBY_DTRACE_METHOD_RETURN_ENABLED() ||
        RUBY_DTRACE_CMETHOD_ENTRY_ENABLED() ||
        RUBY_DTRACE_CMETHOD_RETURN_ENABLED()) {

        switch (flag) {
          case RUBY_EVENT_CALL:
            RUBY_DTRACE_METHOD_ENTRY_HOOK(ec, 0, 0);
            return;
          case RUBY_EVENT_C_CALL:
            RUBY_DTRACE_CMETHOD_ENTRY_HOOK(ec, 0, 0);
            return;
          case RUBY_EVENT_RETURN:
            RUBY_DTRACE_METHOD_RETURN_HOOK(ec, 0, 0);
            return;
          case RUBY_EVENT_C_RETURN:
            RUBY_DTRACE_CMETHOD_RETURN_HOOK(ec, 0, 0);
            return;
        }
    }
}

static VALUE
vm_const_get_under(ID id, rb_num_t flags, VALUE cbase)
{
    if (!rb_const_defined_at(cbase, id)) {
        return 0;
    }
    else if (VM_DEFINECLASS_SCOPED_P(flags)) {
        return rb_public_const_get_at(cbase, id);
    }
    else {
        return rb_const_get_at(cbase, id);
    }
}

static VALUE
vm_check_if_class(ID id, rb_num_t flags, VALUE super, VALUE klass)
{
    if (!RB_TYPE_P(klass, T_CLASS)) {
        return 0;
    }
    else if (VM_DEFINECLASS_HAS_SUPERCLASS_P(flags)) {
        VALUE tmp = rb_class_real(RCLASS_SUPER(klass));

        if (tmp != super) {
            rb_raise(rb_eTypeError,
                     "superclass mismatch for class %"PRIsVALUE"",
                     rb_id2str(id));
        }
        else {
            return klass;
        }
    }
    else {
        return klass;
    }
}

static VALUE
vm_check_if_module(ID id, VALUE mod)
{
    if (!RB_TYPE_P(mod, T_MODULE)) {
        return 0;
    }
    else {
        return mod;
    }
}

static VALUE
declare_under(ID id, VALUE cbase, VALUE c)
{
    rb_set_class_path_string(c, cbase, rb_id2str(id));
    rb_const_set(cbase, id, c);
    return c;
}

static VALUE
vm_declare_class(ID id, rb_num_t flags, VALUE cbase, VALUE super)
{
    /* new class declaration */
    VALUE s = VM_DEFINECLASS_HAS_SUPERCLASS_P(flags) ? super : rb_cObject;
    VALUE c = declare_under(id, cbase, rb_define_class_id(id, s));
    rb_define_alloc_func(c, rb_get_alloc_func(c));
    rb_class_inherited(s, c);
    return c;
}

static VALUE
vm_declare_module(ID id, VALUE cbase)
{
    /* new module declaration */
    return declare_under(id, cbase, rb_module_new());
}

NORETURN(static void unmatched_redefinition(const char *type, VALUE cbase, ID id, VALUE old));
static void
unmatched_redefinition(const char *type, VALUE cbase, ID id, VALUE old)
{
    VALUE name = rb_id2str(id);
    VALUE message = rb_sprintf("%"PRIsVALUE" is not a %s",
                               name, type);
    VALUE location = rb_const_source_location_at(cbase, id);
    if (!NIL_P(location)) {
        rb_str_catf(message, "\n%"PRIsVALUE":%"PRIsVALUE":"
                    " previous definition of %"PRIsVALUE" was here",
                    rb_ary_entry(location, 0), rb_ary_entry(location, 1), name);
    }
    rb_exc_raise(rb_exc_new_str(rb_eTypeError, message));
}

static VALUE
vm_define_class(ID id, rb_num_t flags, VALUE cbase, VALUE super)
{
    VALUE klass;

    if (VM_DEFINECLASS_HAS_SUPERCLASS_P(flags) && !RB_TYPE_P(super, T_CLASS)) {
        rb_raise(rb_eTypeError,
                 "superclass must be an instance of Class (given an instance of %"PRIsVALUE")",
                 rb_obj_class(super));
    }

    vm_check_if_namespace(cbase);

    /* find klass */
    rb_autoload_load(cbase, id);
    if ((klass = vm_const_get_under(id, flags, cbase)) != 0) {
        if (!vm_check_if_class(id, flags, super, klass))
            unmatched_redefinition("class", cbase, id, klass);
        return klass;
    }
    else {
        return vm_declare_class(id, flags, cbase, super);
    }
}

static VALUE
vm_define_module(ID id, rb_num_t flags, VALUE cbase)
{
    VALUE mod;

    vm_check_if_namespace(cbase);
    if ((mod = vm_const_get_under(id, flags, cbase)) != 0) {
        if (!vm_check_if_module(id, mod))
            unmatched_redefinition("module", cbase, id, mod);
        return mod;
    }
    else {
        return vm_declare_module(id, cbase);
    }
}

static VALUE
vm_find_or_create_class_by_id(ID id,
                              rb_num_t flags,
                              VALUE cbase,
                              VALUE super)
{
    rb_vm_defineclass_type_t type = VM_DEFINECLASS_TYPE(flags);

    switch (type) {
      case VM_DEFINECLASS_TYPE_CLASS:
        /* classdef returns class scope value */
        return vm_define_class(id, flags, cbase, super);

      case VM_DEFINECLASS_TYPE_SINGLETON_CLASS:
        /* classdef returns class scope value */
        return rb_singleton_class(cbase);

      case VM_DEFINECLASS_TYPE_MODULE:
        /* classdef returns class scope value */
        return vm_define_module(id, flags, cbase);

      default:
        rb_bug("unknown defineclass type: %d", (int)type);
    }
}

static rb_method_visibility_t
vm_scope_visibility_get(const rb_execution_context_t *ec)
{
    const rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(ec, ec->cfp);

    if (!vm_env_cref_by_cref(cfp->ep)) {
        return METHOD_VISI_PUBLIC;
    }
    else {
        return CREF_SCOPE_VISI(vm_ec_cref(ec))->method_visi;
    }
}

static int
vm_scope_module_func_check(const rb_execution_context_t *ec)
{
    const rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(ec, ec->cfp);

    if (!vm_env_cref_by_cref(cfp->ep)) {
        return FALSE;
    }
    else {
        return CREF_SCOPE_VISI(vm_ec_cref(ec))->module_func;
    }
}

static void
vm_define_method(const rb_execution_context_t *ec, VALUE obj, ID id, VALUE iseqval, int is_singleton)
{
    VALUE klass;
    rb_method_visibility_t visi;
    rb_cref_t *cref = vm_ec_cref(ec);

    if (is_singleton) {
        klass = rb_singleton_class(obj); /* class and frozen checked in this API */
        visi = METHOD_VISI_PUBLIC;
    }
    else {
        klass = CREF_CLASS_FOR_DEFINITION(cref);
        visi = vm_scope_visibility_get(ec);
    }

    if (NIL_P(klass)) {
        rb_raise(rb_eTypeError, "no class/module to add method");
    }

    rb_add_method_iseq(klass, id, (const rb_iseq_t *)iseqval, cref, visi);
    // Set max_iv_count on klasses based on number of ivar sets that are in the initialize method
    if (id == idInitialize && klass != rb_cObject &&  RB_TYPE_P(klass, T_CLASS) && (rb_get_alloc_func(klass) == rb_class_allocate_instance)) {

        RCLASS_EXT(klass)->max_iv_count = rb_estimate_iv_count(klass, (const rb_iseq_t *)iseqval);
    }

    if (!is_singleton && vm_scope_module_func_check(ec)) {
        klass = rb_singleton_class(klass);
        rb_add_method_iseq(klass, id, (const rb_iseq_t *)iseqval, cref, METHOD_VISI_PUBLIC);
    }
}

static VALUE
vm_invokeblock_i(struct rb_execution_context_struct *ec,
                 struct rb_control_frame_struct *reg_cfp,
                 struct rb_calling_info *calling)
{
    const struct rb_callinfo *ci = calling->cd->ci;
    VALUE block_handler = VM_CF_BLOCK_HANDLER(GET_CFP());

    if (block_handler == VM_BLOCK_HANDLER_NONE) {
        rb_vm_localjump_error("no block given (yield)", Qnil, 0);
    }
    else {
        return vm_invoke_block(ec, GET_CFP(), calling, ci, false, block_handler);
    }
}

enum method_explorer_type {
    mexp_search_method,
    mexp_search_invokeblock,
    mexp_search_super,
};

static inline VALUE
vm_sendish(
    struct rb_execution_context_struct *ec,
    struct rb_control_frame_struct *reg_cfp,
    struct rb_call_data *cd,
    VALUE block_handler,
    enum method_explorer_type method_explorer
) {
    VALUE val = Qundef;
    const struct rb_callinfo *ci = cd->ci;
    const struct rb_callcache *cc;
    int argc = vm_ci_argc(ci);
    VALUE recv = TOPN(argc);
    struct rb_calling_info calling = {
        .block_handler = block_handler,
        .kw_splat = IS_ARGS_KW_SPLAT(ci) > 0,
        .recv = recv,
        .argc = argc,
        .cd = cd,
    };

    switch (method_explorer) {
      case mexp_search_method:
        calling.cc = cc = vm_search_method_fastpath((VALUE)reg_cfp->iseq, cd, CLASS_OF(recv));
        val = vm_cc_call(cc)(ec, GET_CFP(), &calling);
        break;
      case mexp_search_super:
        calling.cc = cc = vm_search_super_method(reg_cfp, cd, recv);
        val = vm_cc_call(cc)(ec, GET_CFP(), &calling);
        break;
      case mexp_search_invokeblock:
        val = vm_invokeblock_i(ec, GET_CFP(), &calling);
        break;
    }
    return val;
}

VALUE
rb_vm_send(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, CALL_DATA cd, ISEQ blockiseq)
{
    stack_check(ec);

    struct rb_forwarding_call_data adjusted_cd;
    struct rb_callinfo adjusted_ci;
    CALL_DATA _cd = cd;

    VALUE bh = vm_caller_setup_args(ec, GET_CFP(), &cd, blockiseq, false, &adjusted_cd, &adjusted_ci);
    VALUE val = vm_sendish(ec, GET_CFP(), cd, bh, mexp_search_method);

    if (vm_ci_flag(_cd->ci) & VM_CALL_FORWARDING) {
      if (_cd->cc != cd->cc && vm_cc_markable(cd->cc)) {
          RB_OBJ_WRITE(GET_ISEQ(), &_cd->cc, cd->cc);
      }
    }

    VM_EXEC(ec, val);
    return val;
}

VALUE
rb_vm_opt_send_without_block(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, CALL_DATA cd)
{
    stack_check(ec);
    VALUE bh = VM_BLOCK_HANDLER_NONE;
    VALUE val = vm_sendish(ec, GET_CFP(), cd, bh, mexp_search_method);
    VM_EXEC(ec, val);
    return val;
}

VALUE
rb_vm_invokesuper(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, CALL_DATA cd, ISEQ blockiseq)
{
    stack_check(ec);
    struct rb_forwarding_call_data adjusted_cd;
    struct rb_callinfo adjusted_ci;
    CALL_DATA _cd = cd;

    VALUE bh = vm_caller_setup_args(ec, GET_CFP(), &cd, blockiseq, true, &adjusted_cd, &adjusted_ci);
    VALUE val = vm_sendish(ec, GET_CFP(), cd, bh, mexp_search_super);

    if (vm_ci_flag(_cd->ci) & VM_CALL_FORWARDING) {
      if (_cd->cc != cd->cc && vm_cc_markable(cd->cc)) {
          RB_OBJ_WRITE(GET_ISEQ(), &_cd->cc, cd->cc);
      }
    }

    VM_EXEC(ec, val);
    return val;
}

VALUE
rb_vm_invokeblock(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, CALL_DATA cd)
{
    stack_check(ec);
    VALUE bh = VM_BLOCK_HANDLER_NONE;
    VALUE val = vm_sendish(ec, GET_CFP(), cd, bh, mexp_search_invokeblock);
    VM_EXEC(ec, val);
    return val;
}

/* object.c */
VALUE rb_nil_to_s(VALUE);
VALUE rb_true_to_s(VALUE);
VALUE rb_false_to_s(VALUE);
/* numeric.c */
VALUE rb_int_to_s(int argc, VALUE *argv, VALUE x);
VALUE rb_fix_to_s(VALUE);
/* variable.c */
VALUE rb_mod_to_s(VALUE);
VALUE rb_mod_name(VALUE);

static VALUE
vm_objtostring(const rb_iseq_t *iseq, VALUE recv, CALL_DATA cd)
{
    int type = TYPE(recv);
    if (type == T_STRING) {
        return recv;
    }

    const struct rb_callcache *cc = vm_search_method((VALUE)iseq, cd, recv);

    switch (type) {
      case T_SYMBOL:
        if (check_cfunc(vm_cc_cme(cc), rb_sym_to_s)) {
            // rb_sym_to_s() allocates a mutable string, but since we are only
            // going to use this string for interpolation, it's fine to use the
            // frozen string.
            return rb_sym2str(recv);
        }
        break;
      case T_MODULE:
      case T_CLASS:
        if (check_cfunc(vm_cc_cme(cc), rb_mod_to_s)) {
            // rb_mod_to_s() allocates a mutable string, but since we are only
            // going to use this string for interpolation, it's fine to use the
            // frozen string.
            VALUE val = rb_mod_name(recv);
            if (NIL_P(val)) {
                val = rb_mod_to_s(recv);
            }
            return val;
        }
        break;
      case T_NIL:
        if (check_cfunc(vm_cc_cme(cc), rb_nil_to_s)) {
            return rb_nil_to_s(recv);
        }
        break;
      case T_TRUE:
        if (check_cfunc(vm_cc_cme(cc), rb_true_to_s)) {
            return rb_true_to_s(recv);
        }
        break;
      case T_FALSE:
        if (check_cfunc(vm_cc_cme(cc), rb_false_to_s)) {
            return rb_false_to_s(recv);
        }
        break;
      case T_FIXNUM:
        if (check_cfunc(vm_cc_cme(cc), rb_int_to_s)) {
            return rb_fix_to_s(recv);
        }
        break;
    }
    return Qundef;
}

static VALUE
vm_opt_str_freeze(VALUE str, int bop, ID id)
{
    if (BASIC_OP_UNREDEFINED_P(bop, STRING_REDEFINED_OP_FLAG)) {
        return str;
    }
    else {
        return Qundef;
    }
}

/* this macro is mandatory to use OPTIMIZED_CMP. What a design! */
#define id_cmp idCmp

static VALUE
vm_opt_newarray_max(rb_execution_context_t *ec, rb_num_t num, const VALUE *ptr)
{
    if (BASIC_OP_UNREDEFINED_P(BOP_MAX, ARRAY_REDEFINED_OP_FLAG)) {
        if (num == 0) {
            return Qnil;
        }
        else {
            VALUE result = *ptr;
            rb_snum_t i = num - 1;
            while (i-- > 0) {
                const VALUE v = *++ptr;
                if (OPTIMIZED_CMP(v, result) > 0) {
                    result = v;
                }
            }
            return result;
        }
    }
    else {
        return rb_vm_call_with_refinements(ec, rb_ary_new4(num, ptr), idMax, 0, NULL, RB_NO_KEYWORDS);
    }
}

VALUE
rb_vm_opt_newarray_max(rb_execution_context_t *ec, rb_num_t num, const VALUE *ptr)
{
    return vm_opt_newarray_max(ec, num, ptr);
}

static VALUE
vm_opt_newarray_min(rb_execution_context_t *ec, rb_num_t num, const VALUE *ptr)
{
    if (BASIC_OP_UNREDEFINED_P(BOP_MIN, ARRAY_REDEFINED_OP_FLAG)) {
        if (num == 0) {
            return Qnil;
        }
        else {
            VALUE result = *ptr;
            rb_snum_t i = num - 1;
            while (i-- > 0) {
                const VALUE v = *++ptr;
                if (OPTIMIZED_CMP(v, result) < 0) {
                    result = v;
                }
            }
            return result;
        }
    }
    else {
        return rb_vm_call_with_refinements(ec, rb_ary_new4(num, ptr), idMin, 0, NULL, RB_NO_KEYWORDS);
    }
}

VALUE
rb_vm_opt_newarray_min(rb_execution_context_t *ec, rb_num_t num, const VALUE *ptr)
{
    return vm_opt_newarray_min(ec, num, ptr);
}

static VALUE
vm_opt_newarray_hash(rb_execution_context_t *ec, rb_num_t num, const VALUE *ptr)
{
    // If Array#hash is _not_ monkeypatched, use the optimized call
    if (BASIC_OP_UNREDEFINED_P(BOP_HASH, ARRAY_REDEFINED_OP_FLAG)) {
        return rb_ary_hash_values(num, ptr);
    }
    else {
        return rb_vm_call_with_refinements(ec, rb_ary_new4(num, ptr), idHash, 0, NULL, RB_NO_KEYWORDS);
    }
}

VALUE
rb_vm_opt_newarray_hash(rb_execution_context_t *ec, rb_num_t num, const VALUE *ptr)
{
    return vm_opt_newarray_hash(ec, num, ptr);
}

VALUE rb_setup_fake_ary(struct RArray *fake_ary, const VALUE *list, long len, bool freeze);
VALUE rb_ec_pack_ary(rb_execution_context_t *ec, VALUE ary, VALUE fmt, VALUE buffer);

VALUE
rb_vm_opt_newarray_pack(rb_execution_context_t *ec, rb_num_t num, const VALUE *ptr, VALUE fmt)
{
    if (BASIC_OP_UNREDEFINED_P(BOP_PACK, ARRAY_REDEFINED_OP_FLAG)) {
        struct RArray fake_ary;
        VALUE ary = rb_setup_fake_ary(&fake_ary, ptr, num, true);
        return rb_ec_pack_ary(ec, ary, fmt, Qnil);
    }
    else {
        return rb_vm_call_with_refinements(ec, rb_ary_new4(num, ptr), idPack, 1, &fmt, RB_PASS_CALLED_KEYWORDS);
    }
}

#undef id_cmp

#define IMEMO_CONST_CACHE_SHAREABLE IMEMO_FL_USER0

static void
vm_track_constant_cache(ID id, void *ic)
{
    struct rb_id_table *const_cache = GET_VM()->constant_cache;
    VALUE lookup_result;
    st_table *ics;

    if (rb_id_table_lookup(const_cache, id, &lookup_result)) {
        ics = (st_table *)lookup_result;
    }
    else {
        ics = st_init_numtable();
        rb_id_table_insert(const_cache, id, (VALUE)ics);
    }

    st_insert(ics, (st_data_t) ic, (st_data_t) Qtrue);
}

static void
vm_ic_track_const_chain(rb_control_frame_t *cfp, IC ic, const ID *segments)
{
    RB_VM_LOCK_ENTER();

    for (int i = 0; segments[i]; i++) {
        ID id = segments[i];
        if (id == idNULL) continue;
        vm_track_constant_cache(id, ic);
    }

    RB_VM_LOCK_LEAVE();
}

// For RJIT inlining
static inline bool
vm_inlined_ic_hit_p(VALUE flags, VALUE value, const rb_cref_t *ic_cref, const VALUE *reg_ep)
{
    if ((flags & IMEMO_CONST_CACHE_SHAREABLE) || rb_ractor_main_p()) {
        VM_ASSERT(ractor_incidental_shareable_p(flags & IMEMO_CONST_CACHE_SHAREABLE, value));

        return (ic_cref == NULL || // no need to check CREF
                ic_cref == vm_get_cref(reg_ep));
    }
    return false;
}

static bool
vm_ic_hit_p(const struct iseq_inline_constant_cache_entry *ice, const VALUE *reg_ep)
{
    VM_ASSERT(IMEMO_TYPE_P(ice, imemo_constcache));
    return vm_inlined_ic_hit_p(ice->flags, ice->value, ice->ic_cref, reg_ep);
}

// YJIT needs this function to never allocate and never raise
bool
rb_vm_ic_hit_p(IC ic, const VALUE *reg_ep)
{
    return ic->entry && vm_ic_hit_p(ic->entry, reg_ep);
}

static void
vm_ic_update(const rb_iseq_t *iseq, IC ic, VALUE val, const VALUE *reg_ep, const VALUE *pc)
{
    if (ruby_vm_const_missing_count > 0) {
        ruby_vm_const_missing_count = 0;
        ic->entry = NULL;
        return;
    }

    struct iseq_inline_constant_cache_entry *ice = IMEMO_NEW(struct iseq_inline_constant_cache_entry, imemo_constcache, 0);
    RB_OBJ_WRITE(ice, &ice->value, val);
    ice->ic_cref = vm_get_const_key_cref(reg_ep);
    if (rb_ractor_shareable_p(val)) ice->flags |= IMEMO_CONST_CACHE_SHAREABLE;
    RB_OBJ_WRITE(iseq, &ic->entry, ice);

    RUBY_ASSERT(pc >= ISEQ_BODY(iseq)->iseq_encoded);
    unsigned pos = (unsigned)(pc - ISEQ_BODY(iseq)->iseq_encoded);
    rb_yjit_constant_ic_update(iseq, ic, pos);
    rb_rjit_constant_ic_update(iseq, ic, pos);
}

VALUE
rb_vm_opt_getconstant_path(rb_execution_context_t *ec, rb_control_frame_t *const reg_cfp, IC ic)
{
    VALUE val;
    const ID *segments = ic->segments;
    struct iseq_inline_constant_cache_entry *ice = ic->entry;
    if (ice && vm_ic_hit_p(ice, GET_EP())) {
        val = ice->value;

        VM_ASSERT(val == vm_get_ev_const_chain(ec, segments));
    }
    else {
        ruby_vm_constant_cache_misses++;
        val = vm_get_ev_const_chain(ec, segments);
        vm_ic_track_const_chain(GET_CFP(), ic, segments);
        // Undo the PC increment to get the address to this instruction
        // INSN_ATTR(width) == 2
        vm_ic_update(GET_ISEQ(), ic, val, GET_EP(), GET_PC() - 2);
    }
    return val;
}

static VALUE
vm_once_dispatch(rb_execution_context_t *ec, ISEQ iseq, ISE is)
{
    rb_thread_t *th = rb_ec_thread_ptr(ec);
    rb_thread_t *const RUNNING_THREAD_ONCE_DONE = (rb_thread_t *)(0x1);

  again:
    if (is->once.running_thread == RUNNING_THREAD_ONCE_DONE) {
        return is->once.value;
    }
    else if (is->once.running_thread == NULL) {
        VALUE val;
        is->once.running_thread = th;
        val = rb_ensure(vm_once_exec, (VALUE)iseq, vm_once_clear, (VALUE)is);
        RB_OBJ_WRITE(ec->cfp->iseq, &is->once.value, val);
        /* is->once.running_thread is cleared by vm_once_clear() */
        is->once.running_thread = RUNNING_THREAD_ONCE_DONE; /* success */
        return val;
    }
    else if (is->once.running_thread == th) {
        /* recursive once */
        return vm_once_exec((VALUE)iseq);
    }
    else {
        /* waiting for finish */
        RUBY_VM_CHECK_INTS(ec);
        rb_thread_schedule();
        goto again;
    }
}

static OFFSET
vm_case_dispatch(CDHASH hash, OFFSET else_offset, VALUE key)
{
    switch (OBJ_BUILTIN_TYPE(key)) {
      case -1:
      case T_FLOAT:
      case T_SYMBOL:
      case T_BIGNUM:
      case T_STRING:
        if (BASIC_OP_UNREDEFINED_P(BOP_EQQ,
                                   SYMBOL_REDEFINED_OP_FLAG |
                                   INTEGER_REDEFINED_OP_FLAG |
                                   FLOAT_REDEFINED_OP_FLAG |
                                   NIL_REDEFINED_OP_FLAG    |
                                   TRUE_REDEFINED_OP_FLAG   |
                                   FALSE_REDEFINED_OP_FLAG  |
                                   STRING_REDEFINED_OP_FLAG)) {
            st_data_t val;
            if (RB_FLOAT_TYPE_P(key)) {
                double kval = RFLOAT_VALUE(key);
                if (!isinf(kval) && modf(kval, &kval) == 0.0) {
                    key = FIXABLE(kval) ? LONG2FIX((long)kval) : rb_dbl2big(kval);
                }
            }
            if (rb_hash_stlike_lookup(hash, key, &val)) {
                return FIX2LONG((VALUE)val);
            }
            else {
                return else_offset;
            }
        }
    }
    return 0;
}

NORETURN(static void
         vm_stack_consistency_error(const rb_execution_context_t *ec,
                                    const rb_control_frame_t *,
                                    const VALUE *));
static void
vm_stack_consistency_error(const rb_execution_context_t *ec,
                           const rb_control_frame_t *cfp,
                           const VALUE *bp)
{
    const ptrdiff_t nsp = VM_SP_CNT(ec, cfp->sp);
    const ptrdiff_t nbp = VM_SP_CNT(ec, bp);
    static const char stack_consistency_error[] =
        "Stack consistency error (sp: %"PRIdPTRDIFF", bp: %"PRIdPTRDIFF")";
#if defined RUBY_DEVEL
    VALUE mesg = rb_sprintf(stack_consistency_error, nsp, nbp);
    rb_str_cat_cstr(mesg, "\n");
    rb_str_append(mesg, rb_iseq_disasm(cfp->iseq));
    rb_exc_fatal(rb_exc_new3(rb_eFatal, mesg));
#else
    rb_bug(stack_consistency_error, nsp, nbp);
#endif
}

static VALUE
vm_opt_plus(VALUE recv, VALUE obj)
{
    if (FIXNUM_2_P(recv, obj) &&
        BASIC_OP_UNREDEFINED_P(BOP_PLUS, INTEGER_REDEFINED_OP_FLAG)) {
        return rb_fix_plus_fix(recv, obj);
    }
    else if (FLONUM_2_P(recv, obj) &&
             BASIC_OP_UNREDEFINED_P(BOP_PLUS, FLOAT_REDEFINED_OP_FLAG)) {
        return DBL2NUM(RFLOAT_VALUE(recv) + RFLOAT_VALUE(obj));
    }
    else if (SPECIAL_CONST_P(recv) || SPECIAL_CONST_P(obj)) {
        return Qundef;
    }
    else if (RBASIC_CLASS(recv) == rb_cFloat &&
             RBASIC_CLASS(obj)  == rb_cFloat &&
             BASIC_OP_UNREDEFINED_P(BOP_PLUS, FLOAT_REDEFINED_OP_FLAG)) {
        return DBL2NUM(RFLOAT_VALUE(recv) + RFLOAT_VALUE(obj));
    }
    else if (RBASIC_CLASS(recv) == rb_cString &&
             RBASIC_CLASS(obj) == rb_cString &&
             BASIC_OP_UNREDEFINED_P(BOP_PLUS, STRING_REDEFINED_OP_FLAG)) {
        return rb_str_opt_plus(recv, obj);
    }
    else if (RBASIC_CLASS(recv) == rb_cArray &&
             RBASIC_CLASS(obj) == rb_cArray &&
             BASIC_OP_UNREDEFINED_P(BOP_PLUS, ARRAY_REDEFINED_OP_FLAG)) {
        return rb_ary_plus(recv, obj);
    }
    else {
        return Qundef;
    }
}

static VALUE
vm_opt_minus(VALUE recv, VALUE obj)
{
    if (FIXNUM_2_P(recv, obj) &&
        BASIC_OP_UNREDEFINED_P(BOP_MINUS, INTEGER_REDEFINED_OP_FLAG)) {
        return rb_fix_minus_fix(recv, obj);
    }
    else if (FLONUM_2_P(recv, obj) &&
             BASIC_OP_UNREDEFINED_P(BOP_MINUS, FLOAT_REDEFINED_OP_FLAG)) {
        return DBL2NUM(RFLOAT_VALUE(recv) - RFLOAT_VALUE(obj));
    }
    else if (SPECIAL_CONST_P(recv) || SPECIAL_CONST_P(obj)) {
        return Qundef;
    }
    else if (RBASIC_CLASS(recv) == rb_cFloat &&
             RBASIC_CLASS(obj)  == rb_cFloat &&
             BASIC_OP_UNREDEFINED_P(BOP_MINUS, FLOAT_REDEFINED_OP_FLAG)) {
        return DBL2NUM(RFLOAT_VALUE(recv) - RFLOAT_VALUE(obj));
    }
    else {
        return Qundef;
    }
}

static VALUE
vm_opt_mult(VALUE recv, VALUE obj)
{
    if (FIXNUM_2_P(recv, obj) &&
        BASIC_OP_UNREDEFINED_P(BOP_MULT, INTEGER_REDEFINED_OP_FLAG)) {
        return rb_fix_mul_fix(recv, obj);
    }
    else if (FLONUM_2_P(recv, obj) &&
             BASIC_OP_UNREDEFINED_P(BOP_MULT, FLOAT_REDEFINED_OP_FLAG)) {
        return DBL2NUM(RFLOAT_VALUE(recv) * RFLOAT_VALUE(obj));
    }
    else if (SPECIAL_CONST_P(recv) || SPECIAL_CONST_P(obj)) {
        return Qundef;
    }
    else if (RBASIC_CLASS(recv) == rb_cFloat &&
             RBASIC_CLASS(obj)  == rb_cFloat &&
             BASIC_OP_UNREDEFINED_P(BOP_MULT, FLOAT_REDEFINED_OP_FLAG)) {
        return DBL2NUM(RFLOAT_VALUE(recv) * RFLOAT_VALUE(obj));
    }
    else {
        return Qundef;
    }
}

static VALUE
vm_opt_div(VALUE recv, VALUE obj)
{
    if (FIXNUM_2_P(recv, obj) &&
        BASIC_OP_UNREDEFINED_P(BOP_DIV, INTEGER_REDEFINED_OP_FLAG)) {
        return (FIX2LONG(obj) == 0) ? Qundef : rb_fix_div_fix(recv, obj);
    }
    else if (FLONUM_2_P(recv, obj) &&
             BASIC_OP_UNREDEFINED_P(BOP_DIV, FLOAT_REDEFINED_OP_FLAG)) {
        return rb_flo_div_flo(recv, obj);
    }
    else if (SPECIAL_CONST_P(recv) || SPECIAL_CONST_P(obj)) {
        return Qundef;
    }
    else if (RBASIC_CLASS(recv) == rb_cFloat &&
             RBASIC_CLASS(obj)  == rb_cFloat &&
             BASIC_OP_UNREDEFINED_P(BOP_DIV, FLOAT_REDEFINED_OP_FLAG)) {
        return rb_flo_div_flo(recv, obj);
    }
    else {
        return Qundef;
    }
}

static VALUE
vm_opt_mod(VALUE recv, VALUE obj)
{
    if (FIXNUM_2_P(recv, obj) &&
        BASIC_OP_UNREDEFINED_P(BOP_MOD, INTEGER_REDEFINED_OP_FLAG)) {
        return (FIX2LONG(obj) == 0) ? Qundef : rb_fix_mod_fix(recv, obj);
    }
    else if (FLONUM_2_P(recv, obj) &&
             BASIC_OP_UNREDEFINED_P(BOP_MOD, FLOAT_REDEFINED_OP_FLAG)) {
        return DBL2NUM(ruby_float_mod(RFLOAT_VALUE(recv), RFLOAT_VALUE(obj)));
    }
    else if (SPECIAL_CONST_P(recv) || SPECIAL_CONST_P(obj)) {
        return Qundef;
    }
    else if (RBASIC_CLASS(recv) == rb_cFloat &&
             RBASIC_CLASS(obj)  == rb_cFloat &&
             BASIC_OP_UNREDEFINED_P(BOP_MOD, FLOAT_REDEFINED_OP_FLAG)) {
        return DBL2NUM(ruby_float_mod(RFLOAT_VALUE(recv), RFLOAT_VALUE(obj)));
    }
    else {
        return Qundef;
    }
}

static VALUE
vm_opt_neq(const rb_iseq_t *iseq, CALL_DATA cd, CALL_DATA cd_eq, VALUE recv, VALUE obj)
{
    if (vm_method_cfunc_is(iseq, cd, recv, rb_obj_not_equal)) {
        VALUE val = opt_equality(iseq, recv, obj, cd_eq);

        if (!UNDEF_P(val)) {
            return RBOOL(!RTEST(val));
        }
    }

    return Qundef;
}

static VALUE
vm_opt_lt(VALUE recv, VALUE obj)
{
    if (FIXNUM_2_P(recv, obj) &&
        BASIC_OP_UNREDEFINED_P(BOP_LT, INTEGER_REDEFINED_OP_FLAG)) {
        return RBOOL((SIGNED_VALUE)recv < (SIGNED_VALUE)obj);
    }
    else if (FLONUM_2_P(recv, obj) &&
             BASIC_OP_UNREDEFINED_P(BOP_LT, FLOAT_REDEFINED_OP_FLAG)) {
        return RBOOL(RFLOAT_VALUE(recv) < RFLOAT_VALUE(obj));
    }
    else if (SPECIAL_CONST_P(recv) || SPECIAL_CONST_P(obj)) {
        return Qundef;
    }
    else if (RBASIC_CLASS(recv) == rb_cFloat &&
             RBASIC_CLASS(obj)  == rb_cFloat &&
             BASIC_OP_UNREDEFINED_P(BOP_LT, FLOAT_REDEFINED_OP_FLAG)) {
        CHECK_CMP_NAN(RFLOAT_VALUE(recv), RFLOAT_VALUE(obj));
        return RBOOL(RFLOAT_VALUE(recv) < RFLOAT_VALUE(obj));
    }
    else {
        return Qundef;
    }
}

static VALUE
vm_opt_le(VALUE recv, VALUE obj)
{
    if (FIXNUM_2_P(recv, obj) &&
        BASIC_OP_UNREDEFINED_P(BOP_LE, INTEGER_REDEFINED_OP_FLAG)) {
        return RBOOL((SIGNED_VALUE)recv <= (SIGNED_VALUE)obj);
    }
    else if (FLONUM_2_P(recv, obj) &&
             BASIC_OP_UNREDEFINED_P(BOP_LE, FLOAT_REDEFINED_OP_FLAG)) {
        return RBOOL(RFLOAT_VALUE(recv) <= RFLOAT_VALUE(obj));
    }
    else if (SPECIAL_CONST_P(recv) || SPECIAL_CONST_P(obj)) {
        return Qundef;
    }
    else if (RBASIC_CLASS(recv) == rb_cFloat &&
             RBASIC_CLASS(obj)  == rb_cFloat &&
             BASIC_OP_UNREDEFINED_P(BOP_LE, FLOAT_REDEFINED_OP_FLAG)) {
        CHECK_CMP_NAN(RFLOAT_VALUE(recv), RFLOAT_VALUE(obj));
        return RBOOL(RFLOAT_VALUE(recv) <= RFLOAT_VALUE(obj));
    }
    else {
        return Qundef;
    }
}

static VALUE
vm_opt_gt(VALUE recv, VALUE obj)
{
    if (FIXNUM_2_P(recv, obj) &&
        BASIC_OP_UNREDEFINED_P(BOP_GT, INTEGER_REDEFINED_OP_FLAG)) {
        return RBOOL((SIGNED_VALUE)recv > (SIGNED_VALUE)obj);
    }
    else if (FLONUM_2_P(recv, obj) &&
             BASIC_OP_UNREDEFINED_P(BOP_GT, FLOAT_REDEFINED_OP_FLAG)) {
        return RBOOL(RFLOAT_VALUE(recv) > RFLOAT_VALUE(obj));
    }
    else if (SPECIAL_CONST_P(recv) || SPECIAL_CONST_P(obj)) {
        return Qundef;
    }
    else if (RBASIC_CLASS(recv) == rb_cFloat &&
             RBASIC_CLASS(obj)  == rb_cFloat &&
             BASIC_OP_UNREDEFINED_P(BOP_GT, FLOAT_REDEFINED_OP_FLAG)) {
        CHECK_CMP_NAN(RFLOAT_VALUE(recv), RFLOAT_VALUE(obj));
        return RBOOL(RFLOAT_VALUE(recv) > RFLOAT_VALUE(obj));
    }
    else {
        return Qundef;
    }
}

static VALUE
vm_opt_ge(VALUE recv, VALUE obj)
{
    if (FIXNUM_2_P(recv, obj) &&
        BASIC_OP_UNREDEFINED_P(BOP_GE, INTEGER_REDEFINED_OP_FLAG)) {
        return RBOOL((SIGNED_VALUE)recv >= (SIGNED_VALUE)obj);
    }
    else if (FLONUM_2_P(recv, obj) &&
             BASIC_OP_UNREDEFINED_P(BOP_GE, FLOAT_REDEFINED_OP_FLAG)) {
        return RBOOL(RFLOAT_VALUE(recv) >= RFLOAT_VALUE(obj));
    }
    else if (SPECIAL_CONST_P(recv) || SPECIAL_CONST_P(obj)) {
        return Qundef;
    }
    else if (RBASIC_CLASS(recv) == rb_cFloat &&
             RBASIC_CLASS(obj)  == rb_cFloat &&
             BASIC_OP_UNREDEFINED_P(BOP_GE, FLOAT_REDEFINED_OP_FLAG)) {
        CHECK_CMP_NAN(RFLOAT_VALUE(recv), RFLOAT_VALUE(obj));
        return RBOOL(RFLOAT_VALUE(recv) >= RFLOAT_VALUE(obj));
    }
    else {
        return Qundef;
    }
}


static VALUE
vm_opt_ltlt(VALUE recv, VALUE obj)
{
    if (SPECIAL_CONST_P(recv)) {
        return Qundef;
    }
    else if (RBASIC_CLASS(recv) == rb_cString &&
             BASIC_OP_UNREDEFINED_P(BOP_LTLT, STRING_REDEFINED_OP_FLAG)) {
        if (LIKELY(RB_TYPE_P(obj, T_STRING))) {
            return rb_str_buf_append(recv, obj);
        }
        else {
            return rb_str_concat(recv, obj);
        }
    }
    else if (RBASIC_CLASS(recv) == rb_cArray &&
             BASIC_OP_UNREDEFINED_P(BOP_LTLT, ARRAY_REDEFINED_OP_FLAG)) {
        return rb_ary_push(recv, obj);
    }
    else {
        return Qundef;
    }
}

static VALUE
vm_opt_and(VALUE recv, VALUE obj)
{
    // If recv and obj are both fixnums, then the bottom tag bit
    // will be 1 on both.  1 & 1 == 1, so the result value will also
    // be a fixnum.  If either side is *not* a fixnum, then the tag bit
    // will be 0, and we return Qundef.
    VALUE ret = ((SIGNED_VALUE) recv) & ((SIGNED_VALUE) obj);

    if (FIXNUM_P(ret) &&
        BASIC_OP_UNREDEFINED_P(BOP_AND, INTEGER_REDEFINED_OP_FLAG)) {
        return ret;
    }
    else {
        return Qundef;
    }
}

static VALUE
vm_opt_or(VALUE recv, VALUE obj)
{
    if (FIXNUM_2_P(recv, obj) &&
        BASIC_OP_UNREDEFINED_P(BOP_OR, INTEGER_REDEFINED_OP_FLAG)) {
        return recv | obj;
    }
    else {
        return Qundef;
    }
}

static VALUE
vm_opt_aref(VALUE recv, VALUE obj)
{
    if (SPECIAL_CONST_P(recv)) {
        if (FIXNUM_2_P(recv, obj) &&
                BASIC_OP_UNREDEFINED_P(BOP_AREF, INTEGER_REDEFINED_OP_FLAG)) {
            return rb_fix_aref(recv, obj);
        }
        return Qundef;
    }
    else if (RBASIC_CLASS(recv) == rb_cArray &&
             BASIC_OP_UNREDEFINED_P(BOP_AREF, ARRAY_REDEFINED_OP_FLAG)) {
        if (FIXNUM_P(obj)) {
            return rb_ary_entry_internal(recv, FIX2LONG(obj));
        }
        else {
            return rb_ary_aref1(recv, obj);
        }
    }
    else if (RBASIC_CLASS(recv) == rb_cHash &&
             BASIC_OP_UNREDEFINED_P(BOP_AREF, HASH_REDEFINED_OP_FLAG)) {
        return rb_hash_aref(recv, obj);
    }
    else {
        return Qundef;
    }
}

static VALUE
vm_opt_aset(VALUE recv, VALUE obj, VALUE set)
{
    if (SPECIAL_CONST_P(recv)) {
        return Qundef;
    }
    else if (RBASIC_CLASS(recv) == rb_cArray &&
             BASIC_OP_UNREDEFINED_P(BOP_ASET, ARRAY_REDEFINED_OP_FLAG) &&
             FIXNUM_P(obj)) {
        rb_ary_store(recv, FIX2LONG(obj), set);
        return set;
    }
    else if (RBASIC_CLASS(recv) == rb_cHash &&
             BASIC_OP_UNREDEFINED_P(BOP_ASET, HASH_REDEFINED_OP_FLAG)) {
        rb_hash_aset(recv, obj, set);
        return set;
    }
    else {
        return Qundef;
    }
}

static VALUE
vm_opt_aref_with(VALUE recv, VALUE key)
{
    if (!SPECIAL_CONST_P(recv) && RBASIC_CLASS(recv) == rb_cHash &&
        BASIC_OP_UNREDEFINED_P(BOP_AREF, HASH_REDEFINED_OP_FLAG) &&
        rb_hash_compare_by_id_p(recv) == Qfalse &&
        !FL_TEST(recv, RHASH_PROC_DEFAULT)) {
        return rb_hash_aref(recv, key);
    }
    else {
        return Qundef;
    }
}

VALUE
rb_vm_opt_aref_with(VALUE recv, VALUE key)
{
    return vm_opt_aref_with(recv, key);
}

static VALUE
vm_opt_aset_with(VALUE recv, VALUE key, VALUE val)
{
    if (!SPECIAL_CONST_P(recv) && RBASIC_CLASS(recv) == rb_cHash &&
        BASIC_OP_UNREDEFINED_P(BOP_ASET, HASH_REDEFINED_OP_FLAG) &&
        rb_hash_compare_by_id_p(recv) == Qfalse) {
        return rb_hash_aset(recv, key, val);
    }
    else {
        return Qundef;
    }
}

static VALUE
vm_opt_length(VALUE recv, int bop)
{
    if (SPECIAL_CONST_P(recv)) {
        return Qundef;
    }
    else if (RBASIC_CLASS(recv) == rb_cString &&
             BASIC_OP_UNREDEFINED_P(bop, STRING_REDEFINED_OP_FLAG)) {
        if (bop == BOP_EMPTY_P) {
            return LONG2NUM(RSTRING_LEN(recv));
        }
        else {
            return rb_str_length(recv);
        }
    }
    else if (RBASIC_CLASS(recv) == rb_cArray &&
             BASIC_OP_UNREDEFINED_P(bop, ARRAY_REDEFINED_OP_FLAG)) {
        return LONG2NUM(RARRAY_LEN(recv));
    }
    else if (RBASIC_CLASS(recv) == rb_cHash &&
             BASIC_OP_UNREDEFINED_P(bop, HASH_REDEFINED_OP_FLAG)) {
        return INT2FIX(RHASH_SIZE(recv));
    }
    else {
        return Qundef;
    }
}

static VALUE
vm_opt_empty_p(VALUE recv)
{
    switch (vm_opt_length(recv, BOP_EMPTY_P)) {
      case Qundef: return Qundef;
      case INT2FIX(0): return Qtrue;
      default: return Qfalse;
    }
}

VALUE rb_false(VALUE obj);

static VALUE
vm_opt_nil_p(const rb_iseq_t *iseq, CALL_DATA cd, VALUE recv)
{
    if (NIL_P(recv) &&
        BASIC_OP_UNREDEFINED_P(BOP_NIL_P, NIL_REDEFINED_OP_FLAG)) {
        return Qtrue;
    }
    else if (vm_method_cfunc_is(iseq, cd, recv, rb_false)) {
        return Qfalse;
    }
    else {
        return Qundef;
    }
}

static VALUE
fix_succ(VALUE x)
{
    switch (x) {
      case ~0UL:
        /* 0xFFFF_FFFF == INT2FIX(-1)
         * `-1.succ` is of course 0. */
        return INT2FIX(0);
      case RSHIFT(~0UL, 1):
        /* 0x7FFF_FFFF == LONG2FIX(0x3FFF_FFFF)
         * 0x3FFF_FFFF + 1 == 0x4000_0000, which is a Bignum. */
        return rb_uint2big(1UL << (SIZEOF_LONG * CHAR_BIT - 2));
      default:
        /*    LONG2FIX(FIX2LONG(x)+FIX2LONG(y))
         * == ((lx*2+1)/2 + (ly*2+1)/2)*2+1
         * == lx*2 + ly*2 + 1
         * == (lx*2+1) + (ly*2+1) - 1
         * == x + y - 1
         *
         * Here, if we put y := INT2FIX(1):
         *
         * == x + INT2FIX(1) - 1
         * == x + 2 .
         */
        return x + 2;
    }
}

static VALUE
vm_opt_succ(VALUE recv)
{
    if (FIXNUM_P(recv) &&
        BASIC_OP_UNREDEFINED_P(BOP_SUCC, INTEGER_REDEFINED_OP_FLAG)) {
        return fix_succ(recv);
    }
    else if (SPECIAL_CONST_P(recv)) {
        return Qundef;
    }
    else if (RBASIC_CLASS(recv) == rb_cString &&
             BASIC_OP_UNREDEFINED_P(BOP_SUCC, STRING_REDEFINED_OP_FLAG)) {
        return rb_str_succ(recv);
    }
    else {
        return Qundef;
    }
}

static VALUE
vm_opt_not(const rb_iseq_t *iseq, CALL_DATA cd, VALUE recv)
{
    if (vm_method_cfunc_is(iseq, cd, recv, rb_obj_not)) {
        return RBOOL(!RTEST(recv));
    }
    else {
        return Qundef;
    }
}

static VALUE
vm_opt_regexpmatch2(VALUE recv, VALUE obj)
{
    if (SPECIAL_CONST_P(recv)) {
        return Qundef;
    }
    else if (RBASIC_CLASS(recv) == rb_cString &&
        CLASS_OF(obj) == rb_cRegexp &&
        BASIC_OP_UNREDEFINED_P(BOP_MATCH, STRING_REDEFINED_OP_FLAG)) {
        return rb_reg_match(obj, recv);
    }
    else if (RBASIC_CLASS(recv) == rb_cRegexp &&
        BASIC_OP_UNREDEFINED_P(BOP_MATCH, REGEXP_REDEFINED_OP_FLAG)) {
        return rb_reg_match(recv, obj);
    }
    else {
        return Qundef;
    }
}

rb_event_flag_t rb_iseq_event_flags(const rb_iseq_t *iseq, size_t pos);

NOINLINE(static void vm_trace(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp));

static inline void
vm_trace_hook(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, const VALUE *pc,
              rb_event_flag_t pc_events, rb_event_flag_t target_event,
              rb_hook_list_t *global_hooks, rb_hook_list_t *const *local_hooks_ptr, VALUE val)
{
    rb_event_flag_t event = pc_events & target_event;
    VALUE self = GET_SELF();

    VM_ASSERT(rb_popcount64((uint64_t)event) == 1);

    if (event & global_hooks->events) {
        /* increment PC because source line is calculated with PC-1 */
        reg_cfp->pc++;
        vm_dtrace(event, ec);
        rb_exec_event_hook_orig(ec, global_hooks, event, self, 0, 0, 0 , val, 0);
        reg_cfp->pc--;
    }

    // Load here since global hook above can add and free local hooks
    rb_hook_list_t *local_hooks = *local_hooks_ptr;
    if (local_hooks != NULL) {
        if (event & local_hooks->events) {
            /* increment PC because source line is calculated with PC-1 */
            reg_cfp->pc++;
            rb_exec_event_hook_orig(ec, local_hooks, event, self, 0, 0, 0 , val, 0);
            reg_cfp->pc--;
        }
    }
}

#define VM_TRACE_HOOK(target_event, val) do { \
    if ((pc_events & (target_event)) & enabled_flags) { \
        vm_trace_hook(ec, reg_cfp, pc, pc_events, (target_event), global_hooks, local_hooks_ptr, (val)); \
    } \
} while (0)

static VALUE
rescue_errinfo(rb_execution_context_t *ec, rb_control_frame_t *cfp)
{
    VM_ASSERT(VM_FRAME_RUBYFRAME_P(cfp));
    VM_ASSERT(ISEQ_BODY(cfp->iseq)->type == ISEQ_TYPE_RESCUE);
    return cfp->ep[VM_ENV_INDEX_LAST_LVAR];
}

static void
vm_trace(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp)
{
    const VALUE *pc = reg_cfp->pc;
    rb_event_flag_t enabled_flags = ruby_vm_event_flags & ISEQ_TRACE_EVENTS;
    rb_event_flag_t global_events = enabled_flags;

    if (enabled_flags == 0 && ruby_vm_event_local_num == 0) {
        return;
    }
    else {
        const rb_iseq_t *iseq = reg_cfp->iseq;
        VALUE iseq_val = (VALUE)iseq;
        size_t pos = pc - ISEQ_BODY(iseq)->iseq_encoded;
        rb_event_flag_t pc_events = rb_iseq_event_flags(iseq, pos);
        rb_hook_list_t *local_hooks = iseq->aux.exec.local_hooks;
        rb_hook_list_t *const *local_hooks_ptr = &iseq->aux.exec.local_hooks;
        rb_event_flag_t iseq_local_events = local_hooks != NULL ? local_hooks->events : 0;
        rb_hook_list_t *bmethod_local_hooks = NULL;
        rb_hook_list_t **bmethod_local_hooks_ptr = NULL;
        rb_event_flag_t bmethod_local_events = 0;
        const bool bmethod_frame = VM_FRAME_BMETHOD_P(reg_cfp);
        enabled_flags |= iseq_local_events;

        VM_ASSERT((iseq_local_events & ~ISEQ_TRACE_EVENTS) == 0);

        if (bmethod_frame) {
            const rb_callable_method_entry_t *me = rb_vm_frame_method_entry(reg_cfp);
            VM_ASSERT(me->def->type == VM_METHOD_TYPE_BMETHOD);
            bmethod_local_hooks = me->def->body.bmethod.hooks;
            bmethod_local_hooks_ptr = &me->def->body.bmethod.hooks;
            if (bmethod_local_hooks) {
                bmethod_local_events = bmethod_local_hooks->events;
            }
        }


        if ((pc_events & enabled_flags) == 0 && !bmethod_frame) {
#if 0
            /* disable trace */
            /* TODO: incomplete */
            rb_iseq_trace_set(iseq, vm_event_flags & ISEQ_TRACE_EVENTS);
#else
            /* do not disable trace because of performance problem
             * (re-enable overhead)
             */
#endif
            return;
        }
        else if (ec->trace_arg != NULL) {
            /* already tracing */
            return;
        }
        else {
            rb_hook_list_t *global_hooks = rb_ec_ractor_hooks(ec);
            /* Note, not considering iseq local events here since the same
             * iseq could be used in multiple bmethods. */
            rb_event_flag_t bmethod_events = global_events | bmethod_local_events;

            if (0) {
                ruby_debug_printf("vm_trace>>%4d (%4x) - %s:%d %s\n",
                                  (int)pos,
                                  (int)pc_events,
                                  RSTRING_PTR(rb_iseq_path(iseq)),
                                  (int)rb_iseq_line_no(iseq, pos),
                                  RSTRING_PTR(rb_iseq_label(iseq)));
            }
            VM_ASSERT(reg_cfp->pc == pc);
            VM_ASSERT(pc_events != 0);

            /* check traces */
            if ((pc_events & RUBY_EVENT_B_CALL) && bmethod_frame && (bmethod_events & RUBY_EVENT_CALL)) {
                /* b_call instruction running as a method. Fire call event. */
                vm_trace_hook(ec, reg_cfp, pc, RUBY_EVENT_CALL, RUBY_EVENT_CALL, global_hooks, bmethod_local_hooks_ptr, Qundef);
            }
            VM_TRACE_HOOK(RUBY_EVENT_CLASS | RUBY_EVENT_CALL | RUBY_EVENT_B_CALL,   Qundef);
            VM_TRACE_HOOK(RUBY_EVENT_RESCUE,                                        rescue_errinfo(ec, reg_cfp));
            VM_TRACE_HOOK(RUBY_EVENT_LINE,                                          Qundef);
            VM_TRACE_HOOK(RUBY_EVENT_COVERAGE_LINE,                                 Qundef);
            VM_TRACE_HOOK(RUBY_EVENT_COVERAGE_BRANCH,                               Qundef);
            VM_TRACE_HOOK(RUBY_EVENT_END | RUBY_EVENT_RETURN | RUBY_EVENT_B_RETURN, TOPN(0));
            if ((pc_events & RUBY_EVENT_B_RETURN) && bmethod_frame && (bmethod_events & RUBY_EVENT_RETURN)) {
                /* b_return instruction running as a method. Fire return event. */
                vm_trace_hook(ec, reg_cfp, pc, RUBY_EVENT_RETURN, RUBY_EVENT_RETURN, global_hooks, bmethod_local_hooks_ptr, TOPN(0));
            }

            // Pin the iseq since `local_hooks_ptr` points inside the iseq's slot on the GC heap.
            // We need the pointer to stay valid in case compaction happens in a trace hook.
            //
            // Similar treatment is unnecessary for `bmethod_local_hooks_ptr` since
            // storage for `rb_method_definition_t` is not on the GC heap.
            RB_GC_GUARD(iseq_val);
        }
    }
}
#undef VM_TRACE_HOOK

#if VM_CHECK_MODE > 0
NORETURN( NOINLINE( COLDFUNC
void rb_vm_canary_is_found_dead(enum ruby_vminsn_type i, VALUE c)));

void
Init_vm_stack_canary(void)
{
    /* This has to be called _after_ our PRNG is properly set up. */
    int n = ruby_fill_random_bytes(&vm_stack_canary, sizeof vm_stack_canary, false);
    vm_stack_canary |= 0x01; // valid VALUE (Fixnum)

    vm_stack_canary_was_born = true;
    VM_ASSERT(n == 0);
}

void
rb_vm_canary_is_found_dead(enum ruby_vminsn_type i, VALUE c)
{
    /* Because a method has already been called, why not call
     * another one. */
    const char *insn = rb_insns_name(i);
    VALUE inspection = rb_inspect(c);
    const char *str  = StringValueCStr(inspection);

    rb_bug("dead canary found at %s: %s", insn, str);
}

#else
void Init_vm_stack_canary(void) { /* nothing to do */ }
#endif


/* a part of the following code is generated by this ruby script:

16.times{|i|
  typedef_args = (0...i).map{|j| "VALUE v#{j+1}"}.join(", ")
  typedef_args.prepend(", ") if i != 0
  call_args = (0...i).map{|j| "argv[#{j}]"}.join(", ")
  call_args.prepend(", ") if i != 0
  puts %Q{
static VALUE
builtin_invoker#{i}(rb_execution_context_t *ec, VALUE self, const VALUE *argv, rb_insn_func_t funcptr)
{
    typedef VALUE (*rb_invoke_funcptr#{i}_t)(rb_execution_context_t *ec, VALUE self#{typedef_args});
    return (*(rb_invoke_funcptr#{i}_t)funcptr)(ec, self#{call_args});
}}
}

puts
puts "static VALUE (* const cfunc_invokers[])(rb_execution_context_t *ec, VALUE self, const VALUE *argv, rb_insn_func_t funcptr) = {"
16.times{|i|
  puts "    builtin_invoker#{i},"
}
puts "};"
*/

static VALUE
builtin_invoker0(rb_execution_context_t *ec, VALUE self, const VALUE *argv, rb_insn_func_t funcptr)
{
    typedef VALUE (*rb_invoke_funcptr0_t)(rb_execution_context_t *ec, VALUE self);
    return (*(rb_invoke_funcptr0_t)funcptr)(ec, self);
}

static VALUE
builtin_invoker1(rb_execution_context_t *ec, VALUE self, const VALUE *argv, rb_insn_func_t funcptr)
{
    typedef VALUE (*rb_invoke_funcptr1_t)(rb_execution_context_t *ec, VALUE self, VALUE v1);
    return (*(rb_invoke_funcptr1_t)funcptr)(ec, self, argv[0]);
}

static VALUE
builtin_invoker2(rb_execution_context_t *ec, VALUE self, const VALUE *argv, rb_insn_func_t funcptr)
{
    typedef VALUE (*rb_invoke_funcptr2_t)(rb_execution_context_t *ec, VALUE self, VALUE v1, VALUE v2);
    return (*(rb_invoke_funcptr2_t)funcptr)(ec, self, argv[0], argv[1]);
}

static VALUE
builtin_invoker3(rb_execution_context_t *ec, VALUE self, const VALUE *argv, rb_insn_func_t funcptr)
{
    typedef VALUE (*rb_invoke_funcptr3_t)(rb_execution_context_t *ec, VALUE self, VALUE v1, VALUE v2, VALUE v3);
    return (*(rb_invoke_funcptr3_t)funcptr)(ec, self, argv[0], argv[1], argv[2]);
}

static VALUE
builtin_invoker4(rb_execution_context_t *ec, VALUE self, const VALUE *argv, rb_insn_func_t funcptr)
{
    typedef VALUE (*rb_invoke_funcptr4_t)(rb_execution_context_t *ec, VALUE self, VALUE v1, VALUE v2, VALUE v3, VALUE v4);
    return (*(rb_invoke_funcptr4_t)funcptr)(ec, self, argv[0], argv[1], argv[2], argv[3]);
}

static VALUE
builtin_invoker5(rb_execution_context_t *ec, VALUE self, const VALUE *argv, rb_insn_func_t funcptr)
{
    typedef VALUE (*rb_invoke_funcptr5_t)(rb_execution_context_t *ec, VALUE self, VALUE v1, VALUE v2, VALUE v3, VALUE v4, VALUE v5);
    return (*(rb_invoke_funcptr5_t)funcptr)(ec, self, argv[0], argv[1], argv[2], argv[3], argv[4]);
}

static VALUE
builtin_invoker6(rb_execution_context_t *ec, VALUE self, const VALUE *argv, rb_insn_func_t funcptr)
{
    typedef VALUE (*rb_invoke_funcptr6_t)(rb_execution_context_t *ec, VALUE self, VALUE v1, VALUE v2, VALUE v3, VALUE v4, VALUE v5, VALUE v6);
    return (*(rb_invoke_funcptr6_t)funcptr)(ec, self, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5]);
}

static VALUE
builtin_invoker7(rb_execution_context_t *ec, VALUE self, const VALUE *argv, rb_insn_func_t funcptr)
{
    typedef VALUE (*rb_invoke_funcptr7_t)(rb_execution_context_t *ec, VALUE self, VALUE v1, VALUE v2, VALUE v3, VALUE v4, VALUE v5, VALUE v6, VALUE v7);
    return (*(rb_invoke_funcptr7_t)funcptr)(ec, self, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6]);
}

static VALUE
builtin_invoker8(rb_execution_context_t *ec, VALUE self, const VALUE *argv, rb_insn_func_t funcptr)
{
    typedef VALUE (*rb_invoke_funcptr8_t)(rb_execution_context_t *ec, VALUE self, VALUE v1, VALUE v2, VALUE v3, VALUE v4, VALUE v5, VALUE v6, VALUE v7, VALUE v8);
    return (*(rb_invoke_funcptr8_t)funcptr)(ec, self, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7]);
}

static VALUE
builtin_invoker9(rb_execution_context_t *ec, VALUE self, const VALUE *argv, rb_insn_func_t funcptr)
{
    typedef VALUE (*rb_invoke_funcptr9_t)(rb_execution_context_t *ec, VALUE self, VALUE v1, VALUE v2, VALUE v3, VALUE v4, VALUE v5, VALUE v6, VALUE v7, VALUE v8, VALUE v9);
    return (*(rb_invoke_funcptr9_t)funcptr)(ec, self, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8]);
}

static VALUE
builtin_invoker10(rb_execution_context_t *ec, VALUE self, const VALUE *argv, rb_insn_func_t funcptr)
{
    typedef VALUE (*rb_invoke_funcptr10_t)(rb_execution_context_t *ec, VALUE self, VALUE v1, VALUE v2, VALUE v3, VALUE v4, VALUE v5, VALUE v6, VALUE v7, VALUE v8, VALUE v9, VALUE v10);
    return (*(rb_invoke_funcptr10_t)funcptr)(ec, self, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9]);
}

static VALUE
builtin_invoker11(rb_execution_context_t *ec, VALUE self, const VALUE *argv, rb_insn_func_t funcptr)
{
    typedef VALUE (*rb_invoke_funcptr11_t)(rb_execution_context_t *ec, VALUE self, VALUE v1, VALUE v2, VALUE v3, VALUE v4, VALUE v5, VALUE v6, VALUE v7, VALUE v8, VALUE v9, VALUE v10, VALUE v11);
    return (*(rb_invoke_funcptr11_t)funcptr)(ec, self, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10]);
}

static VALUE
builtin_invoker12(rb_execution_context_t *ec, VALUE self, const VALUE *argv, rb_insn_func_t funcptr)
{
    typedef VALUE (*rb_invoke_funcptr12_t)(rb_execution_context_t *ec, VALUE self, VALUE v1, VALUE v2, VALUE v3, VALUE v4, VALUE v5, VALUE v6, VALUE v7, VALUE v8, VALUE v9, VALUE v10, VALUE v11, VALUE v12);
    return (*(rb_invoke_funcptr12_t)funcptr)(ec, self, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10], argv[11]);
}

static VALUE
builtin_invoker13(rb_execution_context_t *ec, VALUE self, const VALUE *argv, rb_insn_func_t funcptr)
{
    typedef VALUE (*rb_invoke_funcptr13_t)(rb_execution_context_t *ec, VALUE self, VALUE v1, VALUE v2, VALUE v3, VALUE v4, VALUE v5, VALUE v6, VALUE v7, VALUE v8, VALUE v9, VALUE v10, VALUE v11, VALUE v12, VALUE v13);
    return (*(rb_invoke_funcptr13_t)funcptr)(ec, self, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10], argv[11], argv[12]);
}

static VALUE
builtin_invoker14(rb_execution_context_t *ec, VALUE self, const VALUE *argv, rb_insn_func_t funcptr)
{
    typedef VALUE (*rb_invoke_funcptr14_t)(rb_execution_context_t *ec, VALUE self, VALUE v1, VALUE v2, VALUE v3, VALUE v4, VALUE v5, VALUE v6, VALUE v7, VALUE v8, VALUE v9, VALUE v10, VALUE v11, VALUE v12, VALUE v13, VALUE v14);
    return (*(rb_invoke_funcptr14_t)funcptr)(ec, self, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10], argv[11], argv[12], argv[13]);
}

static VALUE
builtin_invoker15(rb_execution_context_t *ec, VALUE self, const VALUE *argv, rb_insn_func_t funcptr)
{
    typedef VALUE (*rb_invoke_funcptr15_t)(rb_execution_context_t *ec, VALUE self, VALUE v1, VALUE v2, VALUE v3, VALUE v4, VALUE v5, VALUE v6, VALUE v7, VALUE v8, VALUE v9, VALUE v10, VALUE v11, VALUE v12, VALUE v13, VALUE v14, VALUE v15);
    return (*(rb_invoke_funcptr15_t)funcptr)(ec, self, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10], argv[11], argv[12], argv[13], argv[14]);
}

typedef VALUE (*builtin_invoker)(rb_execution_context_t *ec, VALUE self, const VALUE *argv, rb_insn_func_t funcptr);

static builtin_invoker
lookup_builtin_invoker(int argc)
{
    static const builtin_invoker invokers[] = {
        builtin_invoker0,
        builtin_invoker1,
        builtin_invoker2,
        builtin_invoker3,
        builtin_invoker4,
        builtin_invoker5,
        builtin_invoker6,
        builtin_invoker7,
        builtin_invoker8,
        builtin_invoker9,
        builtin_invoker10,
        builtin_invoker11,
        builtin_invoker12,
        builtin_invoker13,
        builtin_invoker14,
        builtin_invoker15,
    };

    return invokers[argc];
}

static inline VALUE
invoke_bf(rb_execution_context_t *ec, rb_control_frame_t *reg_cfp, const struct rb_builtin_function* bf, const VALUE *argv)
{
    const bool canary_p = ISEQ_BODY(reg_cfp->iseq)->builtin_attrs & BUILTIN_ATTR_LEAF; // Verify an assumption of `Primitive.attr! :leaf`
    SETUP_CANARY(canary_p);
    VALUE ret = (*lookup_builtin_invoker(bf->argc))(ec, reg_cfp->self, argv, (rb_insn_func_t)bf->func_ptr);
    CHECK_CANARY(canary_p, BIN(invokebuiltin));
    return ret;
}

static VALUE
vm_invoke_builtin(rb_execution_context_t *ec, rb_control_frame_t *cfp, const struct rb_builtin_function* bf, const VALUE *argv)
{
    return invoke_bf(ec, cfp, bf, argv);
}

static VALUE
vm_invoke_builtin_delegate(rb_execution_context_t *ec, rb_control_frame_t *cfp, const struct rb_builtin_function *bf, unsigned int start_index)
{
    if (0) { // debug print
        fputs("vm_invoke_builtin_delegate: passing -> ", stderr);
        for (int i=0; i<bf->argc; i++) {
            ruby_debug_printf(":%s ", rb_id2name(ISEQ_BODY(cfp->iseq)->local_table[i+start_index]));
        }
        ruby_debug_printf("\n" "%s %s(%d):%p\n", RUBY_FUNCTION_NAME_STRING, bf->name, bf->argc, bf->func_ptr);
    }

    if (bf->argc == 0) {
        return invoke_bf(ec, cfp, bf, NULL);
    }
    else {
        const VALUE *argv = cfp->ep - ISEQ_BODY(cfp->iseq)->local_table_size - VM_ENV_DATA_SIZE + 1 + start_index;
        return invoke_bf(ec, cfp, bf, argv);
    }
}

// for __builtin_inline!()

VALUE
rb_vm_lvar_exposed(rb_execution_context_t *ec, int index)
{
    const rb_control_frame_t *cfp = ec->cfp;
    return cfp->ep[index];
}
