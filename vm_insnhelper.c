/**********************************************************************

  vm_insnhelper.c - instruction helper functions.

  $Author$

  Copyright (C) 2007 Koichi Sasada

**********************************************************************/

/* finish iseq array */
#include "insns.inc"
#include <math.h>
#include "constant.h"
#include "internal.h"
#include "probes.h"
#include "probes_helper.h"

/* control stack frame */

#ifndef INLINE
#define INLINE inline
#endif

static rb_control_frame_t *vm_get_ruby_level_caller_cfp(const rb_thread_t *th, const rb_control_frame_t *cfp);

VALUE
ruby_vm_special_exception_copy(VALUE exc)
{
    VALUE e = rb_obj_alloc(rb_class_real(RBASIC_CLASS(exc)));
    rb_obj_copy_ivar(e, exc);
    return e;
}

static void
vm_stackoverflow(void)
{
    rb_exc_raise(ruby_vm_special_exception_copy(sysstack_error));
}

#if VM_CHECK_MODE > 0
static int
callable_class_p(VALUE klass)
{
#if VM_CHECK_MODE >= 2
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
callable_method_entry_p(const rb_callable_method_entry_t *me)
{
    if (me == NULL || callable_class_p(me->defined_class)) {
	return TRUE;
    }
    else {
	return FALSE;
    }
}

static void
vm_check_frame_detail(VALUE type, int req_block, int req_me, int req_cref, VALUE specval, VALUE cref_or_me)
{
    int magic = (int)(type & VM_FRAME_MAGIC_MASK);
    enum imemo_type cref_or_me_type = imemo_none;

    if (RB_TYPE_P(cref_or_me, T_IMEMO)) {
	cref_or_me_type = imemo_type(cref_or_me);
    }
    if (type & VM_FRAME_FLAG_BMETHOD) {
	req_me = TRUE;
    }

    if (req_block && !VM_ENVVAL_BLOCK_PTR_P(specval)) {
	rb_bug("vm_push_frame: specval (%p) should be a block_ptr on %x frame", (void *)specval, magic);
    }
    if (!req_block && VM_ENVVAL_BLOCK_PTR_P(specval)) {
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
		if ((magic == VM_FRAME_MAGIC_LAMBDA || magic == VM_FRAME_MAGIC_IFUNC) && (cref_or_me_type == imemo_ment)) {
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
}

static void
vm_check_frame(VALUE type,
	       VALUE specval,
	       VALUE cref_or_me)
{
    int magic = (int)(type & VM_FRAME_MAGIC_MASK);

#define CHECK(magic, req_block, req_me, req_cref) case magic: vm_check_frame_detail(type, req_block, req_me, req_cref, specval, cref_or_me); break;
    switch (magic) {
	/*                           BLK    ME     CREF */
	CHECK(VM_FRAME_MAGIC_METHOD, TRUE,  TRUE,  FALSE);
	CHECK(VM_FRAME_MAGIC_CLASS,  TRUE,  FALSE, TRUE);
	CHECK(VM_FRAME_MAGIC_TOP,    TRUE,  FALSE, TRUE);
	CHECK(VM_FRAME_MAGIC_CFUNC,  TRUE,  TRUE,  FALSE);
	CHECK(VM_FRAME_MAGIC_BLOCK,  FALSE, FALSE, FALSE);
	CHECK(VM_FRAME_MAGIC_PROC,   FALSE, FALSE, FALSE);
	CHECK(VM_FRAME_MAGIC_IFUNC,  FALSE, FALSE, FALSE);
	CHECK(VM_FRAME_MAGIC_EVAL,   FALSE, FALSE, FALSE);
	CHECK(VM_FRAME_MAGIC_LAMBDA, FALSE, FALSE, FALSE);
	CHECK(VM_FRAME_MAGIC_RESCUE, FALSE, FALSE, FALSE);
	CHECK(VM_FRAME_MAGIC_DUMMY,  TRUE,  FALSE, FALSE);
      default:
	rb_bug("vm_push_frame: unknown type (%x)", magic);
    }
#undef CHECK
}
#else
#define vm_check_frame(a, b, c)
#endif /* VM_CHECK_MODE > 0 */

static inline rb_control_frame_t *
vm_push_frame(rb_thread_t *th,
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
    rb_control_frame_t *const cfp = th->cfp - 1;
    int i;

    vm_check_frame(type, specval, cref_or_me);
    VM_ASSERT(local_size >= 1);

    /* check stack overflow */
    CHECK_VM_STACK_OVERFLOW0(cfp, sp, local_size + stack_max);

    th->cfp = cfp;

    /* setup new frame */
    cfp->pc = (VALUE *)pc;
    cfp->iseq = (rb_iseq_t *)iseq;
    cfp->flag = type;
    cfp->self = self;
    cfp->block_iseq = NULL;
    cfp->proc = 0;

    /* setup vm value stack */

    /* initialize local variables */
    for (i=0; i < local_size - 1; i++) {
	*sp++ = Qnil;
    }

    /* set special val */
    *sp++ = cref_or_me; /* Qnil or T_IMEMO(cref) or T_IMEMO(ment) */
    *sp = specval;

    /* setup vm control frame stack */

    cfp->ep = sp;
    cfp->sp = sp + 1;

#if VM_DEBUG_BP_CHECK
    cfp->bp_check = sp + 1;
#endif

    if (VMDEBUG == 2) {
	SDR();
    }

    return cfp;
}

static inline void
vm_pop_frame(rb_thread_t *th)
{
    th->cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(th->cfp);

    if (VMDEBUG == 2) {
	SDR();
    }
}

/* method dispatch */
static inline VALUE
rb_arity_error_new(int argc, int min, int max)
{
    VALUE err_mess = 0;
    if (min == max) {
	err_mess = rb_sprintf("wrong number of arguments (given %d, expected %d)", argc, min);
    }
    else if (max == UNLIMITED_ARGUMENTS) {
	err_mess = rb_sprintf("wrong number of arguments (given %d, expected %d+)", argc, min);
    }
    else {
	err_mess = rb_sprintf("wrong number of arguments (given %d, expected %d..%d)", argc, min, max);
    }
    return rb_exc_new3(rb_eArgError, err_mess);
}

void
rb_error_arity(int argc, int min, int max)
{
    rb_exc_raise(rb_arity_error_new(argc, min, max));
}

/* svar */

static inline struct vm_svar **
lep_svar_place(rb_thread_t *th, const VALUE *lep)
{
    const VALUE *svar_place;

    if (lep && (th == NULL || th->root_lep != lep)) {
	svar_place = &lep[-1];
    }
    else {
	svar_place = &th->root_svar;
    }

#if VM_CHECK_MODE > 0
    {
	VALUE svar = *svar_place;

	if (svar != Qfalse) {
	    if (RB_TYPE_P((VALUE)svar, T_IMEMO)) {
		switch (imemo_type(svar)) {
		  case imemo_svar:
		  case imemo_cref:
		  case imemo_ment:
		    goto okay;
		  default:
		    break; /* fall through */
		}
	    }
	    rb_bug("lep_svar_place: unknown type: %s", rb_obj_info(svar));
	}
      okay:;
    }
#endif

    return (struct vm_svar **)svar_place;
}

static VALUE
lep_svar_get(rb_thread_t *th, const VALUE *lep, rb_num_t key)
{
    struct vm_svar ** const svar_place = lep_svar_place(th, lep);
    const struct vm_svar *const svar = *svar_place;

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
    return (struct vm_svar *)rb_imemo_new(imemo_svar, Qnil, Qnil, Qnil, obj);
}

static void
lep_svar_set(rb_thread_t *th, VALUE *lep, rb_num_t key, VALUE val)
{
    struct vm_svar **svar_place = lep_svar_place(th, lep);
    struct vm_svar *svar = *svar_place;

    if ((VALUE)svar == Qfalse || imemo_type((VALUE)svar) != imemo_svar) {
	svar = *svar_place = svar_new((VALUE)svar);
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
vm_getspecial(rb_thread_t *th, VALUE *lep, rb_num_t key, rb_num_t type)
{
    VALUE val;

    if (type == 0) {
	val = lep_svar_get(th, lep, key);
    }
    else {
	VALUE backref = lep_svar_get(th, lep, VM_SVAR_BACKREF);

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
    VALUE *ep = cfp->ep;
    rb_callable_method_entry_t *me;

    while (!VM_EP_LEP_P(ep)) {
	if ((me = check_method_entry(ep[-1], FALSE)) != NULL) return me;
	ep = VM_EP_PREV_EP(ep);
    }

    return check_method_entry(ep[-1], TRUE);
}

static rb_cref_t *
method_entry_cref(rb_callable_method_entry_t *me)
{
    switch (me->def->type) {
      case VM_METHOD_TYPE_ISEQ:
	return me->def->body.iseq.cref;
      default:
	return NULL;
    }
}

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

    while (!VM_EP_LEP_P(ep)) {
	if ((cref = check_cref(ep[-1], FALSE)) != NULL) return cref;
	ep = VM_EP_PREV_EP(ep);
    }

    return check_cref(ep[-1], TRUE);
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
    while (!VM_EP_LEP_P(ep)) {
	if (is_cref(ep[-1], FALSE)) return TRUE;
	ep = VM_EP_PREV_EP(ep);
    }
    return is_cref(ep[-1], TRUE);
}

static rb_cref_t *
cref_replace_with_duplicated_cref_each_frame(VALUE *vptr, int can_be_svar, VALUE parent)
{
    const VALUE v = *vptr;
    rb_cref_t *cref, *new_cref;

    if (RB_TYPE_P(v, T_IMEMO)) {
	switch (imemo_type(v)) {
	  case imemo_cref:
	    cref = (rb_cref_t *)v;
	    new_cref = vm_cref_dup(cref);
	    if (parent) {
		/* this pointer is in svar */
		RB_OBJ_WRITE(parent, vptr, new_cref);
	    }
	    else {
		*vptr = (VALUE)new_cref;
	    }
	    return (rb_cref_t *)new_cref;
	  case imemo_svar:
	    if (can_be_svar) {
		return cref_replace_with_duplicated_cref_each_frame((VALUE *)&((struct vm_svar *)v)->cref_or_me, FALSE, v);
	    }
	  case imemo_ment:
	    rb_bug("cref_replace_with_duplicated_cref_each_frame: unreachable");
	  default:
	    break;
	}
    }
    return FALSE;
}

static rb_cref_t *
vm_cref_replace_with_duplicated_cref(const VALUE *ep)
{
    if (vm_env_cref_by_cref(ep)) {
	rb_cref_t *cref;

	while (!VM_EP_LEP_P(ep)) {
	    if ((cref = cref_replace_with_duplicated_cref_each_frame((VALUE *)&ep[-1], FALSE, Qfalse)) != NULL) {
		return cref;
	    }
	    ep = VM_EP_PREV_EP(ep);
	}
	return cref_replace_with_duplicated_cref_each_frame((VALUE *)&ep[-1], TRUE, Qfalse);
    }
    else {
	rb_bug("vm_cref_dup: unreachable");
    }
}


static rb_cref_t *
rb_vm_get_cref(const VALUE *ep)
{
    rb_cref_t *cref = vm_env_cref(ep);

    if (cref != NULL) {
	return cref;
    }
    else {
	rb_bug("rb_vm_get_cref: unreachable");
    }
}

static const rb_cref_t *
vm_get_const_key_cref(const VALUE *ep)
{
    const rb_cref_t *cref = rb_vm_get_cref(ep);
    const rb_cref_t *key_cref = cref;

    while (cref) {
	if (FL_TEST(CREF_CLASS(cref), FL_SINGLETON)) {
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
	new_cref_ptr = (rb_cref_t **)&new_cref->next;
    }
    *new_cref_ptr = NULL;
}

static rb_cref_t *
vm_cref_push(rb_thread_t *th, VALUE klass, rb_block_t *blockptr, int pushed_by_eval)
{
    rb_cref_t *prev_cref = NULL;

    if (blockptr) {
	prev_cref = vm_env_cref(blockptr->ep);
    }
    else {
	rb_control_frame_t *cfp = vm_get_ruby_level_caller_cfp(th, th->cfp);

	if (cfp) {
	    prev_cref = vm_env_cref(cfp->ep);
	}
    }

    return vm_cref_new(klass, METHOD_VISI_PUBLIC, FALSE, prev_cref, pushed_by_eval);
}

static inline VALUE
vm_get_cbase(const VALUE *ep)
{
    const rb_cref_t *cref = rb_vm_get_cref(ep);
    VALUE klass = Qundef;

    while (cref) {
	if ((klass = CREF_CLASS(cref)) != 0) {
	    break;
	}
	cref = CREF_NEXT(cref);
    }

    return klass;
}

static inline VALUE
vm_get_const_base(const VALUE *ep)
{
    const rb_cref_t *cref = rb_vm_get_cref(ep);
    VALUE klass = Qundef;

    while (cref) {
	if (!CREF_PUSHED_BY_EVAL(cref) &&
	    (klass = CREF_CLASS(cref)) != 0) {
	    break;
	}
	cref = CREF_NEXT(cref);
    }

    return klass;
}

static inline void
vm_check_if_namespace(VALUE klass)
{
    VALUE str;
    if (!RB_TYPE_P(klass, T_CLASS) && !RB_TYPE_P(klass, T_MODULE)) {
	str = rb_inspect(klass);
	rb_raise(rb_eTypeError, "%s is not a class/module",
		 StringValuePtr(str));
    }
}

static inline VALUE
vm_get_iclass(rb_control_frame_t *cfp, VALUE klass)
{
    return klass;
}

static inline VALUE
vm_get_ev_const(rb_thread_t *th, VALUE orig_klass, ID id, int is_defined)
{
    void rb_const_warn_if_deprecated(const rb_const_entry_t *ce, VALUE klass, ID id);
    VALUE val;

    if (orig_klass == Qnil) {
	/* in current lexical scope */
	const rb_cref_t *root_cref = rb_vm_get_cref(th->cfp->ep);
	const rb_cref_t *cref;
	VALUE klass = orig_klass;

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
		    if (val == Qundef) {
			if (am == klass) break;
			am = klass;
			if (is_defined) return 1;
			if (rb_autoloading_value(klass, id, &av)) return av;
			rb_autoload_load(klass, id);
			goto search_continue;
		    }
		    else {
			if (is_defined) {
			    return 1;
			}
			else {
			    return val;
			}
		    }
		}
	    }
	}

	/* search self */
	if (root_cref && !NIL_P(CREF_CLASS(root_cref))) {
	    klass = vm_get_iclass(th->cfp, CREF_CLASS(root_cref));
	}
	else {
	    klass = CLASS_OF(th->cfp->self);
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

static inline VALUE
vm_get_cvar_base(const rb_cref_t *cref, rb_control_frame_t *cfp)
{
    VALUE klass;

    if (!cref) {
	rb_bug("vm_get_cvar_base: no cref");
    }

    while (CREF_NEXT(cref) &&
	   (NIL_P(CREF_CLASS(cref)) || FL_TEST(CREF_CLASS(cref), FL_SINGLETON) ||
	    CREF_PUSHED_BY_EVAL(cref))) {
	cref = CREF_NEXT(cref);
    }
    if (!CREF_NEXT(cref)) {
	rb_warn("class variable access from toplevel");
    }

    klass = vm_get_iclass(cfp, CREF_CLASS(cref));

    if (NIL_P(klass)) {
	rb_raise(rb_eTypeError, "no class variables available");
    }
    return klass;
}

static VALUE
vm_search_const_defined_class(const VALUE cbase, ID id)
{
    if (rb_const_defined_at(cbase, id)) return cbase;
    if (cbase == rb_cObject) {
	VALUE tmp = RCLASS_SUPER(cbase);
	while (tmp) {
	    if (rb_const_defined_at(tmp, id)) return tmp;
	    tmp = RCLASS_SUPER(tmp);
	}
    }
    return 0;
}

#ifndef USE_IC_FOR_IVAR
#define USE_IC_FOR_IVAR 1
#endif

static inline VALUE
vm_getivar(VALUE obj, ID id, IC ic, struct rb_call_cache *cc, int is_attr)
{
#if USE_IC_FOR_IVAR
    if (RB_TYPE_P(obj, T_OBJECT)) {
	VALUE val = Qundef;
	VALUE klass = RBASIC(obj)->klass;
	const long len = ROBJECT_NUMIV(obj);
	const VALUE *const ptr = ROBJECT_IVPTR(obj);

	if (LIKELY(is_attr ? cc->aux.index > 0 : ic->ic_serial == RCLASS_SERIAL(klass))) {
	    long index = !is_attr ? (long)ic->ic_value.index : (long)(cc->aux.index - 1);

	    if (index < len) {
		val = ptr[index];
	    }
	}
	else {
	    st_data_t index;
	    struct st_table *iv_index_tbl = ROBJECT_IV_INDEX_TBL(obj);

	    if (iv_index_tbl) {
		if (st_lookup(iv_index_tbl, id, &index)) {
		    if ((long)index < len) {
			val = ptr[index];
		    }
		    if (!is_attr) {
			ic->ic_value.index = index;
			ic->ic_serial = RCLASS_SERIAL(klass);
		    }
		    else { /* call_info */
			cc->aux.index = (int)index + 1;
		    }
		}
	    }
	}

	if (UNLIKELY(val == Qundef)) {
	    if (!is_attr && RTEST(ruby_verbose))
		rb_warning("instance variable %"PRIsVALUE" not initialized", QUOTE_ID(id));
	    val = Qnil;
	}
	return val;
    }
#endif	/* USE_IC_FOR_IVAR */
    if (is_attr)
	return rb_attr_get(obj, id);
    return rb_ivar_get(obj, id);
}

static inline VALUE
vm_setivar(VALUE obj, ID id, VALUE val, IC ic, struct rb_call_cache *cc, int is_attr)
{
#if USE_IC_FOR_IVAR
    rb_check_frozen(obj);

    if (RB_TYPE_P(obj, T_OBJECT)) {
	VALUE klass = RBASIC(obj)->klass;
	st_data_t index;

	if (LIKELY(
	    (!is_attr && ic->ic_serial == RCLASS_SERIAL(klass)) ||
	    (is_attr && cc->aux.index > 0))) {
	    long index = !is_attr ? (long)ic->ic_value.index : (long)cc->aux.index-1;
	    long len = ROBJECT_NUMIV(obj);
	    VALUE *ptr = ROBJECT_IVPTR(obj);

	    if (index < len) {
		RB_OBJ_WRITE(obj, &ptr[index], val);
		return val; /* inline cache hit */
	    }
	}
	else {
	    struct st_table *iv_index_tbl = ROBJECT_IV_INDEX_TBL(obj);

	    if (iv_index_tbl && st_lookup(iv_index_tbl, (st_data_t)id, &index)) {
		if (!is_attr) {
		    ic->ic_value.index = index;
		    ic->ic_serial = RCLASS_SERIAL(klass);
		}
		else if (index >= INT_MAX) {
		    rb_raise(rb_eArgError, "too many instance variables");
		}
		else {
		    cc->aux.index = (int)(index + 1);
		}
	    }
	    /* fall through */
	}
    }
#endif	/* USE_IC_FOR_IVAR */
    return rb_ivar_set(obj, id, val);
}

static VALUE
vm_getinstancevariable(VALUE obj, ID id, IC ic)
{
    return vm_getivar(obj, id, ic, 0, 0);
}

static void
vm_setinstancevariable(VALUE obj, ID id, VALUE val, IC ic)
{
    vm_setivar(obj, id, val, ic, 0, 0);
}

static VALUE
vm_throw_continue(rb_thread_t *th, VALUE err)
{
    /* continue throw */

    if (FIXNUM_P(err)) {
	th->state = FIX2INT(err);
    }
    else if (SYMBOL_P(err)) {
	th->state = TAG_THROW;
    }
    else if (THROW_DATA_P(err)) {
	th->state = THROW_DATA_STATE((struct vm_throw_data *)err);
    }
    else {
	th->state = TAG_RAISE;
	/*th->state = FIX2INT(rb_ivar_get(err, idThrowState));*/
    }
    return err;
}

static VALUE
vm_throw_start(rb_thread_t *const th, rb_control_frame_t *const reg_cfp, enum ruby_tag_type state,
	       const int flag, const rb_num_t level, const VALUE throwobj)
{
    rb_control_frame_t *escape_cfp = NULL;
    const rb_control_frame_t * const eocfp = RUBY_VM_END_CONTROL_FRAME(th); /* end of control frame pointer */

    if (flag != 0) {
	/* do nothing */
    }
    else if (state == TAG_BREAK) {
	int is_orphan = 1;
	VALUE *ep = GET_EP();
	const rb_iseq_t *base_iseq = GET_ISEQ();
	escape_cfp = reg_cfp;

	while (base_iseq->body->type != ISEQ_TYPE_BLOCK) {
	    if (escape_cfp->iseq->body->type == ISEQ_TYPE_CLASS) {
		escape_cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(escape_cfp);
		ep = escape_cfp->ep;
		base_iseq = escape_cfp->iseq;
	    }
	    else {
		ep = VM_EP_PREV_EP(ep);
		base_iseq = base_iseq->body->parent_iseq;
		escape_cfp = rb_vm_search_cf_from_ep(th, escape_cfp, ep);
		VM_ASSERT(escape_cfp->iseq == base_iseq);
	    }
	}

	if (VM_FRAME_TYPE(escape_cfp) == VM_FRAME_MAGIC_LAMBDA) {
	    /* lambda{... break ...} */
	    is_orphan = 0;
	    state = TAG_RETURN;
	}
	else {
	    ep = VM_EP_PREV_EP(ep);

	    while (escape_cfp < eocfp) {
		if (escape_cfp->ep == ep) {
		    const rb_iseq_t *const iseq = escape_cfp->iseq;
		    const VALUE epc = escape_cfp->pc - iseq->body->iseq_encoded;
		    const struct iseq_catch_table *const ct = iseq->body->catch_table;
		    unsigned int i;

		    if (!ct) break;
		    for (i=0; i < ct->size; i++) {
			const struct iseq_catch_table_entry * const entry = &ct->entries[i];;

			if (entry->type == CATCH_TYPE_BREAK && entry->start < epc && entry->end >= epc) {
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
	rb_num_t i;
	VALUE *ep = VM_EP_PREV_EP(GET_EP());

	for (i = 0; i < level; i++) {
	    ep = VM_EP_PREV_EP(ep);
	}

	escape_cfp = rb_vm_search_cf_from_ep(th, reg_cfp, ep);
    }
    else if (state == TAG_RETURN) {
	VALUE *current_ep = GET_EP();
	VALUE *target_lep = VM_EP_LEP(current_ep);
	int in_class_frame = 0;
	escape_cfp = reg_cfp;

	while (escape_cfp < eocfp) {
	    VALUE *lep = VM_CF_LEP(escape_cfp);

	    if (!target_lep) {
		target_lep = lep;
	    }

	    if (lep == target_lep &&
		RUBY_VM_NORMAL_ISEQ_P(escape_cfp->iseq) &&
		escape_cfp->iseq->body->type == ISEQ_TYPE_CLASS) {
		in_class_frame = 1;
		target_lep = 0;
	    }

	    if (lep == target_lep) {
		if (VM_FRAME_TYPE(escape_cfp) == VM_FRAME_MAGIC_LAMBDA) {
		    if (in_class_frame) {
			/* lambda {class A; ... return ...; end} */
			goto valid_return;
		    }
		    else {
			VALUE *tep = current_ep;

			while (target_lep != tep) {
			    if (escape_cfp->ep == tep) {
				/* in lambda */
				goto valid_return;
			    }
			    tep = VM_EP_PREV_EP(tep);
			}
		    }
		}
	    }

	    if (escape_cfp->ep == target_lep && escape_cfp->iseq->body->type == ISEQ_TYPE_METHOD) {
		goto valid_return;
	    }

	    escape_cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(escape_cfp);
	}
	rb_vm_localjump_error("unexpected return", throwobj, TAG_RETURN);

      valid_return:;
	/* do nothing */
    }
    else {
	rb_bug("isns(throw): unsupport throw type");
    }

    th->state = state;
    return (VALUE)THROW_DATA_NEW(throwobj, escape_cfp, state);
}

static VALUE
vm_throw(rb_thread_t *th, rb_control_frame_t *reg_cfp,
	 rb_num_t throw_state, VALUE throwobj)
{
    const int state = (int)(throw_state & VM_THROW_STATE_MASK);
    const int flag = (int)(throw_state & VM_THROW_NO_ESCAPE_FLAG);
    const rb_num_t level = throw_state >> VM_THROW_LEVEL_SHIFT;

    if (state != 0) {
	return vm_throw_start(th, reg_cfp, state, flag, level, throwobj);
    }
    else {
	return vm_throw_continue(th, throwobj);
    }
}

static inline void
vm_expandarray(rb_control_frame_t *cfp, VALUE ary, rb_num_t num, int flag)
{
    int is_splat = flag & 0x01;
    rb_num_t space_size = num + is_splat;
    VALUE *base = cfp->sp;
    const VALUE *ptr;
    rb_num_t len;

    if (!RB_TYPE_P(ary, T_ARRAY)) {
	ary = rb_ary_to_ary(ary);
    }

    cfp->sp += space_size;

    ptr = RARRAY_CONST_PTR(ary);
    len = (rb_num_t)RARRAY_LEN(ary);

    if (flag & 0x02) {
	/* post: ..., nil ,ary[-1], ..., ary[0..-num] # top */
	rb_num_t i = 0, j;

	if (len < num) {
	    for (i=0; i<num-len; i++) {
		*base++ = Qnil;
	    }
	}
	for (j=0; i<num; i++, j++) {
	    VALUE v = ptr[len - j - 1];
	    *base++ = v;
	}
	if (is_splat) {
	    *base = rb_ary_new4(len - j, ptr);
	}
    }
    else {
	/* normal: ary[num..-1], ary[num-2], ary[num-3], ..., ary[0] # top */
	rb_num_t i;
	VALUE *bptr = &base[space_size - 1];

	for (i=0; i<num; i++) {
	    if (len <= i) {
		for (; i<num; i++) {
		    *bptr-- = Qnil;
		}
		break;
	    }
	    *bptr-- = ptr[i];
	}
	if (is_splat) {
	    if (num > len) {
		*bptr = rb_ary_new();
	    }
	    else {
		*bptr = rb_ary_new4(len - num, ptr + num);
	    }
	}
    }
    RB_GC_GUARD(ary);
}

static VALUE vm_call_general(rb_thread_t *th, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc);

static void
vm_search_method(const struct rb_call_info *ci, struct rb_call_cache *cc, VALUE recv)
{
    VALUE klass = CLASS_OF(recv);

#if OPT_INLINE_METHOD_CACHE
    if (LIKELY(GET_GLOBAL_METHOD_STATE() == cc->method_state && RCLASS_SERIAL(klass) == cc->class_serial)) {
	/* cache hit! */
	return;
    }
#endif

    cc->me = rb_callable_method_entry(klass, ci->mid);
    VM_ASSERT(callable_method_entry_p(cc->me));
    cc->call = vm_call_general;
#if OPT_INLINE_METHOD_CACHE
    cc->method_state = GET_GLOBAL_METHOD_STATE();
    cc->class_serial = RCLASS_SERIAL(klass);
#endif
}

static inline int
check_cfunc(const rb_callable_method_entry_t *me, VALUE (*func)())
{
    if (me && me->def->type == VM_METHOD_TYPE_CFUNC &&
	me->def->body.cfunc.func == func) {
	return 1;
    }
    else {
	return 0;
    }
}

static
#ifndef NO_BIG_INLINE
inline
#endif
VALUE
opt_eq_func(VALUE recv, VALUE obj, CALL_INFO ci, CALL_CACHE cc)
{
    if (FIXNUM_2_P(recv, obj) &&
	BASIC_OP_UNREDEFINED_P(BOP_EQ, FIXNUM_REDEFINED_OP_FLAG)) {
	return (recv == obj) ? Qtrue : Qfalse;
    }
    else if (FLONUM_2_P(recv, obj) &&
	     BASIC_OP_UNREDEFINED_P(BOP_EQ, FLOAT_REDEFINED_OP_FLAG)) {
	return (recv == obj) ? Qtrue : Qfalse;
    }
    else if (!SPECIAL_CONST_P(recv) && !SPECIAL_CONST_P(obj)) {
	if (RBASIC_CLASS(recv) == rb_cFloat &&
	    RBASIC_CLASS(obj) == rb_cFloat &&
	    BASIC_OP_UNREDEFINED_P(BOP_EQ, FLOAT_REDEFINED_OP_FLAG)) {
	    double a = RFLOAT_VALUE(recv);
	    double b = RFLOAT_VALUE(obj);

	    if (isnan(a) || isnan(b)) {
		return Qfalse;
	    }
	    return  (a == b) ? Qtrue : Qfalse;
	}
	else if (RBASIC_CLASS(recv) == rb_cString &&
		 RBASIC_CLASS(obj) == rb_cString &&
		 BASIC_OP_UNREDEFINED_P(BOP_EQ, STRING_REDEFINED_OP_FLAG)) {
	    return rb_str_equal(recv, obj);
	}
    }

    {
	vm_search_method(ci, cc, recv);

	if (check_cfunc(cc->me, rb_obj_equal)) {
	    return recv == obj ? Qtrue : Qfalse;
	}
    }

    return Qundef;
}

VALUE
rb_equal_opt(VALUE obj1, VALUE obj2)
{
    struct rb_call_info ci;
    struct rb_call_cache cc;

    ci.mid = idEq;
    cc.method_state = 0;
    cc.class_serial = 0;
    cc.me = NULL;
    return opt_eq_func(obj1, obj2, &ci, &cc);
}

static VALUE vm_call0(rb_thread_t*, VALUE, ID, int, const VALUE*, const rb_callable_method_entry_t *);

static VALUE
check_match(VALUE pattern, VALUE target, enum vm_check_match_type type)
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
	const rb_callable_method_entry_t *me = rb_callable_method_entry_with_refinements(CLASS_OF(pattern), idEqq);
	if (me) {
	    return vm_call0(GET_THREAD(), pattern, idEqq, 1, &target, me);
	}
	else {
	    /* fallback to funcall (e.g. method_missing) */
	    return rb_funcall2(pattern, idEqq, 1, &target);
	}
      }
      default:
	rb_bug("check_match: unreachable");
    }
}


#if defined(_MSC_VER) && _MSC_VER < 1300
#define CHECK_CMP_NAN(a, b) if (isnan(a) || isnan(b)) return Qfalse;
#else
#define CHECK_CMP_NAN(a, b) /* do nothing */
#endif

static inline VALUE
double_cmp_lt(double a, double b)
{
    CHECK_CMP_NAN(a, b);
    return a < b ? Qtrue : Qfalse;
}

static inline VALUE
double_cmp_le(double a, double b)
{
    CHECK_CMP_NAN(a, b);
    return a <= b ? Qtrue : Qfalse;
}

static inline VALUE
double_cmp_gt(double a, double b)
{
    CHECK_CMP_NAN(a, b);
    return a > b ? Qtrue : Qfalse;
}

static inline VALUE
double_cmp_ge(double a, double b)
{
    CHECK_CMP_NAN(a, b);
    return a >= b ? Qtrue : Qfalse;
}

static VALUE *
vm_base_ptr(rb_control_frame_t *cfp)
{
    rb_control_frame_t *prev_cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
    VALUE *bp = prev_cfp->sp + cfp->iseq->body->local_size + 1;

    if (cfp->iseq->body->type == ISEQ_TYPE_METHOD) {
	/* adjust `self' */
	bp += 1;
    }

#if VM_DEBUG_BP_CHECK
    if (bp != cfp->bp_check) {
	fprintf(stderr, "bp_check: %ld, bp: %ld\n",
		(long)(cfp->bp_check - GET_THREAD()->stack),
		(long)(bp - GET_THREAD()->stack));
	rb_bug("vm_base_ptr: unreachable");
    }
#endif

    return bp;
}

/* method call processes with call_info */

#include "vm_args.c"

static inline VALUE vm_call_iseq_setup_2(rb_thread_t *th, rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc, int opt_pc, int param_size, int local_size);
static inline VALUE vm_call_iseq_setup_normal(rb_thread_t *th, rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc, int opt_pc, int param_size, int local_size);
static inline VALUE vm_call_iseq_setup_tailcall(rb_thread_t *th, rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc, int opt_pc);
static VALUE vm_call_super_method(rb_thread_t *th, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc);
static VALUE vm_call_method_nome(rb_thread_t *th, rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc);
static VALUE vm_call_method_each_type(rb_thread_t *th, rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc);
static inline VALUE vm_call_method(rb_thread_t *th, rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc);

static vm_call_handler vm_call_iseq_setup_func(const struct rb_call_info *ci, const int param_size, const int local_size);

static rb_method_definition_t *method_definition_create(rb_method_type_t type, ID mid);
static void method_definition_set(const rb_method_entry_t *me, rb_method_definition_t *def, void *opts);
static int rb_method_definition_eq(const rb_method_definition_t *d1, const rb_method_definition_t *d2);

static const rb_iseq_t *
def_iseq_ptr(rb_method_definition_t *def)
{
#if VM_CHECK_MODE > 0
    if (def->type != VM_METHOD_TYPE_ISEQ) rb_bug("def_iseq_ptr: not iseq (%d)", def->type);
#endif
    return rb_iseq_check(def->body.iseq.iseqptr);
}

static VALUE
vm_call_iseq_setup_tailcall_0start(rb_thread_t *th, rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc)
{
    return vm_call_iseq_setup_tailcall(th, cfp, calling, ci, cc, 0);
}

static VALUE
vm_call_iseq_setup_normal_0start(rb_thread_t *th, rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc)
{
    const rb_iseq_t *iseq = def_iseq_ptr(cc->me->def);
    int param = iseq->body->param.size;
    int local = iseq->body->local_size;
    return vm_call_iseq_setup_normal(th, cfp, calling, ci, cc, 0, param, local);
}

static inline int
simple_iseq_p(const rb_iseq_t *iseq)
{
    return iseq->body->param.flags.has_opt == FALSE &&
           iseq->body->param.flags.has_rest == FALSE &&
	   iseq->body->param.flags.has_post == FALSE &&
	   iseq->body->param.flags.has_kw == FALSE &&
	   iseq->body->param.flags.has_kwrest == FALSE &&
	   iseq->body->param.flags.has_block == FALSE;
}

static inline int
vm_callee_setup_arg(rb_thread_t *th, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc,
		    const rb_iseq_t *iseq, VALUE *argv, int param_size, int local_size)
{
    if (LIKELY(simple_iseq_p(iseq))) {
	rb_control_frame_t *cfp = th->cfp;

	CALLER_SETUP_ARG(cfp, calling, ci); /* splat arg */

	if (calling->argc != iseq->body->param.lead_num) {
	    argument_arity_error(th, iseq, calling->argc, iseq->body->param.lead_num, iseq->body->param.lead_num);
	}

	CI_SET_FASTPATH(cc, vm_call_iseq_setup_func(ci, param_size, local_size),
			(!IS_ARGS_SPLAT(ci) && !IS_ARGS_KEYWORD(ci) &&
			 !(METHOD_ENTRY_VISI(cc->me) == METHOD_VISI_PROTECTED)));
	return 0;
    }
    else {
	return setup_parameters_complex(th, iseq, calling, ci, argv, arg_setup_method);
    }
}

static VALUE
vm_call_iseq_setup(rb_thread_t *th, rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc)
{
    const rb_iseq_t *iseq = def_iseq_ptr(cc->me->def);
    const int param_size = iseq->body->param.size;
    const int local_size = iseq->body->local_size;
    const int opt_pc = vm_callee_setup_arg(th, calling, ci, cc, def_iseq_ptr(cc->me->def), cfp->sp - calling->argc, param_size, local_size);
    return vm_call_iseq_setup_2(th, cfp, calling, ci, cc, opt_pc, param_size, local_size);
}

static inline VALUE
vm_call_iseq_setup_2(rb_thread_t *th, rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc,
		     int opt_pc, int param_size, int local_size)
{
    if (LIKELY(!(ci->flag & VM_CALL_TAILCALL))) {
	return vm_call_iseq_setup_normal(th, cfp, calling, ci, cc, opt_pc, param_size, local_size);
    }
    else {
	return vm_call_iseq_setup_tailcall(th, cfp, calling, ci, cc, opt_pc);
    }
}

static inline VALUE
vm_call_iseq_setup_normal(rb_thread_t *th, rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc,
			  int opt_pc, int param_size, int local_size)
{
    const rb_callable_method_entry_t *me = cc->me;
    const rb_iseq_t *iseq = def_iseq_ptr(me->def);
    VALUE *argv = cfp->sp - calling->argc;
    VALUE *sp = argv + param_size;
    cfp->sp = argv - 1 /* recv */;

    vm_push_frame(th, iseq, VM_FRAME_MAGIC_METHOD, calling->recv,
		  VM_ENVVAL_BLOCK_PTR(calling->blockptr), (VALUE)me,
		  iseq->body->iseq_encoded + opt_pc, sp,
		  local_size - param_size,
		  iseq->body->stack_max);
    return Qundef;
}

static inline VALUE
vm_call_iseq_setup_tailcall(rb_thread_t *th, rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc,
			    int opt_pc)
{
    unsigned int i;
    VALUE *argv = cfp->sp - calling->argc;
    const rb_callable_method_entry_t *me = cc->me;
    const rb_iseq_t *iseq = def_iseq_ptr(me->def);
    VALUE *src_argv = argv;
    VALUE *sp_orig, *sp;
    VALUE finish_flag = VM_FRAME_TYPE_FINISH_P(cfp) ? VM_FRAME_FLAG_FINISH : 0;

    cfp = th->cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(th->cfp); /* pop cf */

    RUBY_VM_CHECK_INTS(th);

    sp_orig = sp = cfp->sp;

    /* push self */
    sp[0] = calling->recv;
    sp++;

    /* copy arguments */
    for (i=0; i < iseq->body->param.size; i++) {
	*sp++ = src_argv[i];
    }

    vm_push_frame(th, iseq, VM_FRAME_MAGIC_METHOD | finish_flag,
		  calling->recv, VM_ENVVAL_BLOCK_PTR(calling->blockptr), (VALUE)me,
		  iseq->body->iseq_encoded + opt_pc, sp,
		  iseq->body->local_size - iseq->body->param.size,
		  iseq->body->stack_max);

    cfp->sp = sp_orig;
    return Qundef;
}

static VALUE
call_cfunc_m2(VALUE (*func)(ANYARGS), VALUE recv, int argc, const VALUE *argv)
{
    return (*func)(recv, rb_ary_new4(argc, argv));
}

static VALUE
call_cfunc_m1(VALUE (*func)(ANYARGS), VALUE recv, int argc, const VALUE *argv)
{
    return (*func)(argc, argv, recv);
}

static VALUE
call_cfunc_0(VALUE (*func)(ANYARGS), VALUE recv, int argc, const VALUE *argv)
{
    return (*func)(recv);
}

static VALUE
call_cfunc_1(VALUE (*func)(ANYARGS), VALUE recv, int argc, const VALUE *argv)
{
    return (*func)(recv, argv[0]);
}

static VALUE
call_cfunc_2(VALUE (*func)(ANYARGS), VALUE recv, int argc, const VALUE *argv)
{
    return (*func)(recv, argv[0], argv[1]);
}

static VALUE
call_cfunc_3(VALUE (*func)(ANYARGS), VALUE recv, int argc, const VALUE *argv)
{
    return (*func)(recv, argv[0], argv[1], argv[2]);
}

static VALUE
call_cfunc_4(VALUE (*func)(ANYARGS), VALUE recv, int argc, const VALUE *argv)
{
    return (*func)(recv, argv[0], argv[1], argv[2], argv[3]);
}

static VALUE
call_cfunc_5(VALUE (*func)(ANYARGS), VALUE recv, int argc, const VALUE *argv)
{
    return (*func)(recv, argv[0], argv[1], argv[2], argv[3], argv[4]);
}

static VALUE
call_cfunc_6(VALUE (*func)(ANYARGS), VALUE recv, int argc, const VALUE *argv)
{
    return (*func)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5]);
}

static VALUE
call_cfunc_7(VALUE (*func)(ANYARGS), VALUE recv, int argc, const VALUE *argv)
{
    return (*func)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6]);
}

static VALUE
call_cfunc_8(VALUE (*func)(ANYARGS), VALUE recv, int argc, const VALUE *argv)
{
    return (*func)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7]);
}

static VALUE
call_cfunc_9(VALUE (*func)(ANYARGS), VALUE recv, int argc, const VALUE *argv)
{
    return (*func)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8]);
}

static VALUE
call_cfunc_10(VALUE (*func)(ANYARGS), VALUE recv, int argc, const VALUE *argv)
{
    return (*func)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9]);
}

static VALUE
call_cfunc_11(VALUE (*func)(ANYARGS), VALUE recv, int argc, const VALUE *argv)
{
    return (*func)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10]);
}

static VALUE
call_cfunc_12(VALUE (*func)(ANYARGS), VALUE recv, int argc, const VALUE *argv)
{
    return (*func)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10], argv[11]);
}

static VALUE
call_cfunc_13(VALUE (*func)(ANYARGS), VALUE recv, int argc, const VALUE *argv)
{
    return (*func)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10], argv[11], argv[12]);
}

static VALUE
call_cfunc_14(VALUE (*func)(ANYARGS), VALUE recv, int argc, const VALUE *argv)
{
    return (*func)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10], argv[11], argv[12], argv[13]);
}

static VALUE
call_cfunc_15(VALUE (*func)(ANYARGS), VALUE recv, int argc, const VALUE *argv)
{
    return (*func)(recv, argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8], argv[9], argv[10], argv[11], argv[12], argv[13], argv[14]);
}

#ifndef VM_PROFILE
#define VM_PROFILE 0
#endif

#if VM_PROFILE
enum {
    VM_PROFILE_R2C_CALL,
    VM_PROFILE_R2C_POPF,
    VM_PROFILE_C2C_CALL,
    VM_PROFILE_C2C_POPF,
    VM_PROFILE_COUNT
};
static int vm_profile_counter[VM_PROFILE_COUNT];
#define VM_PROFILE_UP(x) (vm_profile_counter[VM_PROFILE_##x]++)
#define VM_PROFILE_ATEXIT() atexit(vm_profile_show_result)
static void
vm_profile_show_result(void)
{
    fprintf(stderr, "VM Profile results: \n");
    fprintf(stderr, "r->c call: %d\n", vm_profile_counter[VM_PROFILE_R2C_CALL]);
    fprintf(stderr, "r->c popf: %d\n", vm_profile_counter[VM_PROFILE_R2C_POPF]);
    fprintf(stderr, "c->c call: %d\n", vm_profile_counter[VM_PROFILE_C2C_CALL]);
    fprintf(stderr, "c->c popf: %d\n", vm_profile_counter[VM_PROFILE_C2C_POPF]);
}
#else
#define VM_PROFILE_UP(x)
#define VM_PROFILE_ATEXIT()
#endif

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
    return &me->def->body.cfunc;
}

static VALUE
vm_call_cfunc_with_frame(rb_thread_t *th, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc)
{
    VALUE val;
    const rb_callable_method_entry_t *me = cc->me;
    const rb_method_cfunc_t *cfunc = vm_method_cfunc_entry(me);
    int len = cfunc->argc;

    VALUE recv = calling->recv;
    rb_block_t *blockptr = calling->blockptr;
    int argc = calling->argc;

    RUBY_DTRACE_CMETHOD_ENTRY_HOOK(th, me->owner, me->def->original_id);
    EXEC_EVENT_HOOK(th, RUBY_EVENT_C_CALL, recv, me->def->original_id, me->owner, Qundef);

    vm_push_frame(th, NULL, VM_FRAME_MAGIC_CFUNC, recv,
		  VM_ENVVAL_BLOCK_PTR(blockptr), (VALUE)me,
		  0, th->cfp->sp, 1, 0);

    if (len >= 0) rb_check_arity(argc, len, len);

    reg_cfp->sp -= argc + 1;
    VM_PROFILE_UP(R2C_CALL);
    val = (*cfunc->invoker)(cfunc->func, recv, argc, reg_cfp->sp + 1);

    if (reg_cfp != th->cfp + 1) {
	rb_bug("vm_call_cfunc - cfp consistency error");
    }

    vm_pop_frame(th);

    EXEC_EVENT_HOOK(th, RUBY_EVENT_C_RETURN, recv, me->def->original_id, me->owner, val);
    RUBY_DTRACE_CMETHOD_RETURN_HOOK(th, me->owner, me->def->original_id);

    return val;
}

#if OPT_CALL_CFUNC_WITHOUT_FRAME
static VALUE
vm_call_cfunc_latter(rb_thread_t *th, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling)
{
    VALUE val;
    int argc = calling->argc;
    VALUE *argv = STACK_ADDR_FROM_TOP(argc);
    VALUE recv = calling->recv;
    const rb_method_cfunc_t *cfunc = vm_method_cfunc_entry(cc->me);

    th->passed_calling = calling;
    reg_cfp->sp -= argc + 1;
    ci->aux.inc_sp = argc + 1;
    VM_PROFILE_UP(R2C_CALL);
    val = (*cfunc->invoker)(cfunc->func, recv, argc, argv);

    /* check */
    if (reg_cfp == th->cfp) { /* no frame push */
	if (UNLIKELY(th->passed_ci != ci)) {
	    rb_bug("vm_call_cfunc_latter: passed_ci error (ci: %p, passed_ci: %p)", ci, th->passed_ci);
	}
	th->passed_ci = 0;
    }
    else {
	if (UNLIKELY(reg_cfp != RUBY_VM_PREVIOUS_CONTROL_FRAME(th->cfp))) {
	    rb_bug("vm_call_cfunc_latter: cfp consistency error (%p, %p)", reg_cfp, th->cfp+1);
	}
	vm_pop_frame(th);
	VM_PROFILE_UP(R2C_POPF);
    }

    return val;
}

static VALUE
vm_call_cfunc(rb_thread_t *th, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling, const struct rb_call_info *ci)
{
    VALUE val;
    const rb_callable_method_entry_t *me = cc->me;
    int len = vm_method_cfunc_entry(me)->argc;
    VALUE recv = calling->recv;

    CALLER_SETUP_ARG(reg_cfp, calling, ci);
    if (len >= 0) rb_check_arity(calling->argc, len, len);

    RUBY_DTRACE_CMETHOD_ENTRY_HOOK(th, me->owner, me->called_id);
    EXEC_EVENT_HOOK(th, RUBY_EVENT_C_CALL, recv, me->called_id, me->owner, Qnil);

    if (!(cc->me->def->flag & METHOD_VISI_PROTECTED) &&
	!(ci->flag & VM_CALL_ARGS_SPLAT) &&
	!(ci->kw_arg != NULL)) {
	CI_SET_FASTPATH(cc, vm_call_cfunc_latter, 1);
    }
    val = vm_call_cfunc_latter(th, reg_cfp, calling);

    EXEC_EVENT_HOOK(th, RUBY_EVENT_C_RETURN, recv, me->called_id, me->owner, val);
    RUBY_DTRACE_CMETHOD_RETURN_HOOK(th, me->owner, me->called_id);

    return val;
}

void
rb_vm_call_cfunc_push_frame(rb_thread_t *th)
{
    struct rb_calling_info *calling = th->passed_calling;
    const rb_callable_method_entry_t *me = calling->me;
    th->passed_ci = 0;

    vm_push_frame(th, 0, VM_FRAME_MAGIC_CFUNC,
		  calling->recv, VM_ENVVAL_BLOCK_PTR(calling->blockptr), (VALUE)me /* cref */,
		  0, th->cfp->sp + cc->aux.inc_sp, 1, 0);

    if (calling->call != vm_call_general) {
	calling->call = vm_call_cfunc_with_frame;
    }
}
#else /* OPT_CALL_CFUNC_WITHOUT_FRAME */
static VALUE
vm_call_cfunc(rb_thread_t *th, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc)
{
    CALLER_SETUP_ARG(reg_cfp, calling, ci);
    return vm_call_cfunc_with_frame(th, reg_cfp, calling, ci, cc);
}
#endif

static VALUE
vm_call_ivar(rb_thread_t *th, rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc)
{
    VALUE val = vm_getivar(calling->recv, cc->me->def->body.attr.id, NULL, cc, 1);
    cfp->sp -= 1;
    return val;
}

static VALUE
vm_call_attrset(rb_thread_t *th, rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc)
{
    VALUE val = vm_setivar(calling->recv, cc->me->def->body.attr.id, *(cfp->sp - 1), NULL, cc, 1);
    cfp->sp -= 2;
    return val;
}

static inline VALUE
vm_call_bmethod_body(rb_thread_t *th, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc, const VALUE *argv)
{
    rb_proc_t *proc;
    VALUE val;

    /* control block frame */
    th->passed_bmethod_me = cc->me;
    GetProcPtr(cc->me->def->body.proc, proc);
    val = vm_invoke_bmethod(th, proc, calling->recv, calling->argc, argv, calling->blockptr);

    return val;
}

static VALUE
vm_call_bmethod(rb_thread_t *th, rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc)
{
    VALUE *argv;
    int argc;

    CALLER_SETUP_ARG(cfp, calling, ci);

    argc = calling->argc;
    argv = ALLOCA_N(VALUE, argc);
    MEMCPY(argv, cfp->sp - argc, VALUE, argc);
    cfp->sp += - argc - 1;

    return vm_call_bmethod_body(th, calling, ci, cc, argv);
}

static enum method_missing_reason
ci_missing_reason(const struct rb_call_info *ci)
{
    enum method_missing_reason stat = MISSING_NOENTRY;
    if (ci->flag & VM_CALL_VCALL) stat |= MISSING_VCALL;
    if (ci->flag & VM_CALL_SUPER) stat |= MISSING_SUPER;
    return stat;
}

static VALUE
vm_call_opt_send(rb_thread_t *th, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling, const struct rb_call_info *orig_ci, struct rb_call_cache *orig_cc)
{
    int i;
    VALUE sym;
    struct rb_call_info *ci;
    struct rb_call_info_with_kwarg ci_entry;
    struct rb_call_cache cc_entry, *cc;

    CALLER_SETUP_ARG(reg_cfp, calling, orig_ci);

    i = calling->argc - 1;

    if (calling->argc == 0) {
	rb_raise(rb_eArgError, "no method name given");
    }

    /* setup new ci */
    if (orig_ci->flag & VM_CALL_KWARG) {
	ci = (struct rb_call_info *)&ci_entry;
	ci_entry = *(struct rb_call_info_with_kwarg *)orig_ci;
    }
    else {
	ci = &ci_entry.ci;
	ci_entry.ci = *orig_ci;
    }
    ci->flag = ci->flag & ~VM_CALL_KWARG; /* TODO: delegate kw_arg without making a Hash object */

    /* setup new cc */
    cc_entry = *orig_cc;
    cc = &cc_entry;

    sym = TOPN(i);

    if (!(ci->mid = rb_check_id(&sym))) {
	if (rb_method_basic_definition_p(CLASS_OF(calling->recv), idMethodMissing)) {
	    VALUE exc = make_no_method_exception(rb_eNoMethodError, NULL, calling->recv, rb_long2int(calling->argc), &TOPN(i));
	    rb_exc_raise(exc);
	}
	TOPN(i) = rb_str_intern(sym);
	ci->mid = idMethodMissing;
	th->method_missing_reason = cc->aux.method_missing_reason = ci_missing_reason(ci);
    }
    else {
	/* shift arguments */
	if (i > 0) {
	    MEMMOVE(&TOPN(i), &TOPN(i-1), VALUE, i);
	}
	calling->argc -= 1;
	DEC_SP(1);
    }

    cc->me = rb_callable_method_entry_without_refinements(CLASS_OF(calling->recv), ci->mid);
    ci->flag = VM_CALL_FCALL | VM_CALL_OPT_SEND;
    return vm_call_method(th, reg_cfp, calling, ci, cc);
}

static VALUE
vm_call_opt_call(rb_thread_t *th, rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc)
{
    rb_proc_t *proc;
    int argc;
    VALUE *argv;

    CALLER_SETUP_ARG(cfp, calling, ci);

    argc = calling->argc;
    argv = ALLOCA_N(VALUE, argc);
    GetProcPtr(calling->recv, proc);
    MEMCPY(argv, cfp->sp - argc, VALUE, argc);
    cfp->sp -= argc + 1;

    return rb_vm_invoke_proc(th, proc, argc, argv, calling->blockptr);
}

static VALUE
vm_call_method_missing(rb_thread_t *th, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling, const struct rb_call_info *orig_ci, struct rb_call_cache *orig_cc)
{
    VALUE *argv = STACK_ADDR_FROM_TOP(calling->argc);
    struct rb_call_info ci_entry;
    const struct rb_call_info *ci;
    struct rb_call_cache cc_entry, *cc;
    unsigned int argc;

    CALLER_SETUP_ARG(reg_cfp, calling, orig_ci);
    argc = calling->argc+1;

    ci_entry.flag = VM_CALL_FCALL | VM_CALL_OPT_SEND;
    ci_entry.mid = idMethodMissing;
    ci_entry.orig_argc = argc;
    ci = &ci_entry;

    cc_entry = *orig_cc;
    cc_entry.me =
	rb_callable_method_entry_without_refinements(CLASS_OF(calling->recv),
						     idMethodMissing);
    cc = &cc_entry;

    calling->argc = argc;

    /* shift arguments: m(a, b, c) #=> method_missing(:m, a, b, c) */
    CHECK_VM_STACK_OVERFLOW(reg_cfp, 1);
    if (argc > 1) {
	MEMMOVE(argv+1, argv, VALUE, argc-1);
    }
    argv[0] = ID2SYM(orig_ci->mid);
    INC_SP(1);

    th->method_missing_reason = orig_cc->aux.method_missing_reason;
    return vm_call_method(th, reg_cfp, calling, ci, cc);
}

static VALUE
vm_call_zsuper(rb_thread_t *th, rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc, VALUE klass)
{
    klass = RCLASS_SUPER(klass);
    cc->me = klass ? rb_callable_method_entry(klass, ci->mid) : NULL;

    if (cc->me != NULL) {
	return vm_call_method_each_type(th, cfp, calling, ci, cc);
    }
    else {
	return vm_call_method_nome(th, cfp, calling, ci, cc);
    }
}

static inline VALUE
find_refinement(VALUE refinements, VALUE klass)
{
    if (NIL_P(refinements)) {
	return Qnil;
    }
    return rb_hash_lookup(refinements, klass);
}

static rb_control_frame_t *
current_method_entry(rb_thread_t *th, rb_control_frame_t *cfp)
{
    rb_control_frame_t *top_cfp = cfp;

    if (cfp->iseq && cfp->iseq->body->type == ISEQ_TYPE_BLOCK) {
	const rb_iseq_t *local_iseq = cfp->iseq->body->local_iseq;

	do {
	    cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
	    if (RUBY_VM_CONTROL_FRAME_STACK_OVERFLOW_P(th, cfp)) {
		/* TODO: orphan block */
		return top_cfp;
	    }
	} while (cfp->iseq != local_iseq);
    }
    return cfp;
}

static VALUE
find_defined_class_by_owner(VALUE current_class, VALUE target_owner)
{
    VALUE klass = current_class;

    /* for prepended Module, then start from cover class */
    if (RB_TYPE_P(klass, T_ICLASS) && FL_TEST(klass, RICLASS_IS_ORIGIN)) klass = RBASIC_CLASS(klass);

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
	VALUE defined_class = find_defined_class_by_owner(me->defined_class, orig_me->owner);
	VM_ASSERT(RB_TYPE_P(orig_me->owner, T_MODULE));
	cme = rb_method_entry_complement_defined_class(orig_me, me->called_id, defined_class);

	if (me->def->alias_count + me->def->complemented_count == 0) {
	    RB_OBJ_WRITE(me, &me->def->body.alias.original_me, cme);
	}
	else {
	    method_definition_set((rb_method_entry_t *)me,
				  method_definition_create(VM_METHOD_TYPE_ALIAS, me->def->original_id),
				  (void *)cme);
	}
    }
    else {
	cme = (const rb_callable_method_entry_t *)orig_me;
    }

    VM_ASSERT(callable_method_entry_p(cme));
    return cme;
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
    return cme;
}

static VALUE
vm_call_method_each_type(rb_thread_t *th, rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc)
{
    switch (cc->me->def->type) {
      case VM_METHOD_TYPE_ISEQ:
	CI_SET_FASTPATH(cc, vm_call_iseq_setup, TRUE);
	return vm_call_iseq_setup(th, cfp, calling, ci, cc);

      case VM_METHOD_TYPE_NOTIMPLEMENTED:
      case VM_METHOD_TYPE_CFUNC:
	CI_SET_FASTPATH(cc, vm_call_cfunc, TRUE);
	return vm_call_cfunc(th, cfp, calling, ci, cc);

      case VM_METHOD_TYPE_ATTRSET:
	CALLER_SETUP_ARG(cfp, calling, ci);
	rb_check_arity(calling->argc, 1, 1);
	cc->aux.index = 0;
	CI_SET_FASTPATH(cc, vm_call_attrset, !((ci->flag & VM_CALL_ARGS_SPLAT) || (ci->flag & VM_CALL_KWARG)));
	return vm_call_attrset(th, cfp, calling, ci, cc);

      case VM_METHOD_TYPE_IVAR:
	CALLER_SETUP_ARG(cfp, calling, ci);
	rb_check_arity(calling->argc, 0, 0);
	cc->aux.index = 0;
	CI_SET_FASTPATH(cc, vm_call_ivar, !(ci->flag & VM_CALL_ARGS_SPLAT));
	return vm_call_ivar(th, cfp, calling, ci, cc);

      case VM_METHOD_TYPE_MISSING:
	cc->aux.method_missing_reason = 0;
	CI_SET_FASTPATH(cc, vm_call_method_missing, TRUE);
	return vm_call_method_missing(th, cfp, calling, ci, cc);

      case VM_METHOD_TYPE_BMETHOD:
	CI_SET_FASTPATH(cc, vm_call_bmethod, TRUE);
	return vm_call_bmethod(th, cfp, calling, ci, cc);

      case VM_METHOD_TYPE_ALIAS:
	cc->me = aliased_callable_method_entry(cc->me);
	VM_ASSERT(cc->me != NULL);
	return vm_call_method_each_type(th, cfp, calling, ci, cc);

      case VM_METHOD_TYPE_OPTIMIZED:
	switch (cc->me->def->body.optimize_type) {
	  case OPTIMIZED_METHOD_TYPE_SEND:
	    CI_SET_FASTPATH(cc, vm_call_opt_send, TRUE);
	    return vm_call_opt_send(th, cfp, calling, ci, cc);
	  case OPTIMIZED_METHOD_TYPE_CALL:
	    CI_SET_FASTPATH(cc, vm_call_opt_call, TRUE);
	    return vm_call_opt_call(th, cfp, calling, ci, cc);
	  default:
	    rb_bug("vm_call_method: unsupported optimized method type (%d)",
		   cc->me->def->body.optimize_type);
	}

      case VM_METHOD_TYPE_UNDEF:
	break;

      case VM_METHOD_TYPE_ZSUPER:
	return vm_call_zsuper(th, cfp, calling, ci, cc, RCLASS_ORIGIN(cc->me->owner));

      case VM_METHOD_TYPE_REFINED: {
	  const rb_cref_t *cref = rb_vm_get_cref(cfp->ep);
	  VALUE refinements = cref ? CREF_REFINEMENTS(cref) : Qnil;
	  VALUE refinement;
	  const rb_callable_method_entry_t *ref_me;

	  refinement = find_refinement(refinements, cc->me->owner);

	  if (NIL_P(refinement)) {
	      goto no_refinement_dispatch;
	  }
	  ref_me = rb_callable_method_entry(refinement, ci->mid);

	  if (ref_me) {
	      if (cc->call == vm_call_super_method) {
		  const rb_control_frame_t *top_cfp = current_method_entry(th, cfp);
		  const rb_callable_method_entry_t *top_me = rb_vm_frame_method_entry(top_cfp);
		  if (top_me && rb_method_definition_eq(ref_me->def, top_me->def)) {
		      goto no_refinement_dispatch;
		  }
	      }
	      cc->me = ref_me;
	      if (ref_me->def->type != VM_METHOD_TYPE_REFINED) {
		  return vm_call_method(th, cfp, calling, ci, cc);
	      }
	  }
	  else {
	      cc->me = NULL;
	      return vm_call_method_nome(th, cfp, calling, ci, cc);
	  }

	no_refinement_dispatch:
	  if (cc->me->def->body.refined.orig_me) {
	      cc->me = refined_method_callable_without_refinement(cc->me);

	      if (UNDEFINED_METHOD_ENTRY_P(cc->me)) {
		  cc->me = NULL;
	      }
	      return vm_call_method(th, cfp, calling, ci, cc);
	  }
	  else {
	      return vm_call_zsuper(th, cfp, calling, ci, cc, cc->me->owner);
	  }
      }
    }

    rb_bug("vm_call_method: unsupported method type (%d)", cc->me->def->type);
}

static VALUE
vm_call_method_nome(rb_thread_t *th, rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc)
{
    /* method missing */
    const int stat = ci_missing_reason(ci);

    if (ci->mid == idMethodMissing) {
	rb_control_frame_t *reg_cfp = cfp;
	VALUE *argv = STACK_ADDR_FROM_TOP(calling->argc);
	rb_raise_method_missing(th, calling->argc, argv, calling->recv, stat);
    }
    else {
	cc->aux.method_missing_reason = stat;
	CI_SET_FASTPATH(cc, vm_call_method_missing, 1);
	return vm_call_method_missing(th, cfp, calling, ci, cc);
    }
}

static inline VALUE
vm_call_method(rb_thread_t *th, rb_control_frame_t *cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc)
{
    VM_ASSERT(callable_method_entry_p(cc->me));

    if (cc->me != NULL) {
	switch (METHOD_ENTRY_VISI(cc->me)) {
	  case METHOD_VISI_PUBLIC: /* likely */
	    return vm_call_method_each_type(th, cfp, calling, ci, cc);

	  case METHOD_VISI_PRIVATE:
	    if (!(ci->flag & VM_CALL_FCALL)) {
		enum method_missing_reason stat = MISSING_PRIVATE;
		if (ci->flag & VM_CALL_VCALL) stat |= MISSING_VCALL;

		cc->aux.method_missing_reason = stat;
		CI_SET_FASTPATH(cc, vm_call_method_missing, 1);
		return vm_call_method_missing(th, cfp, calling, ci, cc);
	    }
	    return vm_call_method_each_type(th, cfp, calling, ci, cc);

	  case METHOD_VISI_PROTECTED:
	    if (!(ci->flag & VM_CALL_OPT_SEND)) {
		if (!rb_obj_is_kind_of(cfp->self, cc->me->defined_class)) {
		    cc->aux.method_missing_reason = MISSING_PROTECTED;
		    return vm_call_method_missing(th, cfp, calling, ci, cc);
		}
		else {
		    /* caching method info to dummy cc */
		    struct rb_call_cache cc_entry;
		    cc_entry = *cc;
		    cc = &cc_entry;

		    VM_ASSERT(cc->me != NULL);
		    return vm_call_method_each_type(th, cfp, calling, ci, cc);
		}
	    }
	    return vm_call_method_each_type(th, cfp, calling, ci, cc);

	  default:
	    rb_bug("unreachable");
	}
    }
    else {
	return vm_call_method_nome(th, cfp, calling, ci, cc);
    }
}

static VALUE
vm_call_general(rb_thread_t *th, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc)
{
    return vm_call_method(th, reg_cfp, calling, ci, cc);
}

static VALUE
vm_call_super_method(rb_thread_t *th, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling, const struct rb_call_info *ci, struct rb_call_cache *cc)
{
    /* this check is required to distinguish with other functions. */
    if (cc->call != vm_call_super_method) rb_bug("bug");
    return vm_call_method(th, reg_cfp, calling, ci, cc);
}

/* super */

static inline VALUE
vm_search_normal_superclass(VALUE klass)
{
    if (BUILTIN_TYPE(klass) == T_ICLASS &&
	FL_TEST(RBASIC(klass)->klass, RMODULE_IS_REFINEMENT)) {
	klass = RBASIC(klass)->klass;
    }
    klass = RCLASS_ORIGIN(klass);
    return RCLASS_SUPER(klass);
}

static void
vm_super_outside(void)
{
    rb_raise(rb_eNoMethodError, "super called outside of method");
}

static void
vm_search_super_method(rb_thread_t *th, rb_control_frame_t *reg_cfp,
		       struct rb_calling_info *calling, struct rb_call_info *ci, struct rb_call_cache *cc)
{
    VALUE current_defined_class, klass;
    VALUE sigval = TOPN(calling->argc);
    const rb_callable_method_entry_t *me = rb_vm_frame_method_entry(reg_cfp);

    if (!me) {
	vm_super_outside();
    }

    current_defined_class = me->defined_class;

    if (!NIL_P(RCLASS_REFINED_CLASS(current_defined_class))) {
	current_defined_class = RCLASS_REFINED_CLASS(current_defined_class);
    }

    if (BUILTIN_TYPE(current_defined_class) != T_MODULE &&
	BUILTIN_TYPE(current_defined_class) != T_ICLASS && /* bound UnboundMethod */
	!FL_TEST(current_defined_class, RMODULE_INCLUDED_INTO_REFINEMENT) &&
	!rb_obj_is_kind_of(calling->recv, current_defined_class)) {
	VALUE m = RB_TYPE_P(current_defined_class, T_ICLASS) ?
	    RBASIC(current_defined_class)->klass : current_defined_class;

	rb_raise(rb_eTypeError,
		 "self has wrong type to call super in this context: "
		 "%"PRIsVALUE" (expected %"PRIsVALUE")",
		 rb_obj_class(calling->recv), m);
    }

    if (me->def->type == VM_METHOD_TYPE_BMETHOD && !sigval) {
	rb_raise(rb_eRuntimeError,
		 "implicit argument passing of super from method defined"
		 " by define_method() is not supported."
		 " Specify all arguments explicitly.");
    }

    ci->mid = me->def->original_id;
    klass = vm_search_normal_superclass(me->defined_class);

    if (!klass) {
	/* bound instance method of module */
	cc->aux.method_missing_reason = MISSING_SUPER;
	CI_SET_FASTPATH(cc, vm_call_method_missing, 1);
    }
    else {
	/* TODO: use inline cache */
	cc->me = rb_callable_method_entry(klass, ci->mid);
	CI_SET_FASTPATH(cc, vm_call_super_method, 1);
    }
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
vm_yield_with_cfunc(rb_thread_t *th, const rb_block_t *block, VALUE self,
		    int argc, const VALUE *argv,
		    const rb_block_t *blockargptr)
{
    const struct vm_ifunc *ifunc = (struct vm_ifunc *)block->iseq;
    VALUE val, arg, blockarg, data;
    rb_block_call_func *func;
    const rb_callable_method_entry_t *me = th->passed_bmethod_me;
    th->passed_bmethod_me = NULL;

    if (!RUBY_VM_IFUNC_P(block->proc) && !SYMBOL_P(block->proc) &&
	block_proc_is_lambda(block->proc)) {
	arg = rb_ary_new4(argc, argv);
    }
    else if (argc == 0) {
	arg = Qnil;
    }
    else {
	arg = argv[0];
    }

    if (blockargptr) {
	if (blockargptr->proc) {
	    blockarg = blockargptr->proc;
	}
	else {
	    blockarg = rb_vm_make_proc(th, blockargptr, rb_cProc);
	}
    }
    else {
	blockarg = Qnil;
    }

    vm_push_frame(th, (rb_iseq_t *)ifunc, VM_FRAME_MAGIC_IFUNC,
		  self, VM_ENVVAL_PREV_EP_PTR(block->ep), (VALUE)me,
		  0, th->cfp->sp, 1, 0);

    if (SYMBOL_P(ifunc)) {
	func = rb_sym_proc_call;
	data = SYM2ID((VALUE)ifunc);
    }
    else {
	func = (rb_block_call_func *)ifunc->func;
	data = (VALUE)ifunc->data;
    }
    val = (*func)(arg, data, argc, argv, blockarg);

    th->cfp++;
    return val;
}

static inline int
vm_callee_setup_block_arg_arg0_splat(rb_control_frame_t *cfp, const rb_iseq_t *iseq, VALUE *argv, VALUE ary)
{
    int i;
    long len = RARRAY_LEN(ary);

    CHECK_VM_STACK_OVERFLOW(cfp, iseq->body->param.lead_num);

    for (i=0; i<len && i<iseq->body->param.lead_num; i++) {
	argv[i] = RARRAY_AREF(ary, i);
    }

    return i;
}

static inline VALUE
vm_callee_setup_block_arg_arg0_check(VALUE *argv)
{
    VALUE ary, arg0 = argv[0];
    ary = rb_check_array_type(arg0);
    argv[0] = arg0;
    return ary;
}

static int
vm_callee_setup_block_arg(rb_thread_t *th, struct rb_calling_info *calling, const struct rb_call_info *ci, const rb_iseq_t *iseq, VALUE *argv, const enum arg_setup_type arg_setup_type)
{
    if (simple_iseq_p(iseq)) {
	rb_control_frame_t *cfp = th->cfp;
	VALUE arg0;

	CALLER_SETUP_ARG(cfp, calling, ci); /* splat arg */

	if (arg_setup_type == arg_setup_block &&
	    calling->argc == 1 &&
	    iseq->body->param.flags.has_lead &&
	    !iseq->body->param.flags.ambiguous_param0 &&
	    !NIL_P(arg0 = vm_callee_setup_block_arg_arg0_check(argv))) {
	    calling->argc = vm_callee_setup_block_arg_arg0_splat(cfp, iseq, argv, arg0);
	}

	if (calling->argc != iseq->body->param.lead_num) {
	    if (arg_setup_type == arg_setup_block) {
		if (calling->argc < iseq->body->param.lead_num) {
		    int i;
		    CHECK_VM_STACK_OVERFLOW(cfp, iseq->body->param.lead_num);
		    for (i=calling->argc; i<iseq->body->param.lead_num; i++) argv[i] = Qnil;
		    calling->argc = iseq->body->param.lead_num; /* fill rest parameters */
		}
		else if (calling->argc > iseq->body->param.lead_num) {
		    calling->argc = iseq->body->param.lead_num; /* simply truncate arguments */
		}
	    }
	    else if (arg_setup_type == arg_setup_lambda &&
		     calling->argc == 1 &&
		     !NIL_P(arg0 = vm_callee_setup_block_arg_arg0_check(argv)) &&
		     RARRAY_LEN(arg0) == iseq->body->param.lead_num) {
		calling->argc = vm_callee_setup_block_arg_arg0_splat(cfp, iseq, argv, arg0);
	    }
	    else {
		argument_arity_error(th, iseq, calling->argc, iseq->body->param.lead_num, iseq->body->param.lead_num);
	    }
	}

	return 0;
    }
    else {
	return setup_parameters_complex(th, iseq, calling, ci, argv, arg_setup_type);
    }
}

static int
vm_yield_setup_args(rb_thread_t *th, const rb_iseq_t *iseq, const int argc, VALUE *argv, const rb_block_t *blockptr, enum arg_setup_type arg_setup_type)
{
    struct rb_calling_info calling_entry, *calling;
    struct rb_call_info ci_entry, *ci;

    calling = &calling_entry;
    calling->argc = argc;
    calling->blockptr  = (rb_block_t *)blockptr;

    ci_entry.flag = 0;
    ci = &ci_entry;

    return vm_callee_setup_block_arg(th, calling, ci, iseq, argv, arg_setup_type);
}

/* ruby iseq -> ruby block iseq */

static VALUE
vm_invoke_block(rb_thread_t *th, rb_control_frame_t *reg_cfp, struct rb_calling_info *calling, const struct rb_call_info *ci)
{
    const rb_block_t *block = VM_CF_BLOCK_PTR(reg_cfp);
    VALUE type = GET_ISEQ()->body->local_iseq->body->type;

    if ((type != ISEQ_TYPE_METHOD && type != ISEQ_TYPE_CLASS) || block == 0) {
	rb_vm_localjump_error("no block given (yield)", Qnil, 0);
    }

    if (RUBY_VM_NORMAL_ISEQ_P(block->iseq)) {
	const rb_iseq_t *iseq = block->iseq;
	const int arg_size = iseq->body->param.size;
	int is_lambda = block_proc_is_lambda(block->proc);
	VALUE * const rsp = GET_SP() - calling->argc;
	int opt_pc = vm_callee_setup_block_arg(th, calling, ci, iseq, rsp, is_lambda ? arg_setup_lambda : arg_setup_block);

	SET_SP(rsp);

	vm_push_frame(th, iseq,
		      is_lambda ? VM_FRAME_MAGIC_LAMBDA : VM_FRAME_MAGIC_BLOCK,
		      block->self,
		      VM_ENVVAL_PREV_EP_PTR(block->ep), 0,
		      iseq->body->iseq_encoded + opt_pc,
		      rsp + arg_size,
		      iseq->body->local_size - arg_size, iseq->body->stack_max);

	return Qundef;
    }
    else {
	VALUE val;
	int argc;
	CALLER_SETUP_ARG(th->cfp, calling, ci);
	argc = calling->argc;
	val = vm_yield_with_cfunc(th, block, block->self, argc, STACK_ADDR_FROM_TOP(argc), 0);
	POPN(argc); /* TODO: should put before C/yield? */
	return val;
    }
}

static VALUE
vm_make_proc_with_iseq(const rb_iseq_t *blockiseq)
{
    rb_block_t *blockptr;
    rb_thread_t *th = GET_THREAD();
    rb_control_frame_t *cfp = rb_vm_get_ruby_level_next_cfp(th, th->cfp);

    if (cfp == 0) {
	rb_bug("vm_make_proc_with_iseq: unreachable");
    }

    blockptr = RUBY_VM_GET_BLOCK_PTR_IN_CFP(cfp);
    blockptr->iseq = blockiseq;
    blockptr->proc = 0;

    return rb_vm_make_proc(th, blockptr, rb_cProc);
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

rb_control_frame_t *
FUNC_FASTCALL(rb_vm_opt_struct_aref)(rb_thread_t *th, rb_control_frame_t *reg_cfp)
{
    TOPN(0) = rb_struct_aref(GET_SELF(), TOPN(0));
    return reg_cfp;
}

rb_control_frame_t *
FUNC_FASTCALL(rb_vm_opt_struct_aset)(rb_thread_t *th, rb_control_frame_t *reg_cfp)
{
    rb_struct_aset(GET_SELF(), TOPN(0), TOPN(1));
    return reg_cfp;
}

/* defined insn */

static enum defined_type
check_respond_to_missing(VALUE obj, VALUE v)
{
    VALUE args[2];
    VALUE r;

    args[0] = obj; args[1] = Qfalse;
    r = rb_check_funcall(v, idRespond_to_missing, 2, args);
    if (r != Qundef && RTEST(r)) {
	return DEFINED_METHOD;
    }
    else {
	return 0;
    }
}

static VALUE
vm_defined(rb_thread_t *th, rb_control_frame_t *reg_cfp, rb_num_t op_type, VALUE obj, VALUE needstr, VALUE v)
{
    VALUE klass;
    enum defined_type expr_type = 0;
    enum defined_type type = (enum defined_type)op_type;

    switch (type) {
      case DEFINED_IVAR:
	if (rb_ivar_defined(GET_SELF(), SYM2ID(obj))) {
	    expr_type = DEFINED_IVAR;
	}
	break;
      case DEFINED_IVAR2:
	klass = vm_get_cbase(GET_EP());
	break;
      case DEFINED_GVAR:
	if (rb_gvar_defined(rb_global_entry(SYM2ID(obj)))) {
	    expr_type = DEFINED_GVAR;
	}
	break;
      case DEFINED_CVAR: {
	const rb_cref_t *cref = rb_vm_get_cref(GET_EP());
	klass = vm_get_cvar_base(cref, GET_CFP());
	if (rb_cvar_defined(klass, SYM2ID(obj))) {
	    expr_type = DEFINED_CVAR;
	}
	break;
      }
      case DEFINED_CONST:
	klass = v;
	if (vm_get_ev_const(th, klass, SYM2ID(obj), 1)) {
	    expr_type = DEFINED_CONST;
	}
	break;
      case DEFINED_FUNC:
	klass = CLASS_OF(v);
	if (rb_method_boundp(klass, SYM2ID(obj), 0)) {
	    expr_type = DEFINED_METHOD;
	}
	else {
	    expr_type = check_respond_to_missing(obj, v);
	}
	break;
      case DEFINED_METHOD:{
	VALUE klass = CLASS_OF(v);
	const rb_method_entry_t *me = rb_method_entry(klass, SYM2ID(obj));

	if (me) {
	    switch (METHOD_ENTRY_VISI(me)) {
	      case METHOD_VISI_PRIVATE:
		break;
	      case METHOD_VISI_PROTECTED:
		if (!rb_obj_is_kind_of(GET_SELF(), rb_class_real(klass))) {
		    break;
		}
	      case METHOD_VISI_PUBLIC:
		expr_type = DEFINED_METHOD;
		break;
	      default:
		rb_bug("vm_defined: unreachable: %u", (unsigned int)METHOD_ENTRY_VISI(me));
	    }
	}
	else {
	    expr_type = check_respond_to_missing(obj, v);
	}
	break;
      }
      case DEFINED_YIELD:
	if (GET_BLOCK_PTR()) {
	    expr_type = DEFINED_YIELD;
	}
	break;
      case DEFINED_ZSUPER:
	{
	    const rb_callable_method_entry_t *me = rb_vm_frame_method_entry(GET_CFP());

	    if (me) {
		VALUE klass = vm_search_normal_superclass(me->defined_class);
		ID id = me->def->original_id;

		if (rb_method_boundp(klass, id, 0)) {
		    expr_type = DEFINED_ZSUPER;
		}
	    }
	}
	break;
      case DEFINED_REF:{
	if (vm_getspecial(th, GET_LEP(), Qfalse, FIX2INT(obj)) != Qnil) {
	    expr_type = DEFINED_GVAR;
	}
	break;
      }
      default:
	rb_bug("unimplemented defined? type (VM)");
	break;
    }

    if (expr_type != 0) {
	if (needstr != Qfalse) {
	    return rb_iseq_defined_string(expr_type);
	}
	else {
	    return Qtrue;
	}
    }
    else {
	return Qnil;
    }
}
