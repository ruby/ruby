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

static rb_control_frame_t *
vm_get_ruby_level_caller_cfp(const rb_thread_t *th, const rb_control_frame_t *cfp);

VALUE
ruby_vm_sysstack_error_copy(void)
{
    VALUE e = rb_obj_alloc(rb_eSysStackError);
    rb_obj_copy_ivar(e, sysstack_error);
    return e;
}

static void
vm_stackoverflow(void)
{
    rb_exc_raise(ruby_vm_sysstack_error_copy());
}

static inline rb_control_frame_t *
vm_push_frame(rb_thread_t *th,
	      const rb_iseq_t *iseq,
	      VALUE type,
	      VALUE self,
	      VALUE klass,
	      VALUE specval,
	      const VALUE *pc,
	      VALUE *sp,
	      int local_size,
	      const rb_method_entry_t *me,
	      int stack_max)
{
    rb_control_frame_t *const cfp = th->cfp - 1;
    int i;

    /* check stack overflow */
    CHECK_VM_STACK_OVERFLOW0(cfp, sp, local_size + stack_max);

    th->cfp = cfp;

    /* setup vm value stack */

    /* initialize local variables */
    for (i=0; i < local_size; i++) {
	*sp++ = Qnil;
    }

    /* set special val */
    *sp = specval;

    /* setup vm control frame stack */

    cfp->pc = (VALUE *)pc;
    cfp->sp = sp + 1;
#if VM_DEBUG_BP_CHECK
    cfp->bp_check = sp + 1;
#endif
    cfp->ep = sp;
    cfp->iseq = (rb_iseq_t *) iseq;
    cfp->flag = type;
    cfp->self = self;
    cfp->block_iseq = 0;
    cfp->proc = 0;
    cfp->me = me;
    if (klass) {
	cfp->klass = klass;
    }
    else {
	rb_control_frame_t *prev_cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp);
	if (RUBY_VM_CONTROL_FRAME_STACK_OVERFLOW_P(th, prev_cfp)) {
	    cfp->klass = Qnil;
	}
	else {
	    cfp->klass = prev_cfp->klass;
	}
    }

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
	err_mess = rb_sprintf("wrong number of arguments (%d for %d)", argc, min);
    }
    else if (max == UNLIMITED_ARGUMENTS) {
	err_mess = rb_sprintf("wrong number of arguments (%d for %d+)", argc, min);
    }
    else {
	err_mess = rb_sprintf("wrong number of arguments (%d for %d..%d)", argc, min, max);
    }
    return rb_exc_new3(rb_eArgError, err_mess);
}

void
rb_error_arity(int argc, int min, int max)
{
    rb_exc_raise(rb_arity_error_new(argc, min, max));
}

/* svar */

static inline NODE *
lep_svar_place(rb_thread_t *th, VALUE *lep)
{
    VALUE *svar;

    if (lep && th->root_lep != lep) {
	svar = &lep[-1];
    }
    else {
	svar = &th->root_svar;
    }
    if (NIL_P(*svar)) {
	*svar = (VALUE)NEW_IF(Qnil, Qnil, Qnil);
    }
    return (NODE *)*svar;
}

static VALUE
lep_svar_get(rb_thread_t *th, VALUE *lep, rb_num_t key)
{
    NODE *svar = lep_svar_place(th, lep);

    switch (key) {
      case 0:
	return svar->u1.value;
      case 1:
	return svar->u2.value;
      default: {
	const VALUE ary = svar->u3.value;

	if (NIL_P(ary)) {
	    return Qnil;
	}
	else {
	    return rb_ary_entry(ary, key - DEFAULT_SPECIAL_VAR_COUNT);
	}
      }
    }
}

static void
lep_svar_set(rb_thread_t *th, VALUE *lep, rb_num_t key, VALUE val)
{
    NODE *svar = lep_svar_place(th, lep);

    switch (key) {
      case 0:
	RB_OBJ_WRITE(svar, &svar->u1.value, val);
	return;
      case 1:
	RB_OBJ_WRITE(svar, &svar->u2.value, val);
	return;
      default: {
	VALUE ary = svar->u3.value;

	if (NIL_P(ary)) {
	    RB_OBJ_WRITE(svar, &svar->u3.value, ary = rb_ary_new());
	}
	rb_ary_store(ary, key - DEFAULT_SPECIAL_VAR_COUNT, val);
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
	VALUE backref = lep_svar_get(th, lep, 1);

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

static NODE *
vm_get_cref0(const rb_iseq_t *iseq, const VALUE *ep)
{
    while (1) {
	if (VM_EP_LEP_P(ep)) {
	    if (!RUBY_VM_NORMAL_ISEQ_P(iseq)) return NULL;
	    return iseq->cref_stack;
	}
	else if (ep[-1] != Qnil) {
	    return (NODE *)ep[-1];
	}
	ep = VM_EP_PREV_EP(ep);
    }
}

NODE *
rb_vm_get_cref(const rb_iseq_t *iseq, const VALUE *ep)
{
    NODE *cref = vm_get_cref0(iseq, ep);

    if (cref == 0) {
	rb_bug("rb_vm_get_cref: unreachable");
    }
    return cref;
}

void
rb_vm_rewrite_cref_stack(NODE *node, VALUE old_klass, VALUE new_klass, NODE **new_cref_ptr)
{
    NODE *new_node;
    while (node) {
	if (node->nd_clss == old_klass) {
	    new_node = NEW_CREF(new_klass);
	    COPY_CREF_OMOD(new_node, node);
	    RB_OBJ_WRITE(new_node, &new_node->nd_next, node->nd_next);
	    *new_cref_ptr = new_node;
	    return;
	}
	new_node = NEW_CREF(node->nd_clss);
	COPY_CREF_OMOD(new_node, node);
	node = node->nd_next;
	*new_cref_ptr = new_node;
	new_cref_ptr = &new_node->nd_next;
    }
    *new_cref_ptr = NULL;
}

static NODE *
vm_cref_push(rb_thread_t *th, VALUE klass, int noex, rb_block_t *blockptr)
{
    rb_control_frame_t *cfp = vm_get_ruby_level_caller_cfp(th, th->cfp);
    NODE *cref = NEW_CREF(klass);
    cref->nd_refinements = Qnil;
    cref->nd_visi = noex;

    if (blockptr) {
	RB_OBJ_WRITE(cref, &cref->nd_next, vm_get_cref0(blockptr->iseq, blockptr->ep));
    }
    else if (cfp) {
	RB_OBJ_WRITE(cref, &cref->nd_next, vm_get_cref0(cfp->iseq, cfp->ep));
    }
    /* TODO: why cref->nd_next is 1? */
    if (cref->nd_next && cref->nd_next != (void *) 1 &&
	!NIL_P(cref->nd_next->nd_refinements)) {
	COPY_CREF_OMOD(cref, cref->nd_next);
    }

    return cref;
}

static inline VALUE
vm_get_cbase(const rb_iseq_t *iseq, const VALUE *ep)
{
    NODE *cref = rb_vm_get_cref(iseq, ep);
    VALUE klass = Qundef;

    while (cref) {
	if ((klass = cref->nd_clss) != 0) {
	    break;
	}
	cref = cref->nd_next;
    }

    return klass;
}

static inline VALUE
vm_get_const_base(const rb_iseq_t *iseq, const VALUE *ep)
{
    NODE *cref = rb_vm_get_cref(iseq, ep);
    VALUE klass = Qundef;

    while (cref) {
	if (!(cref->flags & NODE_FL_CREF_PUSHED_BY_EVAL) &&
	    (klass = cref->nd_clss) != 0) {
	    break;
	}
	cref = cref->nd_next;
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
    if (RB_TYPE_P(klass, T_MODULE) &&
	FL_TEST(klass, RMODULE_IS_OVERLAID) &&
	RB_TYPE_P(cfp->klass, T_ICLASS) &&
	RBASIC(cfp->klass)->klass == klass) {
	return cfp->klass;
    }
    else {
	return klass;
    }
}

static inline VALUE
vm_get_ev_const(rb_thread_t *th, const rb_iseq_t *iseq,
		VALUE orig_klass, ID id, int is_defined)
{
    VALUE val;

    if (orig_klass == Qnil) {
	/* in current lexical scope */
	const NODE *root_cref = rb_vm_get_cref(iseq, th->cfp->ep);
	const NODE *cref;
	VALUE klass = orig_klass;

	while (root_cref && root_cref->flags & NODE_FL_CREF_PUSHED_BY_EVAL) {
	    root_cref = root_cref->nd_next;
	}
	cref = root_cref;
	while (cref && cref->nd_next) {
	    if (cref->flags & NODE_FL_CREF_PUSHED_BY_EVAL) {
		klass = Qnil;
	    }
	    else {
		klass = cref->nd_clss;
	    }
	    cref = cref->nd_next;

	    if (!NIL_P(klass)) {
		VALUE av, am = 0;
		rb_const_entry_t *ce;
	      search_continue:
		if ((ce = rb_const_lookup(klass, id))) {
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
	if (root_cref && !NIL_P(root_cref->nd_clss)) {
	    klass = vm_get_iclass(th->cfp, root_cref->nd_clss);
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
vm_get_cvar_base(NODE *cref, rb_control_frame_t *cfp)
{
    VALUE klass;

    if (!cref) {
	rb_bug("vm_get_cvar_base: no cref");
    }

    while (cref->nd_next &&
	   (NIL_P(cref->nd_clss) || FL_TEST(cref->nd_clss, FL_SINGLETON) ||
	    (cref->flags & NODE_FL_CREF_PUSHED_BY_EVAL))) {
	cref = cref->nd_next;
    }
    if (!cref->nd_next) {
	rb_warn("class variable access from toplevel");
    }

    klass = vm_get_iclass(cfp, cref->nd_clss);

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
vm_getivar(VALUE obj, ID id, IC ic, rb_call_info_t *ci, int is_attr)
{
#if USE_IC_FOR_IVAR
    if (RB_TYPE_P(obj, T_OBJECT)) {
	VALUE val = Qundef;
	VALUE klass = RBASIC(obj)->klass;
	const long len = ROBJECT_NUMIV(obj);
	const VALUE *const ptr = ROBJECT_IVPTR(obj);

	if (LIKELY(is_attr ? ci->aux.index > 0 : ic->ic_serial == RCLASS_SERIAL(klass))) {
	    int index = !is_attr ? (int)ic->ic_value.index : ci->aux.index - 1;

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
			ci->aux.index = (int)index + 1;
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
vm_setivar(VALUE obj, ID id, VALUE val, IC ic, rb_call_info_t *ci, int is_attr)
{
#if USE_IC_FOR_IVAR
    rb_check_frozen(obj);

    if (RB_TYPE_P(obj, T_OBJECT)) {
	VALUE klass = RBASIC(obj)->klass;
	st_data_t index;

	if (LIKELY(
	    (!is_attr && ic->ic_serial == RCLASS_SERIAL(klass)) ||
	    (is_attr && ci->aux.index > 0))) {
	    long index = !is_attr ? (long)ic->ic_value.index : ci->aux.index-1;
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
		    ci->aux.index = (int)(index + 1);
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
vm_throw_continue(rb_thread_t *th, VALUE throwobj)
{
    /* continue throw */
    VALUE err = throwobj;

    if (FIXNUM_P(err)) {
	th->state = FIX2INT(err);
    }
    else if (SYMBOL_P(err)) {
	th->state = TAG_THROW;
    }
    else if (BUILTIN_TYPE(err) == T_NODE) {
	th->state = GET_THROWOBJ_STATE(err);
    }
    else {
	th->state = TAG_RAISE;
	/*th->state = FIX2INT(rb_ivar_get(err, idThrowState));*/
    }
    return err;
}

static VALUE
vm_throw_start(rb_thread_t * const th, rb_control_frame_t * const reg_cfp, int state, const int flag, const rb_num_t level, const VALUE throwobj)
{
    rb_control_frame_t *escape_cfp = NULL;
    const rb_control_frame_t * const eocfp = RUBY_VM_END_CONTROL_FRAME(th); /* end of control frame pointer */

    if (flag != 0) {
	/* do nothing */
    }
    else if (state == TAG_BREAK) {
	int is_orphan = 1;
	VALUE *ep = GET_EP();
	rb_iseq_t *base_iseq = GET_ISEQ();
	escape_cfp = reg_cfp;

	while (base_iseq->type != ISEQ_TYPE_BLOCK) {
	    if (escape_cfp->iseq->type == ISEQ_TYPE_CLASS) {
		escape_cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(escape_cfp);
		ep = escape_cfp->ep;
		base_iseq = escape_cfp->iseq;
	    }
	    else {
		ep = VM_EP_PREV_EP(ep);
		base_iseq = base_iseq->parent_iseq;
		escape_cfp = rb_vm_search_cf_from_ep(th, escape_cfp, ep);
		assert(escape_cfp->iseq == base_iseq);
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
		    const VALUE epc = escape_cfp->pc - escape_cfp->iseq->iseq_encoded;
		    const rb_iseq_t * const iseq = escape_cfp->iseq;
		    const struct iseq_catch_table * const ct = iseq->catch_table;
		    const int ct_size = ct->size;
		    int i;

		    for (i=0; i<ct_size; i++) {
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

	    if (lep == target_lep && escape_cfp->iseq->type == ISEQ_TYPE_CLASS) {
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

	    if (escape_cfp->ep == target_lep && escape_cfp->iseq->type == ISEQ_TYPE_METHOD) {
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
    return (VALUE)NEW_THROW_OBJECT(throwobj, (VALUE)escape_cfp, state);
}

static VALUE
vm_throw(rb_thread_t *th, rb_control_frame_t *reg_cfp,
	 rb_num_t throw_state, VALUE throwobj)
{
    const int state = (int)(throw_state & 0xff);
    const int flag = (int)(throw_state & 0x8000);
    const rb_num_t level = throw_state >> 16;

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

static VALUE vm_call_general(rb_thread_t *th, rb_control_frame_t *reg_cfp, rb_call_info_t *ci);

static void
vm_search_method(rb_call_info_t *ci, VALUE recv)
{
    VALUE klass = CLASS_OF(recv);

#if OPT_INLINE_METHOD_CACHE
    if (LIKELY(GET_GLOBAL_METHOD_STATE() == ci->method_state && RCLASS_SERIAL(klass) == ci->class_serial)) {
	/* cache hit! */
	return;
    }
#endif

    ci->me = rb_method_entry(klass, ci->mid, &ci->defined_class);
    ci->klass = klass;
    ci->call = vm_call_general;
#if OPT_INLINE_METHOD_CACHE
    ci->method_state = GET_GLOBAL_METHOD_STATE();
    ci->class_serial = RCLASS_SERIAL(klass);
#endif
}

static inline int
check_cfunc(const rb_method_entry_t *me, VALUE (*func)())
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
opt_eq_func(VALUE recv, VALUE obj, CALL_INFO ci)
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
	vm_search_method(ci, recv);

	if (check_cfunc(ci->me, rb_obj_equal)) {
	    return recv == obj ? Qtrue : Qfalse;
	}
    }

    return Qundef;
}

VALUE
rb_equal_opt(VALUE obj1, VALUE obj2)
{
    rb_call_info_t ci;
    ci.mid = idEq;
    ci.klass = 0;
    ci.method_state = 0;
    ci.me = NULL;
    ci.defined_class = 0;
    return opt_eq_func(obj1, obj2, &ci);
}

static VALUE
vm_call0(rb_thread_t*, VALUE, ID, int, const VALUE*, const rb_method_entry_t*, VALUE);

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
	VALUE defined_class;
	rb_method_entry_t *me = rb_method_entry_with_refinements(CLASS_OF(pattern), idEqq, &defined_class);
	if (me) {
	    return vm_call0(GET_THREAD(), pattern, idEqq, 1, &target, me, defined_class);
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
    VALUE *bp = prev_cfp->sp + cfp->iseq->local_size + 1;

    if (cfp->iseq->type == ISEQ_TYPE_METHOD) {
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

static VALUE vm_call_iseq_setup_2(rb_thread_t *th, rb_control_frame_t *cfp, rb_call_info_t *ci);
static inline VALUE vm_call_iseq_setup_normal(rb_thread_t *th, rb_control_frame_t *cfp, rb_call_info_t *ci);
static inline VALUE vm_call_iseq_setup_tailcall(rb_thread_t *th, rb_control_frame_t *cfp, rb_call_info_t *ci);


static inline VALUE
vm_callee_setup_block_arg_arg0_check(VALUE *argv)
{
    VALUE ary, arg0 = argv[0];
    ary = rb_check_array_type(arg0);
    argv[0] = arg0;
    return ary;
}

static inline int
vm_callee_setup_block_arg_arg0_splat(rb_control_frame_t *cfp, const rb_iseq_t *iseq, VALUE *argv, VALUE ary)
{
    int i;
    long len = RARRAY_LEN(ary);

    CHECK_VM_STACK_OVERFLOW(cfp, iseq->param.lead_num);

    for (i=0; i<len && i<iseq->param.lead_num; i++) {
	argv[i] = RARRAY_AREF(ary, i);
    }

    return i;
}

static inline int
simple_iseq_p(const rb_iseq_t *iseq)
{
    return iseq->param.flags.has_opt == FALSE &&
           iseq->param.flags.has_rest == FALSE &&
	   iseq->param.flags.has_post == FALSE &&
	   iseq->param.flags.has_kw == FALSE &&
	   iseq->param.flags.has_kwrest == FALSE &&
	   iseq->param.flags.has_block == FALSE;
}

static inline void
vm_callee_setup_block_arg(rb_thread_t *th, rb_call_info_t *ci, const rb_iseq_t *iseq, VALUE *argv, const enum arg_setup_type arg_setup_type)
{
    if (LIKELY(simple_iseq_p(iseq))) {
	rb_control_frame_t *cfp = th->cfp;
	VALUE arg0;

	CALLER_SETUP_ARG(cfp, ci); /* splat arg */

	if (arg_setup_type == arg_setup_block &&
	    ci->argc == 1 &&
	    iseq->param.flags.has_lead &&
	    !iseq->param.flags.ambiguous_param0 &&
	    !NIL_P(arg0 = vm_callee_setup_block_arg_arg0_check(argv))) {
	    ci->argc = vm_callee_setup_block_arg_arg0_splat(cfp, iseq, argv, arg0);
	}

	if (ci->argc != iseq->param.lead_num) {
	    if (arg_setup_type == arg_setup_block) {
		if (ci->argc < iseq->param.lead_num) {
		    int i;
		    CHECK_VM_STACK_OVERFLOW(cfp, iseq->param.lead_num);
		    for (i=ci->argc; i<iseq->param.lead_num; i++) argv[i] = Qnil;
		    ci->argc = iseq->param.lead_num; /* fill rest parameters */
		}
		else if (ci->argc > iseq->param.lead_num) {
		    ci->argc = iseq->param.lead_num; /* simply truncate arguments */
		}
	    }
	    else if (arg_setup_type == arg_setup_lambda &&
		     ci->argc == 1 &&
		     !NIL_P(arg0 = vm_callee_setup_block_arg_arg0_check(argv)) &&
		     RARRAY_LEN(arg0) == iseq->param.lead_num) {
		ci->argc = vm_callee_setup_block_arg_arg0_splat(cfp, iseq, argv, arg0);
	    }
	    else {
		argument_arity_error(th, iseq, ci->argc, iseq->param.lead_num, iseq->param.lead_num);
	    }
	}

	ci->aux.opt_pc = 0;
    }
    else {
	ci->aux.opt_pc = setup_parameters_complex(th, iseq, ci, argv, arg_setup_type);
    }
}

static inline void
vm_callee_setup_arg(rb_thread_t *th, rb_call_info_t *ci, const rb_iseq_t *iseq, VALUE *argv)
{
    if (LIKELY(simple_iseq_p(iseq))) {
	rb_control_frame_t *cfp = th->cfp;

	CALLER_SETUP_ARG(cfp, ci); /* splat arg */

	if (ci->argc != iseq->param.lead_num) {
	    argument_arity_error(th, iseq, ci->argc, iseq->param.lead_num, iseq->param.lead_num);
	}

	ci->aux.opt_pc = 0;

	CI_SET_FASTPATH(ci,
			(UNLIKELY(ci->flag & VM_CALL_TAILCALL) ? vm_call_iseq_setup_tailcall : vm_call_iseq_setup_normal),
			(!IS_ARGS_SPLAT(ci) && !IS_ARGS_KEYWORD(ci) && !(ci->me->flag & NOEX_PROTECTED)));
    }
    else {
	ci->aux.opt_pc = setup_parameters_complex(th, iseq, ci, argv, arg_setup_method);
    }
}

static VALUE
vm_call_iseq_setup(rb_thread_t *th, rb_control_frame_t *cfp, rb_call_info_t *ci)
{
    vm_callee_setup_arg(th, ci, ci->me->def->body.iseq, cfp->sp - ci->argc);
    return vm_call_iseq_setup_2(th, cfp, ci);
}

static VALUE
vm_call_iseq_setup_2(rb_thread_t *th, rb_control_frame_t *cfp, rb_call_info_t *ci)
{
    if (LIKELY(!(ci->flag & VM_CALL_TAILCALL))) {
	return vm_call_iseq_setup_normal(th, cfp, ci);
    }
    else {
	return vm_call_iseq_setup_tailcall(th, cfp, ci);
    }
}

static inline VALUE
vm_call_iseq_setup_normal(rb_thread_t *th, rb_control_frame_t *cfp, rb_call_info_t *ci)
{
    int i, local_size;
    VALUE *argv = cfp->sp - ci->argc;
    rb_iseq_t *iseq = ci->me->def->body.iseq;
    VALUE *sp = argv + iseq->param.size;

    /* clear local variables (arg_size...local_size) */
    for (i = iseq->param.size, local_size = iseq->local_size; i < local_size; i++) {
	*sp++ = Qnil;
    }

    vm_push_frame(th, iseq, VM_FRAME_MAGIC_METHOD, ci->recv, ci->defined_class,
		  VM_ENVVAL_BLOCK_PTR(ci->blockptr),
		  iseq->iseq_encoded + ci->aux.opt_pc, sp, 0, ci->me, iseq->stack_max);

    cfp->sp = argv - 1 /* recv */;
    return Qundef;
}

static inline VALUE
vm_call_iseq_setup_tailcall(rb_thread_t *th, rb_control_frame_t *cfp, rb_call_info_t *ci)
{
    int i;
    VALUE *argv = cfp->sp - ci->argc;
    rb_iseq_t *iseq = ci->me->def->body.iseq;
    VALUE *src_argv = argv;
    VALUE *sp_orig, *sp;
    VALUE finish_flag = VM_FRAME_TYPE_FINISH_P(cfp) ? VM_FRAME_FLAG_FINISH : 0;

    cfp = th->cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(th->cfp); /* pop cf */

    RUBY_VM_CHECK_INTS(th);

    sp_orig = sp = cfp->sp;

    /* push self */
    sp[0] = ci->recv;
    sp++;

    /* copy arguments */
    for (i=0; i < iseq->param.size; i++) {
	*sp++ = src_argv[i];
    }

    /* clear local variables */
    for (i = 0; i < iseq->local_size - iseq->param.size; i++) {
	*sp++ = Qnil;
    }

    vm_push_frame(th, iseq, VM_FRAME_MAGIC_METHOD | finish_flag,
		  ci->recv, ci->defined_class, VM_ENVVAL_BLOCK_PTR(ci->blockptr),
		  iseq->iseq_encoded + ci->aux.opt_pc, sp, 0, ci->me, iseq->stack_max);

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
static int vm_profile_counter[4];
#define VM_PROFILE_UP(x) (vm_profile_counter[x]++)
#define VM_PROFILE_ATEXIT() atexit(vm_profile_show_result)
static void
vm_profile_show_result(void)
{
    fprintf(stderr, "VM Profile results: \n");
    fprintf(stderr, "r->c call: %d\n", vm_profile_counter[0]);
    fprintf(stderr, "r->c popf: %d\n", vm_profile_counter[1]);
    fprintf(stderr, "c->c call: %d\n", vm_profile_counter[2]);
    fprintf(stderr, "r->c popf: %d\n", vm_profile_counter[3]);
}
#else
#define VM_PROFILE_UP(x)
#define VM_PROFILE_ATEXIT()
#endif

static inline
const rb_method_cfunc_t *
vm_method_cfunc_entry(const rb_method_entry_t *me)
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
# undef METHOD_BUG
      default:
	rb_bug("wrong method type: %d", me->def->type);
    }
#endif
    return &me->def->body.cfunc;
}

static VALUE
vm_call_cfunc_with_frame(rb_thread_t *th, rb_control_frame_t *reg_cfp, rb_call_info_t *ci)
{
    VALUE val;
    const rb_method_entry_t *me = ci->me;
    const rb_method_cfunc_t *cfunc = vm_method_cfunc_entry(me);
    int len = cfunc->argc;

    /* don't use `ci' after EXEC_EVENT_HOOK because ci can be override */
    VALUE recv = ci->recv;
    VALUE defined_class = ci->defined_class;
    rb_block_t *blockptr = ci->blockptr;
    int argc = ci->argc;

    RUBY_DTRACE_CMETHOD_ENTRY_HOOK(th, me->klass, me->called_id);
    EXEC_EVENT_HOOK(th, RUBY_EVENT_C_CALL, recv, me->called_id, me->klass, Qundef);

    vm_push_frame(th, 0, VM_FRAME_MAGIC_CFUNC, recv, defined_class,
		  VM_ENVVAL_BLOCK_PTR(blockptr), 0, th->cfp->sp, 1, me, 0);

    if (len >= 0) rb_check_arity(argc, len, len);

    reg_cfp->sp -= argc + 1;
    VM_PROFILE_UP(0);
    val = (*cfunc->invoker)(cfunc->func, recv, argc, reg_cfp->sp + 1);

    if (reg_cfp != th->cfp + 1) {
	rb_bug("vm_call_cfunc - cfp consistency error");
    }

    vm_pop_frame(th);

    EXEC_EVENT_HOOK(th, RUBY_EVENT_C_RETURN, recv, me->called_id, me->klass, val);
    RUBY_DTRACE_CMETHOD_RETURN_HOOK(th, me->klass, me->called_id);

    return val;
}

#if OPT_CALL_CFUNC_WITHOUT_FRAME
static VALUE
vm_call_cfunc_latter(rb_thread_t *th, rb_control_frame_t *reg_cfp, rb_call_info_t *ci)
{
    VALUE val;
    int argc = ci->argc;
    VALUE *argv = STACK_ADDR_FROM_TOP(argc);
    const rb_method_cfunc_t *cfunc = vm_method_cfunc_entry(ci->me);

    th->passed_ci = ci;
    reg_cfp->sp -= argc + 1;
    ci->aux.inc_sp = argc + 1;
    VM_PROFILE_UP(0);
    val = (*cfunc->invoker)(cfunc->func, ci, argv);

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
	VM_PROFILE_UP(1);
    }

    return val;
}

static VALUE
vm_call_cfunc(rb_thread_t *th, rb_control_frame_t *reg_cfp, rb_call_info_t *ci)
{
    VALUE val;
    const rb_method_entry_t *me = ci->me;
    int len = vm_method_cfunc_entry(me)->argc;
    VALUE recv = ci->recv;

    CALLER_SETUP_ARG(reg_cfp, ci);
    if (len >= 0) rb_check_arity(ci->argc, len, len);

    RUBY_DTRACE_CMETHOD_ENTRY_HOOK(th, me->klass, me->called_id);
    EXEC_EVENT_HOOK(th, RUBY_EVENT_C_CALL, recv, me->called_id, me->klass, Qnil);

    if (!(ci->me->flag & NOEX_PROTECTED) &&
	!(ci->flag & VM_CALL_ARGS_SPLAT) &&
	!(ci->kw_arg != NULL)) {
	CI_SET_FASTPATH(ci, vm_call_cfunc_latter, 1);
    }
    val = vm_call_cfunc_latter(th, reg_cfp, ci);

    EXEC_EVENT_HOOK(th, RUBY_EVENT_C_RETURN, recv, me->called_id, me->klass, val);
    RUBY_DTRACE_CMETHOD_RETURN_HOOK(th, me->klass, me->called_id);

    return val;
}

void
vm_call_cfunc_push_frame(rb_thread_t *th)
{
    rb_call_info_t *ci = th->passed_ci;
    const rb_method_entry_t *me = ci->me;
    th->passed_ci = 0;

    vm_push_frame(th, 0, VM_FRAME_MAGIC_CFUNC, ci->recv, ci->defined_class,
		  VM_ENVVAL_BLOCK_PTR(ci->blockptr), 0, th->cfp->sp + ci->aux.inc_sp, 1, me);

    if (ci->call != vm_call_general) {
	ci->call = vm_call_cfunc_with_frame;
    }
}
#else /* OPT_CALL_CFUNC_WITHOUT_FRAME */
static VALUE
vm_call_cfunc(rb_thread_t *th, rb_control_frame_t *reg_cfp, rb_call_info_t *ci)
{
    CALLER_SETUP_ARG(reg_cfp, ci);
    return vm_call_cfunc_with_frame(th, reg_cfp, ci);
}
#endif

static VALUE
vm_call_ivar(rb_thread_t *th, rb_control_frame_t *cfp, rb_call_info_t *ci)
{
    VALUE val = vm_getivar(ci->recv, ci->me->def->body.attr.id, 0, ci, 1);
    cfp->sp -= 1;
    return val;
}

static VALUE
vm_call_attrset(rb_thread_t *th, rb_control_frame_t *cfp, rb_call_info_t *ci)
{
    VALUE val = vm_setivar(ci->recv, ci->me->def->body.attr.id, *(cfp->sp - 1), 0, ci, 1);
    cfp->sp -= 2;
    return val;
}

static inline VALUE
vm_call_bmethod_body(rb_thread_t *th, rb_call_info_t *ci, const VALUE *argv)
{
    rb_proc_t *proc;
    VALUE val;

    /* control block frame */
    th->passed_bmethod_me = ci->me;
    GetProcPtr(ci->me->def->body.proc, proc);
    val = vm_invoke_proc(th, proc, ci->recv, ci->defined_class, ci->argc, argv, ci->blockptr);

    return val;
}

static VALUE
vm_call_bmethod(rb_thread_t *th, rb_control_frame_t *cfp, rb_call_info_t *ci)
{
    VALUE *argv;

    CALLER_SETUP_ARG(cfp, ci);

    argv = ALLOCA_N(VALUE, ci->argc);
    MEMCPY(argv, cfp->sp - ci->argc, VALUE, ci->argc);
    cfp->sp += - ci->argc - 1;

    return vm_call_bmethod_body(th, ci, argv);
}

static int
ci_missing_reason(const rb_call_info_t *ci)
{
    int stat = 0;
    if (ci->flag & VM_CALL_VCALL) {
	stat |= NOEX_VCALL;
    }
    if (ci->flag & VM_CALL_SUPER) {
	stat |= NOEX_SUPER;
    }
    return stat;
}

static
#ifdef _MSC_VER
__forceinline
#else
inline
#endif
VALUE vm_call_method(rb_thread_t *th, rb_control_frame_t *cfp, rb_call_info_t *ci);

static VALUE
vm_call_opt_send(rb_thread_t *th, rb_control_frame_t *reg_cfp, rb_call_info_t *ci)
{
    int i;
    VALUE sym;
    rb_call_info_t ci_entry;

    CALLER_SETUP_ARG(reg_cfp, ci);

    i = ci->argc - 1;

    if (ci->argc == 0) {
	rb_raise(rb_eArgError, "no method name given");
    }

    ci_entry = *ci; /* copy ci entry */
    ci = &ci_entry;
    ci->kw_arg = NULL; /* TODO: delegate kw_arg without making a Hash object */

    sym = TOPN(i);

    if (!(ci->mid = rb_check_id(&sym))) {
	if (rb_method_basic_definition_p(CLASS_OF(ci->recv), idMethodMissing)) {
	    VALUE exc = make_no_method_exception(rb_eNoMethodError, NULL, ci->recv, rb_long2int(ci->argc), &TOPN(i));
	    rb_exc_raise(exc);
	}
	TOPN(i) = rb_str_intern(sym);
	ci->mid = idMethodMissing;
	th->method_missing_reason = ci->aux.missing_reason = ci_missing_reason(ci);
    }
    else {
	/* shift arguments */
	if (i > 0) {
	    MEMMOVE(&TOPN(i), &TOPN(i-1), VALUE, i);
	}
	ci->argc -= 1;
	DEC_SP(1);
    }
    ci->me = rb_method_entry_without_refinements(CLASS_OF(ci->recv), ci->mid, &ci->defined_class);

    ci->flag = VM_CALL_FCALL | VM_CALL_OPT_SEND;

    return vm_call_method(th, reg_cfp, ci);
}

static VALUE
vm_call_opt_call(rb_thread_t *th, rb_control_frame_t *cfp, rb_call_info_t *ci)
{
    rb_proc_t *proc;
    int argc;
    VALUE *argv;

    CALLER_SETUP_ARG(cfp, ci);

    argc = ci->argc;
    argv = ALLOCA_N(VALUE, argc);
    GetProcPtr(ci->recv, proc);
    MEMCPY(argv, cfp->sp - argc, VALUE, argc);
    cfp->sp -= argc + 1;

    return rb_vm_invoke_proc(th, proc, argc, argv, ci->blockptr);
}

static VALUE
vm_call_method_missing(rb_thread_t *th, rb_control_frame_t *reg_cfp, rb_call_info_t *ci)
{
    VALUE *argv = STACK_ADDR_FROM_TOP(ci->argc);
    rb_call_info_t ci_entry;

    CALLER_SETUP_ARG(reg_cfp, ci);

    ci_entry.flag = VM_CALL_FCALL | VM_CALL_OPT_SEND;
    ci_entry.argc = ci->argc+1;
    ci_entry.mid = idMethodMissing;
    ci_entry.blockptr = ci->blockptr;
    ci_entry.recv = ci->recv;
    ci_entry.me = rb_method_entry(CLASS_OF(ci_entry.recv), idMethodMissing, &ci_entry.defined_class);
    ci_entry.kw_arg = NULL;

    /* shift arguments: m(a, b, c) #=> method_missing(:m, a, b, c) */
    CHECK_VM_STACK_OVERFLOW(reg_cfp, 1);
    if (ci->argc > 0) {
	MEMMOVE(argv+1, argv, VALUE, ci->argc);
    }
    argv[0] = ID2SYM(ci->mid);
    INC_SP(1);

    th->method_missing_reason = ci->aux.missing_reason;
    return vm_call_method(th, reg_cfp, &ci_entry);
}

static inline VALUE
find_refinement(VALUE refinements, VALUE klass)
{
    if (NIL_P(refinements)) {
	return Qnil;
    }
    return rb_hash_lookup(refinements, klass);
}

static int rb_method_definition_eq(const rb_method_definition_t *d1, const rb_method_definition_t *d2);
static VALUE vm_call_super_method(rb_thread_t *th, rb_control_frame_t *reg_cfp, rb_call_info_t *ci);

static rb_control_frame_t *
current_method_entry(rb_thread_t *th, rb_control_frame_t *cfp)
{
    rb_control_frame_t *top_cfp = cfp;

    if (cfp->iseq && cfp->iseq->type == ISEQ_TYPE_BLOCK) {
	rb_iseq_t *local_iseq = cfp->iseq->local_iseq;
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

static
#ifdef _MSC_VER
__forceinline
#else
inline
#endif
VALUE
vm_call_method(rb_thread_t *th, rb_control_frame_t *cfp, rb_call_info_t *ci)
{
    int enable_fastpath = 1;
    rb_call_info_t ci_temp;

  start_method_dispatch:
    if (ci->me != 0) {
	if ((ci->me->flag == 0)) {
	    VALUE klass;

	  normal_method_dispatch:
	    switch (ci->me->def->type) {
	      case VM_METHOD_TYPE_ISEQ:{
		CI_SET_FASTPATH(ci, vm_call_iseq_setup, enable_fastpath);
		return vm_call_iseq_setup(th, cfp, ci);
	      }
	      case VM_METHOD_TYPE_NOTIMPLEMENTED:
	      case VM_METHOD_TYPE_CFUNC:
		CI_SET_FASTPATH(ci, vm_call_cfunc, enable_fastpath);
		return vm_call_cfunc(th, cfp, ci);
	      case VM_METHOD_TYPE_ATTRSET:{
		CALLER_SETUP_ARG(cfp, ci);
		rb_check_arity(ci->argc, 1, 1);
		ci->aux.index = 0;
		CI_SET_FASTPATH(ci, vm_call_attrset, enable_fastpath && !(ci->flag & VM_CALL_ARGS_SPLAT) && ci->kw_arg == NULL);
		return vm_call_attrset(th, cfp, ci);
	      }
	      case VM_METHOD_TYPE_IVAR:{
		CALLER_SETUP_ARG(cfp, ci);
		rb_check_arity(ci->argc, 0, 0);
		ci->aux.index = 0;
		CI_SET_FASTPATH(ci, vm_call_ivar, enable_fastpath && !(ci->flag & VM_CALL_ARGS_SPLAT));
		return vm_call_ivar(th, cfp, ci);
	      }
	      case VM_METHOD_TYPE_MISSING:{
		ci->aux.missing_reason = 0;
		CI_SET_FASTPATH(ci, vm_call_method_missing, enable_fastpath);
		return vm_call_method_missing(th, cfp, ci);
	      }
	      case VM_METHOD_TYPE_BMETHOD:{
		CI_SET_FASTPATH(ci, vm_call_bmethod, enable_fastpath);
		return vm_call_bmethod(th, cfp, ci);
	      }
	      case VM_METHOD_TYPE_ZSUPER:{
		klass = ci->me->klass;
		klass = RCLASS_ORIGIN(klass);
	      zsuper_method_dispatch:
		klass = RCLASS_SUPER(klass);
		if (!klass) {
		    ci->me = 0;
		    goto start_method_dispatch;
		}
		ci_temp = *ci;
		ci = &ci_temp;

		ci->me = rb_method_entry(klass, ci->mid, &ci->defined_class);

		if (ci->me != 0) {
		    goto normal_method_dispatch;
		}
		else {
		    goto start_method_dispatch;
		}
	      }
	      case VM_METHOD_TYPE_OPTIMIZED:{
		switch (ci->me->def->body.optimize_type) {
		  case OPTIMIZED_METHOD_TYPE_SEND:
		    CI_SET_FASTPATH(ci, vm_call_opt_send, enable_fastpath);
		    return vm_call_opt_send(th, cfp, ci);
		  case OPTIMIZED_METHOD_TYPE_CALL:
		    CI_SET_FASTPATH(ci, vm_call_opt_call, enable_fastpath);
		    return vm_call_opt_call(th, cfp, ci);
		  default:
		    rb_bug("vm_call_method: unsupported optimized method type (%d)",
			   ci->me->def->body.optimize_type);
		}
		break;
	      }
	      case VM_METHOD_TYPE_UNDEF:
		break;
	      case VM_METHOD_TYPE_REFINED:{
		NODE *cref = rb_vm_get_cref(cfp->iseq, cfp->ep);
		VALUE refinements = cref ? cref->nd_refinements : Qnil;
		VALUE refinement, defined_class;
		rb_method_entry_t *me;

		refinement = find_refinement(refinements,
					     ci->defined_class);
		if (NIL_P(refinement)) {
		    goto no_refinement_dispatch;
		}
		me = rb_method_entry(refinement, ci->mid, &defined_class);
		if (me) {
		    if (ci->call == vm_call_super_method) {
			rb_control_frame_t *top_cfp = current_method_entry(th, cfp);
			if (top_cfp->me &&
			    rb_method_definition_eq(me->def, top_cfp->me->def)) {
			    goto no_refinement_dispatch;
			}
		    }
		    ci->me = me;
		    ci->defined_class = defined_class;
		    if (me->def->type != VM_METHOD_TYPE_REFINED) {
			goto start_method_dispatch;
		    }
		}

	      no_refinement_dispatch:
		if (ci->me->def->body.orig_me) {
		    ci->me = ci->me->def->body.orig_me;
		    if (UNDEFINED_METHOD_ENTRY_P(ci->me)) {
			ci->me = 0;
		    }
		    goto start_method_dispatch;
		}
		else {
		    klass = ci->me->klass;
		    goto zsuper_method_dispatch;
		}
	      }
	    }
	    rb_bug("vm_call_method: unsupported method type (%d)", ci->me->def->type);
	}
	else {
	    int noex_safe;
	    if (!(ci->flag & VM_CALL_FCALL) && (ci->me->flag & NOEX_MASK) & NOEX_PRIVATE) {
		int stat = NOEX_PRIVATE;

		if (ci->flag & VM_CALL_VCALL) {
		    stat |= NOEX_VCALL;
		}
		ci->aux.missing_reason = stat;
		CI_SET_FASTPATH(ci, vm_call_method_missing, 1);
		return vm_call_method_missing(th, cfp, ci);
	    }
	    else if (!(ci->flag & VM_CALL_OPT_SEND) && (ci->me->flag & NOEX_MASK) & NOEX_PROTECTED) {
		enable_fastpath = 0;
		if (!rb_obj_is_kind_of(cfp->self, ci->defined_class)) {
		    ci->aux.missing_reason = NOEX_PROTECTED;
		    return vm_call_method_missing(th, cfp, ci);
		}
		else {
		    goto normal_method_dispatch;
		}
	    }
	    else if ((noex_safe = NOEX_SAFE(ci->me->flag)) > th->safe_level && (noex_safe > 2)) {
		rb_raise(rb_eSecurityError, "calling insecure method: %"PRIsVALUE, rb_id2str(ci->mid));
	    }
	    else {
		goto normal_method_dispatch;
	    }
	}
    }
    else {
	/* method missing */
	const int stat = ci_missing_reason(ci);
	if (ci->mid == idMethodMissing) {
	    rb_control_frame_t *reg_cfp = cfp;
	    VALUE *argv = STACK_ADDR_FROM_TOP(ci->argc);
	    rb_raise_method_missing(th, ci->argc, argv, ci->recv, stat);
	}
	else {
	    ci->aux.missing_reason = stat;
	    CI_SET_FASTPATH(ci, vm_call_method_missing, 1);
	    return vm_call_method_missing(th, cfp, ci);
	}
    }

    rb_bug("vm_call_method: unreachable");
}

static VALUE
vm_call_general(rb_thread_t *th, rb_control_frame_t *reg_cfp, rb_call_info_t *ci)
{
    return vm_call_method(th, reg_cfp, ci);
}

static VALUE
vm_call_super_method(rb_thread_t *th, rb_control_frame_t *reg_cfp, rb_call_info_t *ci)
{
    return vm_call_method(th, reg_cfp, ci);
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

static int
vm_search_superclass(rb_control_frame_t *reg_cfp, rb_iseq_t *iseq, VALUE sigval, rb_call_info_t *ci)
{
    while (iseq && !iseq->klass) {
	iseq = iseq->parent_iseq;
    }

    if (iseq == 0) {
	return -1;
    }

    ci->mid = iseq->defined_method_id;

    if (iseq != iseq->local_iseq) {
	/* defined by Module#define_method() */
	rb_control_frame_t *lcfp = GET_CFP();

	if (!sigval) {
	    /* zsuper */
	    return -2;
	}

	while (lcfp->iseq != iseq) {
	    rb_thread_t *th = GET_THREAD();
	    VALUE *tep = VM_EP_PREV_EP(lcfp->ep);
	    while (1) {
		lcfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(lcfp);
		if (RUBY_VM_CONTROL_FRAME_STACK_OVERFLOW_P(th, lcfp)) {
		    return -1;
		}
		if (lcfp->ep == tep) {
		    break;
		}
	    }
	}

	/* temporary measure for [Bug #2420] [Bug #3136] */
	if (!lcfp->me) {
	    return -1;
	}

	ci->mid = lcfp->me->def->original_id;
	ci->klass = vm_search_normal_superclass(lcfp->klass);
    }
    else {
	ci->klass = vm_search_normal_superclass(reg_cfp->klass);
    }

    return 0;
}

static void
vm_search_super_method(rb_thread_t *th, rb_control_frame_t *reg_cfp, rb_call_info_t *ci)
{
    VALUE current_defined_class;
    rb_iseq_t *iseq = GET_ISEQ();
    VALUE sigval = TOPN(ci->argc);

    current_defined_class = GET_CFP()->klass;
    if (NIL_P(current_defined_class)) {
	vm_super_outside();
    }

    if (!NIL_P(RCLASS_REFINED_CLASS(current_defined_class))) {
	current_defined_class = RCLASS_REFINED_CLASS(current_defined_class);
    }

    if (BUILTIN_TYPE(current_defined_class) != T_MODULE &&
	BUILTIN_TYPE(current_defined_class) != T_ICLASS && /* bound UnboundMethod */
	!FL_TEST(current_defined_class, RMODULE_INCLUDED_INTO_REFINEMENT) &&
	!rb_obj_is_kind_of(ci->recv, current_defined_class)) {
	VALUE m = RB_TYPE_P(current_defined_class, T_ICLASS) ?
	    RBASIC(current_defined_class)->klass : current_defined_class;

	rb_raise(rb_eTypeError,
		 "self has wrong type to call super in this context: "
		 "%"PRIsVALUE" (expected %"PRIsVALUE")",
		 rb_obj_class(ci->recv), m);
    }

    switch (vm_search_superclass(GET_CFP(), iseq, sigval, ci)) {
      case -1:
	vm_super_outside();
      case -2:
	rb_raise(rb_eRuntimeError,
		 "implicit argument passing of super from method defined"
		 " by define_method() is not supported."
		 " Specify all arguments explicitly.");
    }
    if (!ci->klass) {
	/* bound instance method of module */
	ci->aux.missing_reason = NOEX_SUPER;
	CI_SET_FASTPATH(ci, vm_call_method_missing, 1);
	return;
    }

    /* TODO: use inline cache */
    ci->me = rb_method_entry(ci->klass, ci->mid, &ci->defined_class);
    ci->call = vm_call_super_method;

    while (iseq && !iseq->klass) {
	iseq = iseq->parent_iseq;
    }

    if (ci->me && ci->me->def->type == VM_METHOD_TYPE_ISEQ && ci->me->def->body.iseq == iseq) {
	ci->klass = RCLASS_SUPER(ci->defined_class);
	ci->me = rb_method_entry(ci->klass, ci->mid, &ci->defined_class);
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

static inline VALUE
vm_yield_with_cfunc(rb_thread_t *th, const rb_block_t *block,
		    VALUE self, VALUE defined_class,
		    int argc, const VALUE *argv,
		    const rb_block_t *blockargptr)
{
    NODE *ifunc = (NODE *) block->iseq;
    VALUE val, arg, blockarg;
    int lambda = block_proc_is_lambda(block->proc);

    if (lambda) {
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
		  self, defined_class,
		  VM_ENVVAL_PREV_EP_PTR(block->ep), 0,
		  th->cfp->sp, 1, th->passed_bmethod_me, 0);

    val = (*ifunc->nd_cfnc) (arg, ifunc->nd_tval, argc, argv, blockarg);

    th->cfp++;
    return val;
}

static int
vm_yield_callee_setup_arg(rb_thread_t *th, rb_call_info_t *ci, const rb_iseq_t *iseq, VALUE *argv, enum arg_setup_type arg_setup_type)
{
    vm_callee_setup_block_arg(th, ci, iseq, argv, arg_setup_type);
    return ci->aux.opt_pc;
}

static int
vm_yield_setup_args(rb_thread_t *th, const rb_iseq_t *iseq, const int argc, VALUE *argv, const rb_block_t *blockptr, enum arg_setup_type arg_setup_type)
{
    rb_call_info_t ci_entry;
    ci_entry.argc = argc;
    ci_entry.blockptr = (rb_block_t *)blockptr;
    ci_entry.flag = 0;
    ci_entry.kw_arg = NULL;
    ci_entry.me = NULL;

    return vm_yield_callee_setup_arg(th, &ci_entry, iseq, argv, arg_setup_type);
}

/* ruby iseq -> ruby block iseq */
static VALUE
vm_invoke_block(rb_thread_t *th, rb_control_frame_t *reg_cfp, rb_call_info_t *ci)
{
    const rb_block_t *block = VM_CF_BLOCK_PTR(reg_cfp);
    rb_iseq_t *iseq;
    VALUE type = GET_ISEQ()->local_iseq->type;

    if ((type != ISEQ_TYPE_METHOD && type != ISEQ_TYPE_CLASS) || block == 0) {
	rb_vm_localjump_error("no block given (yield)", Qnil, 0);
    }
    iseq = block->iseq;

    if (!RUBY_VM_IFUNC_P(iseq)) {
	int opt_pc;
	const int arg_size = iseq->param.size;
	int is_lambda = block_proc_is_lambda(block->proc);
	VALUE * const rsp = GET_SP() - ci->argc;

	opt_pc = vm_yield_callee_setup_arg(th, ci, iseq, rsp, is_lambda ? arg_setup_lambda : arg_setup_block);

	SET_SP(rsp);

	vm_push_frame(th, iseq,
		      is_lambda ? VM_FRAME_MAGIC_LAMBDA : VM_FRAME_MAGIC_BLOCK,
		      block->self,
		      block->klass,
		      VM_ENVVAL_PREV_EP_PTR(block->ep),
		      iseq->iseq_encoded + opt_pc,
		      rsp + arg_size,
		      iseq->local_size - arg_size, 0, iseq->stack_max);

	return Qundef;
    }
    else {
	VALUE val;
	int argc;
	CALLER_SETUP_ARG(th->cfp, ci);
	argc = ci->argc;
	val = vm_yield_with_cfunc(th, block, block->self, block->klass, argc, STACK_ADDR_FROM_TOP(argc), 0);
	POPN(argc); /* TODO: should put before C/yield? */
	return val;
    }
}

static VALUE
vm_make_proc_with_iseq(rb_iseq_t *blockiseq)
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
