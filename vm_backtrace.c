/**********************************************************************

  vm_backtrace.c -

  $Author: ko1 $
  created at: Sun Jun 03 00:14:20 2012

  Copyright (C) 1993-2012 Yukihiro Matsumoto

**********************************************************************/

#include "eval_intern.h"
#include "internal.h"
#include "internal/class.h"
#include "internal/error.h"
#include "internal/vm.h"
#include "iseq.h"
#include "ruby/debug.h"
#include "ruby/encoding.h"
#include "vm_core.h"

static VALUE rb_cBacktrace;
static VALUE rb_cBacktraceLocation;

static VALUE
id2str(ID id)
{
    VALUE str = rb_id2str(id);
    if (!str) return Qnil;
    return str;
}
#define rb_id2str(id) id2str(id)

#define BACKTRACE_START 0
#define ALL_BACKTRACE_LINES -1

inline static int
calc_pos(const rb_iseq_t *iseq, const VALUE *pc, int *lineno, int *node_id)
{
    VM_ASSERT(iseq);

    if (pc == NULL) {
        if (ISEQ_BODY(iseq)->type == ISEQ_TYPE_TOP) {
            VM_ASSERT(! ISEQ_BODY(iseq)->local_table);
            VM_ASSERT(! ISEQ_BODY(iseq)->local_table_size);
            return 0;
        }
        if (lineno) *lineno = ISEQ_BODY(iseq)->location.first_lineno;
#ifdef USE_ISEQ_NODE_ID
        if (node_id) *node_id = -1;
#endif
        return 1;
    }
    else {
        VM_ASSERT(ISEQ_BODY(iseq));
        VM_ASSERT(ISEQ_BODY(iseq)->iseq_encoded);
        VM_ASSERT(ISEQ_BODY(iseq)->iseq_size);

        ptrdiff_t n = pc - ISEQ_BODY(iseq)->iseq_encoded;
        VM_ASSERT(n >= 0);
#if SIZEOF_PTRDIFF_T > SIZEOF_INT
        VM_ASSERT(n <= (ptrdiff_t)UINT_MAX);
#endif
        VM_ASSERT((unsigned int)n <= ISEQ_BODY(iseq)->iseq_size);
        ASSUME(n >= 0);
        size_t pos = n; /* no overflow */
        if (LIKELY(pos)) {
            /* use pos-1 because PC points next instruction at the beginning of instruction */
            pos--;
        }
#if VMDEBUG && defined(HAVE_BUILTIN___BUILTIN_TRAP)
        else {
            /* SDR() is not possible; that causes infinite loop. */
            rb_print_backtrace(stderr);
            __builtin_trap();
        }
#endif
        if (lineno) *lineno = rb_iseq_line_no(iseq, pos);
#ifdef USE_ISEQ_NODE_ID
        if (node_id) *node_id = rb_iseq_node_id(iseq, pos);
#endif
        return 1;
    }
}

inline static int
calc_lineno(const rb_iseq_t *iseq, const VALUE *pc)
{
    int lineno;
    if (calc_pos(iseq, pc, &lineno, NULL)) return lineno;
    return 0;
}

#ifdef USE_ISEQ_NODE_ID
inline static int
calc_node_id(const rb_iseq_t *iseq, const VALUE *pc)
{
    int node_id;
    if (calc_pos(iseq, pc, NULL, &node_id)) return node_id;
    return -1;
}
#endif

int
rb_vm_get_sourceline(const rb_control_frame_t *cfp)
{
    if (VM_FRAME_RUBYFRAME_P(cfp) && cfp->iseq) {
        const rb_iseq_t *iseq = cfp->iseq;
        int line = calc_lineno(iseq, cfp->pc);
        if (line != 0) {
            return line;
        }
        else {
            return ISEQ_BODY(iseq)->location.first_lineno;
        }
    }
    else {
        return 0;
    }
}

typedef struct rb_backtrace_location_struct {
    const rb_callable_method_entry_t *cme;
    const rb_iseq_t *iseq;
    const VALUE *pc;
} rb_backtrace_location_t;

struct valued_frame_info {
    rb_backtrace_location_t *loc;
    VALUE btobj;
};

static void
location_mark(void *ptr)
{
    struct valued_frame_info *vfi = (struct valued_frame_info *)ptr;
    rb_gc_mark(vfi->btobj);
}

static void
location_mark_entry(rb_backtrace_location_t *fi)
{
    rb_gc_mark((VALUE)fi->cme);
    if (fi->iseq) rb_gc_mark_movable((VALUE)fi->iseq);
}

static const rb_data_type_t location_data_type = {
    "frame_info",
    {
        location_mark,
        RUBY_TYPED_DEFAULT_FREE,
        NULL, // No external memory to report,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED | RUBY_TYPED_EMBEDDABLE
};

int
rb_frame_info_p(VALUE obj)
{
    return rb_typeddata_is_kind_of(obj, &location_data_type);
}

static inline rb_backtrace_location_t *
location_ptr(VALUE locobj)
{
    struct valued_frame_info *vloc;
    TypedData_Get_Struct(locobj, struct valued_frame_info, &location_data_type, vloc);
    return vloc->loc;
}

static int
location_lineno(rb_backtrace_location_t *loc)
{
    if (loc->iseq) {
        return calc_lineno(loc->iseq, loc->pc);
    }
    return 0;
}

/*
 * Returns the line number of this frame.
 *
 * For example, using +caller_locations.rb+ from Thread::Backtrace::Location
 *
 *	loc = c(0..1).first
 *	loc.lineno #=> 2
 */
static VALUE
location_lineno_m(VALUE self)
{
    return INT2FIX(location_lineno(location_ptr(self)));
}

VALUE rb_mod_name0(VALUE klass, bool *permanent);

static VALUE
gen_method_name(VALUE owner, VALUE name)
{
    bool permanent;
    if (RB_TYPE_P(owner, T_CLASS) || RB_TYPE_P(owner, T_MODULE)) {
        if (RCLASS_SINGLETON_P(owner)) {
            VALUE v = RCLASS_ATTACHED_OBJECT(owner);
            if (RB_TYPE_P(v, T_CLASS) || RB_TYPE_P(v, T_MODULE)) {
                v = rb_mod_name0(v, &permanent);
                if (permanent && !NIL_P(v)) {
                    return rb_sprintf("%"PRIsVALUE".%"PRIsVALUE, v, name);
                }
            }
        }
        else {
            owner = rb_mod_name0(owner, &permanent);
            if (permanent && !NIL_P(owner)) {
                return rb_sprintf("%"PRIsVALUE"#%"PRIsVALUE, owner, name);
            }
        }
    }
    return name;
}

static VALUE
calculate_iseq_label(VALUE owner, const rb_iseq_t *iseq)
{
retry:
    switch (ISEQ_BODY(iseq)->type) {
      case ISEQ_TYPE_TOP:
      case ISEQ_TYPE_CLASS:
      case ISEQ_TYPE_MAIN:
        return ISEQ_BODY(iseq)->location.label;
      case ISEQ_TYPE_METHOD:
        return gen_method_name(owner, ISEQ_BODY(iseq)->location.label);
      case ISEQ_TYPE_BLOCK:
      case ISEQ_TYPE_PLAIN: {
        int level = 0;
        const rb_iseq_t *orig_iseq = iseq;
        if (ISEQ_BODY(orig_iseq)->parent_iseq != 0) {
            while (ISEQ_BODY(orig_iseq)->local_iseq != iseq) {
                if (ISEQ_BODY(iseq)->type == ISEQ_TYPE_BLOCK) {
                    level++;
                }
                iseq = ISEQ_BODY(iseq)->parent_iseq;
            }
        }
        if (level <= 1) {
            return rb_sprintf("block in %"PRIsVALUE, calculate_iseq_label(owner, iseq));
        }
        else {
            return rb_sprintf("block (%d levels) in %"PRIsVALUE, level, calculate_iseq_label(owner, iseq));
        }
      }
      case ISEQ_TYPE_RESCUE:
      case ISEQ_TYPE_ENSURE:
      case ISEQ_TYPE_EVAL:
        iseq = ISEQ_BODY(iseq)->parent_iseq;
        goto retry;
      default:
        rb_bug("calculate_iseq_label: unreachable");
    }
}

static VALUE
location_label(rb_backtrace_location_t *loc)
{
    if (loc->cme && loc->cme->def->type == VM_METHOD_TYPE_CFUNC) {
        return gen_method_name(loc->cme->owner, rb_id2str(loc->cme->def->original_id));
    }
    else {
        VALUE owner = Qnil;
        if (loc->cme) {
            owner = loc->cme->owner;
        }
        return calculate_iseq_label(owner, loc->iseq);
    }
}
/*
 * Returns the label of this frame.
 *
 * Usually consists of method, class, module, etc names with decoration.
 *
 * Consider the following example:
 *
 *	def foo
 *	  puts caller_locations(0).first.label
 *
 *	  1.times do
 *	    puts caller_locations(0).first.label
 *
 *	    1.times do
 *	      puts caller_locations(0).first.label
 *	    end
 *
 *	  end
 *	end
 *
 * The result of calling +foo+ is this:
 *
 *	label: foo
 *	label: block in foo
 *	label: block (2 levels) in foo
 *
 */
static VALUE
location_label_m(VALUE self)
{
    return location_label(location_ptr(self));
}

static VALUE
location_base_label(rb_backtrace_location_t *loc)
{
    if (loc->cme && loc->cme->def->type == VM_METHOD_TYPE_CFUNC) {
        return rb_id2str(loc->cme->def->original_id);
    }

    return ISEQ_BODY(loc->iseq)->location.base_label;
}

/*
 * Returns the label of this frame without decoration.
 *
 * For example, if the label is `foo`, this method returns `foo`, same, but if
 * the label is +rescue in foo+, this method returns just +foo+.
 */
static VALUE
location_base_label_m(VALUE self)
{
    return location_base_label(location_ptr(self));
}

static const rb_iseq_t *
location_iseq(rb_backtrace_location_t *loc)
{
    return loc->iseq;
}

/*
 * Returns the file name of this frame. This will generally be an absolute
 * path, unless the frame is in the main script, in which case it will be the
 * script location passed on the command line.
 *
 * For example, using +caller_locations.rb+ from Thread::Backtrace::Location
 *
 *	loc = c(0..1).first
 *	loc.path #=> caller_locations.rb
 */
static VALUE
location_path_m(VALUE self)
{
    const rb_iseq_t *iseq = location_iseq(location_ptr(self));
    return iseq ? rb_iseq_path(iseq) : Qnil;
}

#ifdef USE_ISEQ_NODE_ID
static int
location_node_id(rb_backtrace_location_t *loc)
{
    if (loc->iseq && loc->pc) {
        return calc_node_id(loc->iseq, loc->pc);
    }
    return -1;
}
#endif

int
rb_get_node_id_from_frame_info(VALUE obj)
{
#ifdef USE_ISEQ_NODE_ID
    rb_backtrace_location_t *loc = location_ptr(obj);
    return location_node_id(loc);
#else
    return -1;
#endif
}

const rb_iseq_t *
rb_get_iseq_from_frame_info(VALUE obj)
{
    rb_backtrace_location_t *loc = location_ptr(obj);
    const rb_iseq_t *iseq = location_iseq(loc);
    return iseq;
}

static VALUE
location_realpath(rb_backtrace_location_t *loc)
{
    if (loc->iseq) {
        return rb_iseq_realpath(loc->iseq);
    }
    return Qnil;
}

/*
 * Returns the full file path of this frame.
 *
 * Same as #path, except that it will return absolute path
 * even if the frame is in the main script.
 */
static VALUE
location_absolute_path_m(VALUE self)
{
    return location_realpath(location_ptr(self));
}

static VALUE
location_format(VALUE file, int lineno, VALUE name)
{
    VALUE s = rb_enc_sprintf(rb_enc_compatible(file, name), "%s", RSTRING_PTR(file));
    if (lineno != 0) {
        rb_str_catf(s, ":%d", lineno);
    }
    rb_str_cat_cstr(s, ":in ");
    if (NIL_P(name)) {
        rb_str_cat_cstr(s, "unknown method");
    }
    else {
        rb_str_catf(s, "'%s'", RSTRING_PTR(name));
    }
    return s;
}

static VALUE
location_to_str(rb_backtrace_location_t *loc)
{
    VALUE file, owner = Qnil, name;
    int lineno;

    if (loc->cme && loc->cme->def->type == VM_METHOD_TYPE_CFUNC) {
        if (loc->iseq && loc->pc) {
            file = rb_iseq_path(loc->iseq);
            lineno = calc_lineno(loc->iseq, loc->pc);
        }
        else {
            file = GET_VM()->progname;
            lineno = 0;
        }
        name = gen_method_name(loc->cme->owner, rb_id2str(loc->cme->def->original_id));
    }
    else {
        file = rb_iseq_path(loc->iseq);
        lineno = calc_lineno(loc->iseq, loc->pc);
        if (loc->cme) {
            owner = loc->cme->owner;
        }
        name = calculate_iseq_label(owner, loc->iseq);
    }

    return location_format(file, lineno, name);
}

/*
 * Returns a Kernel#caller style string representing this frame.
 */
static VALUE
location_to_str_m(VALUE self)
{
    return location_to_str(location_ptr(self));
}

/*
 * Returns the same as calling +inspect+ on the string representation of
 * #to_str
 */
static VALUE
location_inspect_m(VALUE self)
{
    return rb_str_inspect(location_to_str(location_ptr(self)));
}

typedef struct rb_backtrace_struct {
    int backtrace_size;
    VALUE strary;
    VALUE locary;
    rb_backtrace_location_t backtrace[1];
} rb_backtrace_t;

static void
backtrace_mark(void *ptr)
{
    rb_backtrace_t *bt = (rb_backtrace_t *)ptr;
    size_t i, s = bt->backtrace_size;

    for (i=0; i<s; i++) {
        location_mark_entry(&bt->backtrace[i]);
    }
    rb_gc_mark_movable(bt->strary);
    rb_gc_mark_movable(bt->locary);
}

static void
location_update_entry(rb_backtrace_location_t *fi)
{
    fi->cme = (rb_callable_method_entry_t *)rb_gc_location((VALUE)fi->cme);
    if (fi->iseq) {
        fi->iseq = (rb_iseq_t *)rb_gc_location((VALUE)fi->iseq);
    }
}

static void
backtrace_update(void *ptr)
{
    rb_backtrace_t *bt = (rb_backtrace_t *)ptr;
    size_t i, s = bt->backtrace_size;

    for (i=0; i<s; i++) {
        location_update_entry(&bt->backtrace[i]);
    }
    bt->strary = rb_gc_location(bt->strary);
    bt->locary = rb_gc_location(bt->locary);
}

static const rb_data_type_t backtrace_data_type = {
    "backtrace",
    {
        backtrace_mark,
        RUBY_DEFAULT_FREE,
        NULL, // No external memory to report,
        backtrace_update,
    },
    0, 0, RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED | RUBY_TYPED_EMBEDDABLE
};

int
rb_backtrace_p(VALUE obj)
{
    return rb_typeddata_is_kind_of(obj, &backtrace_data_type);
}

static VALUE
backtrace_alloc(VALUE klass)
{
    rb_backtrace_t *bt;
    VALUE obj = TypedData_Make_Struct(klass, rb_backtrace_t, &backtrace_data_type, bt);
    return obj;
}

static VALUE
backtrace_alloc_capa(long num_frames, rb_backtrace_t **backtrace)
{
    size_t memsize = offsetof(rb_backtrace_t, backtrace) + num_frames * sizeof(rb_backtrace_location_t);
    VALUE btobj = rb_data_typed_object_zalloc(rb_cBacktrace, memsize, &backtrace_data_type);
    TypedData_Get_Struct(btobj, rb_backtrace_t, &backtrace_data_type, *backtrace);
    return btobj;
}


static long
backtrace_size(const rb_execution_context_t *ec)
{
    const rb_control_frame_t *last_cfp = ec->cfp;
    const rb_control_frame_t *start_cfp = RUBY_VM_END_CONTROL_FRAME(ec);

    if (start_cfp == NULL) {
        return -1;
    }

    start_cfp =
      RUBY_VM_NEXT_CONTROL_FRAME(
          RUBY_VM_NEXT_CONTROL_FRAME(start_cfp)); /* skip top frames */

    if (start_cfp < last_cfp) {
        return 0;
    }

    return start_cfp - last_cfp + 1;
}

static bool
is_internal_location(const rb_control_frame_t *cfp)
{
    static const char prefix[] = "<internal:";
    const size_t prefix_len = sizeof(prefix) - 1;
    VALUE file = rb_iseq_path(cfp->iseq);
    return strncmp(prefix, RSTRING_PTR(file), prefix_len) == 0;
}

static bool
is_rescue_or_ensure_frame(const rb_control_frame_t *cfp)
{
    enum rb_iseq_type type = ISEQ_BODY(cfp->iseq)->type;
    return type == ISEQ_TYPE_RESCUE || type == ISEQ_TYPE_ENSURE;
}

static void
bt_update_cfunc_loc(unsigned long cfunc_counter, rb_backtrace_location_t *cfunc_loc, const rb_iseq_t *iseq, const VALUE *pc)
{
    for (; cfunc_counter > 0; cfunc_counter--, cfunc_loc--) {
        cfunc_loc->iseq = iseq;
        cfunc_loc->pc = pc;
    }
}

static VALUE location_create(rb_backtrace_location_t *srcloc, void *btobj);

static void
bt_yield_loc(rb_backtrace_location_t *loc, long num_frames, VALUE btobj)
{
    for (; num_frames > 0; num_frames--, loc++) {
        rb_yield(location_create(loc, (void *)btobj));
    }
}

static VALUE
rb_ec_partial_backtrace_object(const rb_execution_context_t *ec, long start_frame, long num_frames, int* start_too_large, bool skip_internal, bool do_yield)
{
    const rb_control_frame_t *cfp = ec->cfp;
    const rb_control_frame_t *end_cfp = RUBY_VM_END_CONTROL_FRAME(ec);
    ptrdiff_t size;
    rb_backtrace_t *bt = NULL;
    VALUE btobj = Qnil;
    rb_backtrace_location_t *loc = NULL;
    unsigned long cfunc_counter = 0;
    bool skip_next_frame = FALSE;

    // In the case the thread vm_stack or cfp is not initialized, there is no backtrace.
    if (end_cfp == NULL) {
        num_frames = 0;
    }
    else {
        end_cfp = RUBY_VM_NEXT_CONTROL_FRAME(end_cfp);

        /*
         *  top frame (dummy) <- RUBY_VM_END_CONTROL_FRAME
         *  top frame (dummy) <- end_cfp
         *  top frame         <- main script
         *  top frame
         *  ...
         *  2nd frame         <- lev:0
         *  current frame     <- ec->cfp
         */

        size = end_cfp - cfp + 1;
        if (size < 0) {
            num_frames = 0;
        }
        else if (num_frames < 0 || num_frames > size) {
            num_frames = size;
        }
    }

    btobj = backtrace_alloc_capa(num_frames, &bt);

    bt->backtrace_size = 0;
    if (num_frames == 0) {
        if (start_too_large) *start_too_large = 0;
        return btobj;
    }

    for (; cfp != end_cfp && (bt->backtrace_size < num_frames); cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp)) {
        if (cfp->iseq) {
            if (cfp->pc) {
                if (start_frame > 0) {
                    start_frame--;
                }
                else if (!(skip_internal && is_internal_location(cfp))) {
                    if (!skip_next_frame) {
                        const rb_iseq_t *iseq = cfp->iseq;
                        const VALUE *pc = cfp->pc;
                        loc = &bt->backtrace[bt->backtrace_size++];
                        RB_OBJ_WRITE(btobj, &loc->cme, rb_vm_frame_method_entry(cfp));
                        RB_OBJ_WRITE(btobj, &loc->iseq, iseq);
                        loc->pc = pc;
                        bt_update_cfunc_loc(cfunc_counter, loc-1, iseq, pc);
                        if (do_yield) {
                            bt_yield_loc(loc - cfunc_counter, cfunc_counter+1, btobj);
                        }
                        cfunc_counter = 0;
                    }
                    skip_next_frame = is_rescue_or_ensure_frame(cfp);
                }
            }
        }
        else {
            VM_ASSERT(RUBYVM_CFUNC_FRAME_P(cfp));
            if (start_frame > 0) {
                start_frame--;
            }
            else {
                loc = &bt->backtrace[bt->backtrace_size++];
                RB_OBJ_WRITE(btobj, &loc->cme, rb_vm_frame_method_entry(cfp));
                loc->iseq = NULL;
                loc->pc = NULL;
                cfunc_counter++;
            }
        }
    }

    // When a backtrace entry corresponds to a method defined in C (e.g. rb_define_method), the reported file:line
    // is the one of the caller Ruby frame, so if the last entry is a C frame we find the caller Ruby frame here.
    if (cfunc_counter > 0) {
        for (; cfp != end_cfp; cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp)) {
            if (cfp->iseq && cfp->pc && !(skip_internal && is_internal_location(cfp))) {
                VM_ASSERT(!skip_next_frame); // ISEQ_TYPE_RESCUE/ISEQ_TYPE_ENSURE should have a caller Ruby ISEQ, not a cfunc
                bt_update_cfunc_loc(cfunc_counter, loc, cfp->iseq, cfp->pc);
                RB_OBJ_WRITTEN(btobj, Qundef, cfp->iseq);
                if (do_yield) {
                    bt_yield_loc(loc - cfunc_counter, cfunc_counter, btobj);
                }
                break;
            }
        }
    }

    if (start_too_large) *start_too_large = (start_frame > 0 ? -1 : 0);
    return btobj;
}

VALUE
rb_ec_backtrace_object(const rb_execution_context_t *ec)
{
    return rb_ec_partial_backtrace_object(ec, BACKTRACE_START, ALL_BACKTRACE_LINES, NULL, FALSE, FALSE);
}

static VALUE
backtrace_collect(rb_backtrace_t *bt, VALUE (*func)(rb_backtrace_location_t *, void *arg), void *arg)
{
    VALUE btary;
    int i;

    btary = rb_ary_new2(bt->backtrace_size);

    for (i=0; i<bt->backtrace_size; i++) {
        rb_backtrace_location_t *loc = &bt->backtrace[i];
        rb_ary_push(btary, func(loc, arg));
    }

    return btary;
}

static VALUE
location_to_str_dmyarg(rb_backtrace_location_t *loc, void *dmy)
{
    return location_to_str(loc);
}

static VALUE
backtrace_to_str_ary(VALUE self)
{
    VALUE r;
    rb_backtrace_t *bt;
    TypedData_Get_Struct(self, rb_backtrace_t, &backtrace_data_type, bt);
    r = backtrace_collect(bt, location_to_str_dmyarg, 0);
    RB_GC_GUARD(self);
    return r;
}

VALUE
rb_backtrace_to_str_ary(VALUE self)
{
    rb_backtrace_t *bt;
    TypedData_Get_Struct(self, rb_backtrace_t, &backtrace_data_type, bt);

    if (!bt->strary) {
        RB_OBJ_WRITE(self, &bt->strary, backtrace_to_str_ary(self));
    }
    return bt->strary;
}

void
rb_backtrace_use_iseq_first_lineno_for_last_location(VALUE self)
{
    rb_backtrace_t *bt;
    rb_backtrace_location_t *loc;

    TypedData_Get_Struct(self, rb_backtrace_t, &backtrace_data_type, bt);
    VM_ASSERT(bt->backtrace_size > 0);

    loc = &bt->backtrace[0];

    VM_ASSERT(!loc->cme || loc->cme->def->type == VM_METHOD_TYPE_ISEQ);

    loc->pc = NULL; // means location.first_lineno
}

static VALUE
location_create(rb_backtrace_location_t *srcloc, void *btobj)
{
    VALUE obj;
    struct valued_frame_info *vloc;
    obj = TypedData_Make_Struct(rb_cBacktraceLocation, struct valued_frame_info, &location_data_type, vloc);

    vloc->loc = srcloc;
    RB_OBJ_WRITE(obj, &vloc->btobj, (VALUE)btobj);

    return obj;
}

static VALUE
backtrace_to_location_ary(VALUE self)
{
    VALUE r;
    rb_backtrace_t *bt;
    TypedData_Get_Struct(self, rb_backtrace_t, &backtrace_data_type, bt);
    r = backtrace_collect(bt, location_create, (void *)self);
    RB_GC_GUARD(self);
    return r;
}

VALUE
rb_backtrace_to_location_ary(VALUE self)
{
    rb_backtrace_t *bt;
    TypedData_Get_Struct(self, rb_backtrace_t, &backtrace_data_type, bt);

    if (!bt->locary) {
        RB_OBJ_WRITE(self, &bt->locary, backtrace_to_location_ary(self));
    }
    return bt->locary;
}

VALUE
rb_location_ary_to_backtrace(VALUE ary)
{
    if (!RB_TYPE_P(ary, T_ARRAY) || !rb_frame_info_p(RARRAY_AREF(ary, 0))) {
        return Qfalse;
    }

    rb_backtrace_t *new_backtrace;
    long num_frames = RARRAY_LEN(ary);
    VALUE btobj = backtrace_alloc_capa(num_frames, &new_backtrace);

    for (long index = 0; index < RARRAY_LEN(ary); index++) {
        VALUE locobj = RARRAY_AREF(ary, index);

        if (!rb_frame_info_p(locobj)) {
            return Qfalse;
        }

        struct valued_frame_info *src_vloc;
        TypedData_Get_Struct(locobj, struct valued_frame_info, &location_data_type, src_vloc);

        rb_backtrace_location_t *dst_location = &new_backtrace->backtrace[index];
        RB_OBJ_WRITE(btobj, &dst_location->cme, src_vloc->loc->cme);
        RB_OBJ_WRITE(btobj, &dst_location->iseq, src_vloc->loc->iseq);
        dst_location->pc = src_vloc->loc->pc;

        new_backtrace->backtrace_size++;

        RB_GC_GUARD(locobj);
    }

    return btobj;
}

static VALUE
backtrace_dump_data(VALUE self)
{
    VALUE str = rb_backtrace_to_str_ary(self);
    return str;
}

static VALUE
backtrace_load_data(VALUE self, VALUE str)
{
    rb_backtrace_t *bt;
    TypedData_Get_Struct(self, rb_backtrace_t, &backtrace_data_type, bt);
    RB_OBJ_WRITE(self, &bt->strary, str);
    return self;
}

/*
 *  call-seq: Thread::Backtrace::limit -> integer
 *
 *  Returns maximum backtrace length set by <tt>--backtrace-limit</tt>
 *  command-line option. The default is <tt>-1</tt> which means unlimited
 *  backtraces. If the value is zero or positive, the error backtraces,
 *  produced by Exception#full_message, are abbreviated and the extra lines
 *  are replaced by <tt>... 3 levels... </tt>
 *
 *    $ ruby -r net/http -e "p Thread::Backtrace.limit; Net::HTTP.get(URI('http://wrong.address'))"
 *    - 1
 *    .../lib/ruby/3.1.0/socket.rb:227:in `getaddrinfo': Failed to open TCP connection to wrong.address:80 (getaddrinfo: Name or service not known) (SocketError)
 *        from .../lib/ruby/3.1.0/socket.rb:227:in `foreach'
 *        from .../lib/ruby/3.1.0/socket.rb:632:in `tcp'
 *        from .../lib/ruby/3.1.0/net/http.rb:998:in `connect'
 *        from .../lib/ruby/3.1.0/net/http.rb:976:in `do_start'
 *        from .../lib/ruby/3.1.0/net/http.rb:965:in `start'
 *        from .../lib/ruby/3.1.0/net/http.rb:627:in `start'
 *        from .../lib/ruby/3.1.0/net/http.rb:503:in `get_response'
 *        from .../lib/ruby/3.1.0/net/http.rb:474:in `get'
 *    .../lib/ruby/3.1.0/socket.rb:227:in `getaddrinfo': getaddrinfo: Name or service not known (SocketError)
 *        from .../lib/ruby/3.1.0/socket.rb:227:in `foreach'
 *        from .../lib/ruby/3.1.0/socket.rb:632:in `tcp'
 *        from .../lib/ruby/3.1.0/net/http.rb:998:in `connect'
 *        from .../lib/ruby/3.1.0/net/http.rb:976:in `do_start'
 *        from .../lib/ruby/3.1.0/net/http.rb:965:in `start'
 *        from .../lib/ruby/3.1.0/net/http.rb:627:in `start'
 *        from .../lib/ruby/3.1.0/net/http.rb:503:in `get_response'
 *        from .../lib/ruby/3.1.0/net/http.rb:474:in `get'
 *        from -e:1:in `<main>'
 *
 *    $ ruby --backtrace-limit 2 -r net/http -e "p Thread::Backtrace.limit; Net::HTTP.get(URI('http://wrong.address'))"
 *    2
 *    .../lib/ruby/3.1.0/socket.rb:227:in `getaddrinfo': Failed to open TCP connection to wrong.address:80 (getaddrinfo: Name or service not known) (SocketError)
 *        from .../lib/ruby/3.1.0/socket.rb:227:in `foreach'
 *        from .../lib/ruby/3.1.0/socket.rb:632:in `tcp'
 *         ... 7 levels...
 *    .../lib/ruby/3.1.0/socket.rb:227:in `getaddrinfo': getaddrinfo: Name or service not known (SocketError)
 *        from .../lib/ruby/3.1.0/socket.rb:227:in `foreach'
 *        from .../lib/ruby/3.1.0/socket.rb:632:in `tcp'
 *         ... 7 levels...
 *
 *    $ ruby --backtrace-limit 0 -r net/http -e "p Thread::Backtrace.limit; Net::HTTP.get(URI('http://wrong.address'))"
 *    0
 *    .../lib/ruby/3.1.0/socket.rb:227:in `getaddrinfo': Failed to open TCP connection to wrong.address:80 (getaddrinfo: Name or service not known) (SocketError)
 *         ... 9 levels...
 *    .../lib/ruby/3.1.0/socket.rb:227:in `getaddrinfo': getaddrinfo: Name or service not known (SocketError)
 *         ... 9 levels...
 *
 */
static VALUE
backtrace_limit(VALUE self)
{
    return LONG2NUM(rb_backtrace_length_limit);
}

VALUE
rb_ec_backtrace_str_ary(const rb_execution_context_t *ec, long lev, long n)
{
    return rb_backtrace_to_str_ary(rb_ec_partial_backtrace_object(ec, lev, n, NULL, FALSE, FALSE));
}

VALUE
rb_ec_backtrace_location_ary(const rb_execution_context_t *ec, long lev, long n, bool skip_internal)
{
    return rb_backtrace_to_location_ary(rb_ec_partial_backtrace_object(ec, lev, n, NULL, skip_internal, FALSE));
}

/* make old style backtrace directly */

static void
backtrace_each(const rb_execution_context_t *ec,
           void (*init)(void *arg, size_t size),
           void (*iter_iseq)(void *arg, const rb_control_frame_t *cfp),
           void (*iter_cfunc)(void *arg, const rb_control_frame_t *cfp, ID mid),
           void *arg)
{
    const rb_control_frame_t *last_cfp = ec->cfp;
    const rb_control_frame_t *start_cfp = RUBY_VM_END_CONTROL_FRAME(ec);
    const rb_control_frame_t *cfp;
    ptrdiff_t size, i;

    // In the case the thread vm_stack or cfp is not initialized, there is no backtrace.
    if (start_cfp == NULL) {
        init(arg, 0);
        return;
    }

    /*                <- start_cfp (end control frame)
     *  top frame (dummy)
     *  top frame (dummy)
     *  top frame     <- start_cfp
     *  top frame
     *  ...
     *  2nd frame     <- lev:0
     *  current frame <- ec->cfp
     */

    start_cfp =
      RUBY_VM_NEXT_CONTROL_FRAME(
        RUBY_VM_NEXT_CONTROL_FRAME(start_cfp)); /* skip top frames */

    if (start_cfp < last_cfp) {
        size = 0;
    }
    else {
        size = start_cfp - last_cfp + 1;
    }

    init(arg, size);

    /* SDR(); */
    for (i=0, cfp = start_cfp; i<size; i++, cfp = RUBY_VM_NEXT_CONTROL_FRAME(cfp)) {
        /* fprintf(stderr, "cfp: %d\n", (rb_control_frame_t *)(ec->vm_stack + ec->vm_stack_size) - cfp); */
        if (cfp->iseq) {
            if (cfp->pc) {
                iter_iseq(arg, cfp);
            }
        }
        else {
            VM_ASSERT(RUBYVM_CFUNC_FRAME_P(cfp));
            const rb_callable_method_entry_t *me = rb_vm_frame_method_entry(cfp);
            ID mid = me->def->original_id;

            iter_cfunc(arg, cfp, mid);
        }
    }
}

struct oldbt_arg {
    VALUE filename;
    int lineno;
    void (*func)(void *data, VALUE file, int lineno, VALUE name);
    void *data; /* result */
};

static void
oldbt_init(void *ptr, size_t dmy)
{
    struct oldbt_arg *arg = (struct oldbt_arg *)ptr;
    arg->filename = GET_VM()->progname;
    arg->lineno = 0;
}

static void
oldbt_iter_iseq(void *ptr, const rb_control_frame_t *cfp)
{
    const rb_iseq_t *iseq = cfp->iseq;
    const VALUE *pc = cfp->pc;
    struct oldbt_arg *arg = (struct oldbt_arg *)ptr;
    VALUE file = arg->filename = rb_iseq_path(iseq);
    VALUE name = ISEQ_BODY(iseq)->location.label;
    int lineno = arg->lineno = calc_lineno(iseq, pc);

    (arg->func)(arg->data, file, lineno, name);
}

static void
oldbt_iter_cfunc(void *ptr, const rb_control_frame_t *cfp, ID mid)
{
    struct oldbt_arg *arg = (struct oldbt_arg *)ptr;
    VALUE file = arg->filename;
    VALUE name = rb_id2str(mid);
    int lineno = arg->lineno;

    (arg->func)(arg->data, file, lineno, name);
}

static void
oldbt_print(void *data, VALUE file, int lineno, VALUE name)
{
    FILE *fp = (FILE *)data;

    if (NIL_P(name)) {
        fprintf(fp, "\tfrom %s:%d:in unknown method\n",
                RSTRING_PTR(file), lineno);
    }
    else {
        fprintf(fp, "\tfrom %s:%d:in '%s'\n",
                RSTRING_PTR(file), lineno, RSTRING_PTR(name));
    }
}

static void
vm_backtrace_print(FILE *fp)
{
    struct oldbt_arg arg;

    arg.func = oldbt_print;
    arg.data = (void *)fp;
    backtrace_each(GET_EC(),
                   oldbt_init,
                   oldbt_iter_iseq,
                   oldbt_iter_cfunc,
                   &arg);
}

struct oldbt_bugreport_arg {
    FILE *fp;
    int count;
};

static void
oldbt_bugreport(void *arg, VALUE file, int line, VALUE method)
{
    struct oldbt_bugreport_arg *p = arg;
    FILE *fp = p->fp;
    const char *filename = NIL_P(file) ? "ruby" : RSTRING_PTR(file);
    if (!p->count) {
        fprintf(fp, "-- Ruby level backtrace information "
                "----------------------------------------\n");
        p->count = 1;
    }
    if (NIL_P(method)) {
        fprintf(fp, "%s:%d:in unknown method\n", filename, line);
    }
    else {
        fprintf(fp, "%s:%d:in '%s'\n", filename, line, RSTRING_PTR(method));
    }
}

void
rb_backtrace_print_as_bugreport(FILE *fp)
{
    struct oldbt_arg arg;
    struct oldbt_bugreport_arg barg = {fp, 0};

    arg.func = oldbt_bugreport;
    arg.data = &barg;

    backtrace_each(GET_EC(),
                   oldbt_init,
                   oldbt_iter_iseq,
                   oldbt_iter_cfunc,
                   &arg);
}

void
rb_backtrace(void)
{
    vm_backtrace_print(stderr);
}

struct print_to_arg {
    VALUE (*iter)(VALUE recv, VALUE str);
    VALUE output;
};

static void
oldbt_print_to(void *data, VALUE file, int lineno, VALUE name)
{
    const struct print_to_arg *arg = data;
    VALUE str = rb_sprintf("\tfrom %"PRIsVALUE":%d:in ", file, lineno);

    if (NIL_P(name)) {
        rb_str_cat2(str, "unknown method\n");
    }
    else {
        rb_str_catf(str, " '%"PRIsVALUE"'\n", name);
    }
    (*arg->iter)(arg->output, str);
}

void
rb_backtrace_each(VALUE (*iter)(VALUE recv, VALUE str), VALUE output)
{
    struct oldbt_arg arg;
    struct print_to_arg parg;

    parg.iter = iter;
    parg.output = output;
    arg.func = oldbt_print_to;
    arg.data = &parg;
    backtrace_each(GET_EC(),
                   oldbt_init,
                   oldbt_iter_iseq,
                   oldbt_iter_cfunc,
                   &arg);
}

VALUE
rb_make_backtrace(void)
{
    return rb_ec_backtrace_str_ary(GET_EC(), BACKTRACE_START, ALL_BACKTRACE_LINES);
}

static VALUE
ec_backtrace_to_ary(const rb_execution_context_t *ec, int argc, const VALUE *argv, int lev_default, int lev_plus, int to_str)
{
    VALUE level, vn;
    long lev, n;
    VALUE btval;
    VALUE r;
    int too_large;

    rb_scan_args(argc, argv, "02", &level, &vn);

    if (argc == 2 && NIL_P(vn)) argc--;

    switch (argc) {
      case 0:
        lev = lev_default + lev_plus;
        n = ALL_BACKTRACE_LINES;
        break;
      case 1:
        {
            long beg, len, bt_size = backtrace_size(ec);
            switch (rb_range_beg_len(level, &beg, &len, bt_size - lev_plus, 0)) {
              case Qfalse:
                lev = NUM2LONG(level);
                if (lev < 0) {
                    rb_raise(rb_eArgError, "negative level (%ld)", lev);
                }
                lev += lev_plus;
                n = ALL_BACKTRACE_LINES;
                break;
              case Qnil:
                return Qnil;
              default:
                lev = beg + lev_plus;
                n = len;
                break;
            }
            break;
        }
      case 2:
        lev = NUM2LONG(level);
        n = NUM2LONG(vn);
        if (lev < 0) {
            rb_raise(rb_eArgError, "negative level (%ld)", lev);
        }
        if (n < 0) {
            rb_raise(rb_eArgError, "negative size (%ld)", n);
        }
        lev += lev_plus;
        break;
      default:
        lev = n = 0; /* to avoid warning */
        break;
    }

    if (n == 0) {
        return rb_ary_new();
    }

    btval = rb_ec_partial_backtrace_object(ec, lev, n, &too_large, FALSE, FALSE);

    if (too_large) {
        return Qnil;
    }

    if (to_str) {
        r = backtrace_to_str_ary(btval);
    }
    else {
        r = backtrace_to_location_ary(btval);
    }
    RB_GC_GUARD(btval);
    return r;
}

static VALUE
thread_backtrace_to_ary(int argc, const VALUE *argv, VALUE thval, int to_str)
{
    rb_thread_t *target_th = rb_thread_ptr(thval);

    if (target_th->to_kill || target_th->status == THREAD_KILLED)
      return Qnil;

    return ec_backtrace_to_ary(target_th->ec, argc, argv, 0, 0, to_str);
}

VALUE
rb_vm_thread_backtrace(int argc, const VALUE *argv, VALUE thval)
{
    return thread_backtrace_to_ary(argc, argv, thval, 1);
}

VALUE
rb_vm_thread_backtrace_locations(int argc, const VALUE *argv, VALUE thval)
{
    return thread_backtrace_to_ary(argc, argv, thval, 0);
}

VALUE
rb_vm_backtrace(int argc, const VALUE * argv, struct rb_execution_context_struct * ec)
{
    return ec_backtrace_to_ary(ec, argc, argv, 0, 0, 1);
}

VALUE
rb_vm_backtrace_locations(int argc, const VALUE * argv, struct rb_execution_context_struct * ec)
{
    return ec_backtrace_to_ary(ec, argc, argv, 0, 0, 0);
}

/*
 *  call-seq:
 *     caller(start=1, length=nil)  -> array or nil
 *     caller(range)		    -> array or nil
 *
 *  Returns the current execution stack---an array containing strings in
 *  the form <code>file:line</code> or <code>file:line: in
 *  `method'</code>.
 *
 *  The optional _start_ parameter determines the number of initial stack
 *  entries to omit from the top of the stack.
 *
 *  A second optional +length+ parameter can be used to limit how many entries
 *  are returned from the stack.
 *
 *  Returns +nil+ if _start_ is greater than the size of
 *  current execution stack.
 *
 *  Optionally you can pass a range, which will return an array containing the
 *  entries within the specified range.
 *
 *     def a(skip)
 *       caller(skip)
 *     end
 *     def b(skip)
 *       a(skip)
 *     end
 *     def c(skip)
 *       b(skip)
 *     end
 *     c(0)   #=> ["prog:2:in `a'", "prog:5:in `b'", "prog:8:in `c'", "prog:10:in `<main>'"]
 *     c(1)   #=> ["prog:5:in `b'", "prog:8:in `c'", "prog:11:in `<main>'"]
 *     c(2)   #=> ["prog:8:in `c'", "prog:12:in `<main>'"]
 *     c(3)   #=> ["prog:13:in `<main>'"]
 *     c(4)   #=> []
 *     c(5)   #=> nil
 */

static VALUE
rb_f_caller(int argc, VALUE *argv, VALUE _)
{
    return ec_backtrace_to_ary(GET_EC(), argc, argv, 1, 1, 1);
}

/*
 *  call-seq:
 *     caller_locations(start=1, length=nil)	-> array or nil
 *     caller_locations(range)			-> array or nil
 *
 *  Returns the current execution stack---an array containing
 *  backtrace location objects.
 *
 *  See Thread::Backtrace::Location for more information.
 *
 *  The optional _start_ parameter determines the number of initial stack
 *  entries to omit from the top of the stack.
 *
 *  A second optional +length+ parameter can be used to limit how many entries
 *  are returned from the stack.
 *
 *  Returns +nil+ if _start_ is greater than the size of
 *  current execution stack.
 *
 *  Optionally you can pass a range, which will return an array containing the
 *  entries within the specified range.
 */
static VALUE
rb_f_caller_locations(int argc, VALUE *argv, VALUE _)
{
    return ec_backtrace_to_ary(GET_EC(), argc, argv, 1, 1, 0);
}

/*
 *  call-seq:
 *     Thread.each_caller_location{ |loc| ... } -> nil
 *
 *  Yields each frame of the current execution stack as a
 *  backtrace location object.
 */
static VALUE
each_caller_location(VALUE unused)
{
    rb_ec_partial_backtrace_object(GET_EC(), 2, ALL_BACKTRACE_LINES, NULL, FALSE, TRUE);
    return Qnil;
}

/* called from Init_vm() in vm.c */
void
Init_vm_backtrace(void)
{
    /*
     *  An internal representation of the backtrace. The user will never interact with
     *  objects of this class directly, but class methods can be used to get backtrace
     *  settings of the current session.
     */
    rb_cBacktrace = rb_define_class_under(rb_cThread, "Backtrace", rb_cObject);
    rb_define_alloc_func(rb_cBacktrace, backtrace_alloc);
    rb_undef_method(CLASS_OF(rb_cBacktrace), "new");
    rb_marshal_define_compat(rb_cBacktrace, rb_cArray, backtrace_dump_data, backtrace_load_data);
    rb_define_singleton_method(rb_cBacktrace, "limit", backtrace_limit, 0);

    /*
     *	An object representation of a stack frame, initialized by
     *	Kernel#caller_locations.
     *
     *	For example:
     *
     *		# caller_locations.rb
     *		def a(skip)
     *		  caller_locations(skip)
     *		end
     *		def b(skip)
     *		  a(skip)
     *		end
     *		def c(skip)
     *		  b(skip)
     *		end
     *
     *		c(0..2).map do |call|
     *		  puts call.to_s
     *		end
     *
     *	Running <code>ruby caller_locations.rb</code> will produce:
     *
     *		caller_locations.rb:2:in `a'
     *		caller_locations.rb:5:in `b'
     *		caller_locations.rb:8:in `c'
     *
     *	Here's another example with a slightly different result:
     *
     *		# foo.rb
     *		class Foo
     *		  attr_accessor :locations
     *		  def initialize(skip)
     *		    @locations = caller_locations(skip)
     *		  end
     *		end
     *
     *		Foo.new(0..2).locations.map do |call|
     *		  puts call.to_s
     *		end
     *
     *	Now run <code>ruby foo.rb</code> and you should see:
     *
     *		init.rb:4:in `initialize'
     *		init.rb:8:in `new'
     *		init.rb:8:in `<main>'
     */
    rb_cBacktraceLocation = rb_define_class_under(rb_cBacktrace, "Location", rb_cObject);
    rb_undef_alloc_func(rb_cBacktraceLocation);
    rb_undef_method(CLASS_OF(rb_cBacktraceLocation), "new");
    rb_define_method(rb_cBacktraceLocation, "lineno", location_lineno_m, 0);
    rb_define_method(rb_cBacktraceLocation, "label", location_label_m, 0);
    rb_define_method(rb_cBacktraceLocation, "base_label", location_base_label_m, 0);
    rb_define_method(rb_cBacktraceLocation, "path", location_path_m, 0);
    rb_define_method(rb_cBacktraceLocation, "absolute_path", location_absolute_path_m, 0);
    rb_define_method(rb_cBacktraceLocation, "to_s", location_to_str_m, 0);
    rb_define_method(rb_cBacktraceLocation, "inspect", location_inspect_m, 0);

    rb_define_global_function("caller", rb_f_caller, -1);
    rb_define_global_function("caller_locations", rb_f_caller_locations, -1);

    rb_define_singleton_method(rb_cThread, "each_caller_location", each_caller_location, 0);
}

/* debugger API */

RUBY_SYMBOL_EXPORT_BEGIN

RUBY_SYMBOL_EXPORT_END

struct rb_debug_inspector_struct {
    rb_execution_context_t *ec;
    rb_control_frame_t *cfp;
    VALUE backtrace;
    VALUE contexts; /* [[klass, binding, iseq, cfp], ...] */
    long backtrace_size;
};

enum {
    CALLER_BINDING_SELF,
    CALLER_BINDING_CLASS,
    CALLER_BINDING_BINDING,
    CALLER_BINDING_ISEQ,
    CALLER_BINDING_CFP,
    CALLER_BINDING_DEPTH,
};

struct collect_caller_bindings_data {
    VALUE ary;
    const rb_execution_context_t *ec;
};

static void
collect_caller_bindings_init(void *arg, size_t size)
{
    /* */
}

static VALUE
get_klass(const rb_control_frame_t *cfp)
{
    VALUE klass;
    if (rb_vm_control_frame_id_and_class(cfp, 0, 0, &klass)) {
        if (RB_TYPE_P(klass, T_ICLASS)) {
            return RBASIC(klass)->klass;
        }
        else {
            return klass;
        }
    }
    else {
        return Qnil;
    }
}

static int
frame_depth(const rb_execution_context_t *ec, const rb_control_frame_t *cfp)
{
    VM_ASSERT(RUBY_VM_END_CONTROL_FRAME(ec) >= cfp);
    return (int)(RUBY_VM_END_CONTROL_FRAME(ec) - cfp);
}

static void
collect_caller_bindings_iseq(void *arg, const rb_control_frame_t *cfp)
{
    struct collect_caller_bindings_data *data = (struct collect_caller_bindings_data *)arg;
    VALUE frame = rb_ary_new2(6);

    rb_ary_store(frame, CALLER_BINDING_SELF, cfp->self);
    rb_ary_store(frame, CALLER_BINDING_CLASS, get_klass(cfp));
    rb_ary_store(frame, CALLER_BINDING_BINDING, GC_GUARDED_PTR(cfp)); /* create later */
    rb_ary_store(frame, CALLER_BINDING_ISEQ, cfp->iseq ? (VALUE)cfp->iseq : Qnil);
    rb_ary_store(frame, CALLER_BINDING_CFP, GC_GUARDED_PTR(cfp));
    rb_ary_store(frame, CALLER_BINDING_DEPTH, INT2FIX(frame_depth(data->ec, cfp)));

    rb_ary_push(data->ary, frame);
}

static void
collect_caller_bindings_cfunc(void *arg, const rb_control_frame_t *cfp, ID mid)
{
    struct collect_caller_bindings_data *data = (struct collect_caller_bindings_data *)arg;
    VALUE frame = rb_ary_new2(6);

    rb_ary_store(frame, CALLER_BINDING_SELF, cfp->self);
    rb_ary_store(frame, CALLER_BINDING_CLASS, get_klass(cfp));
    rb_ary_store(frame, CALLER_BINDING_BINDING, Qnil); /* not available */
    rb_ary_store(frame, CALLER_BINDING_ISEQ, Qnil); /* not available */
    rb_ary_store(frame, CALLER_BINDING_CFP, GC_GUARDED_PTR(cfp));
    rb_ary_store(frame, CALLER_BINDING_DEPTH, INT2FIX(frame_depth(data->ec, cfp)));

    rb_ary_push(data->ary, frame);
}

static VALUE
collect_caller_bindings(const rb_execution_context_t *ec)
{
    int i;
    VALUE result;
    struct collect_caller_bindings_data data = {
        rb_ary_new(), ec
    };

    backtrace_each(ec,
                   collect_caller_bindings_init,
                   collect_caller_bindings_iseq,
                   collect_caller_bindings_cfunc,
                   &data);

    result = rb_ary_reverse(data.ary);

    /* bindings should be created from top of frame */
    for (i=0; i<RARRAY_LEN(result); i++) {
        VALUE entry = rb_ary_entry(result, i);
        VALUE cfp_val = rb_ary_entry(entry, CALLER_BINDING_BINDING);

        if (!NIL_P(cfp_val)) {
            rb_control_frame_t *cfp = GC_GUARDED_PTR_REF(cfp_val);
            rb_ary_store(entry, CALLER_BINDING_BINDING, rb_vm_make_binding(ec, cfp));
        }
    }

    return result;
}

/*
 * Note that the passed `rb_debug_inspector_t' will be disabled
 * after `rb_debug_inspector_open'.
 */

VALUE
rb_debug_inspector_open(rb_debug_inspector_func_t func, void *data)
{
    rb_debug_inspector_t dbg_context;
    rb_execution_context_t *ec = GET_EC();
    enum ruby_tag_type state;
    volatile VALUE MAYBE_UNUSED(result);

    /* escape all env to heap */
    rb_vm_stack_to_heap(ec);

    dbg_context.ec = ec;
    dbg_context.cfp = dbg_context.ec->cfp;
    dbg_context.backtrace = rb_ec_backtrace_location_ary(ec, BACKTRACE_START, ALL_BACKTRACE_LINES, FALSE);
    dbg_context.backtrace_size = RARRAY_LEN(dbg_context.backtrace);
    dbg_context.contexts = collect_caller_bindings(ec);

    EC_PUSH_TAG(ec);
    if ((state = EC_EXEC_TAG()) == TAG_NONE) {
        result = (*func)(&dbg_context, data);
    }
    EC_POP_TAG();

    /* invalidate bindings? */

    if (state) {
        EC_JUMP_TAG(ec, state);
    }

    return result;
}

static VALUE
frame_get(const rb_debug_inspector_t *dc, long index)
{
    if (index < 0 || index >= dc->backtrace_size) {
        rb_raise(rb_eArgError, "no such frame");
    }
    return rb_ary_entry(dc->contexts, index);
}

VALUE
rb_debug_inspector_frame_self_get(const rb_debug_inspector_t *dc, long index)
{
    VALUE frame = frame_get(dc, index);
    return rb_ary_entry(frame, CALLER_BINDING_SELF);
}

VALUE
rb_debug_inspector_frame_class_get(const rb_debug_inspector_t *dc, long index)
{
    VALUE frame = frame_get(dc, index);
    return rb_ary_entry(frame, CALLER_BINDING_CLASS);
}

VALUE
rb_debug_inspector_frame_binding_get(const rb_debug_inspector_t *dc, long index)
{
    VALUE frame = frame_get(dc, index);
    return rb_ary_entry(frame, CALLER_BINDING_BINDING);
}

VALUE
rb_debug_inspector_frame_iseq_get(const rb_debug_inspector_t *dc, long index)
{
    VALUE frame = frame_get(dc, index);
    VALUE iseq = rb_ary_entry(frame, CALLER_BINDING_ISEQ);

    return RTEST(iseq) ? rb_iseqw_new((rb_iseq_t *)iseq) : Qnil;
}

VALUE
rb_debug_inspector_frame_depth(const rb_debug_inspector_t *dc, long index)
{
    VALUE frame = frame_get(dc, index);
    return rb_ary_entry(frame, CALLER_BINDING_DEPTH);
}

VALUE
rb_debug_inspector_current_depth(void)
{
    rb_execution_context_t *ec = GET_EC();
    return INT2FIX(frame_depth(ec, ec->cfp));
}

VALUE
rb_debug_inspector_backtrace_locations(const rb_debug_inspector_t *dc)
{
    return dc->backtrace;
}

static int
thread_profile_frames(rb_execution_context_t *ec, int start, int limit, VALUE *buff, int *lines)
{
    int i;
    const rb_control_frame_t *cfp = ec->cfp, *end_cfp = RUBY_VM_END_CONTROL_FRAME(ec);
    const rb_control_frame_t *top = cfp;
    const rb_callable_method_entry_t *cme;

    // If this function is called inside a thread after thread creation, but
    // before the CFP has been created, just return 0.  This can happen when
    // sampling via signals.  Threads can be interrupted randomly by the
    // signal, including during the time after the thread has been created, but
    // before the CFP has been allocated
    if (!cfp) {
        return 0;
    }

    // Skip dummy frame; see `rb_ec_partial_backtrace_object` for details
    end_cfp = RUBY_VM_NEXT_CONTROL_FRAME(end_cfp);

    for (i=0; i<limit && cfp != end_cfp; cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp)) {
        if (VM_FRAME_RUBYFRAME_P(cfp) && cfp->pc != 0) {
            if (start > 0) {
                start--;
                continue;
            }

            /* record frame info */
            cme = rb_vm_frame_method_entry(cfp);
            if (cme && cme->def->type == VM_METHOD_TYPE_ISEQ) {
                buff[i] = (VALUE)cme;
            }
            else {
                buff[i] = (VALUE)cfp->iseq;
            }

            if (lines) {
                // The topmost frame may not have an updated PC because the JIT
                // may not have set one.  The JIT compiler will update the PC
                // before entering a new function (so that `caller` will work),
                // so only the topmost frame could possibly have an out of date PC
                if (cfp == top && cfp->jit_return) {
                    lines[i] = 0;
                }
                else {
                    lines[i] = calc_lineno(cfp->iseq, cfp->pc);
                }
            }

            i++;
        }
        else {
            cme = rb_vm_frame_method_entry(cfp);
            if (cme && cme->def->type == VM_METHOD_TYPE_CFUNC) {
                if (start > 0) {
                    start--;
                    continue;
                }
                buff[i] = (VALUE)cme;
                if (lines) lines[i] = 0;
                i++;
            }
        }
    }

    return i;
}

int
rb_profile_frames(int start, int limit, VALUE *buff, int *lines)
{
    rb_execution_context_t *ec = rb_current_execution_context(false);

    // If there is no EC, we may be attempting to profile a non-Ruby thread or a
    // M:N shared native thread which has no active Ruby thread.
    if (!ec) {
        return 0;
    }

    return thread_profile_frames(ec, start, limit, buff, lines);
}

int
rb_profile_thread_frames(VALUE thread, int start, int limit, VALUE *buff, int *lines)
{
    rb_thread_t *th = rb_thread_ptr(thread);
    return thread_profile_frames(th->ec, start, limit, buff, lines);
}

static const rb_iseq_t *
frame2iseq(VALUE frame)
{
    if (NIL_P(frame)) return NULL;

    if (RB_TYPE_P(frame, T_IMEMO)) {
        switch (imemo_type(frame)) {
          case imemo_iseq:
            return (const rb_iseq_t *)frame;
          case imemo_ment:
            {
                const rb_callable_method_entry_t *cme = (rb_callable_method_entry_t *)frame;
                switch (cme->def->type) {
                  case VM_METHOD_TYPE_ISEQ:
                    return cme->def->body.iseq.iseqptr;
                  default:
                    return NULL;
                }
            }
          default:
            break;
        }
    }
    rb_bug("frame2iseq: unreachable");
}

VALUE
rb_profile_frame_path(VALUE frame)
{
    const rb_iseq_t *iseq = frame2iseq(frame);
    return iseq ? rb_iseq_path(iseq) : Qnil;
}

static const rb_callable_method_entry_t *
cframe(VALUE frame)
{
    if (NIL_P(frame)) return NULL;

    if (RB_TYPE_P(frame, T_IMEMO)) {
        switch (imemo_type(frame)) {
          case imemo_ment:
            {
                const rb_callable_method_entry_t *cme = (rb_callable_method_entry_t *)frame;
                switch (cme->def->type) {
                  case VM_METHOD_TYPE_CFUNC:
                    return cme;
                  default:
                    return NULL;
                }
            }
          default:
            return NULL;
        }
    }

    return NULL;
}

VALUE
rb_profile_frame_absolute_path(VALUE frame)
{
    if (cframe(frame)) {
        static VALUE cfunc_str = Qfalse;
        if (!cfunc_str) {
            cfunc_str = rb_str_new_literal("<cfunc>");
            rb_vm_register_global_object(cfunc_str);
        }
        return cfunc_str;
    }
    const rb_iseq_t *iseq = frame2iseq(frame);
    return iseq ? rb_iseq_realpath(iseq) : Qnil;
}

VALUE
rb_profile_frame_label(VALUE frame)
{
    const rb_iseq_t *iseq = frame2iseq(frame);
    return iseq ? rb_iseq_label(iseq) : Qnil;
}

VALUE
rb_profile_frame_base_label(VALUE frame)
{
    const rb_iseq_t *iseq = frame2iseq(frame);
    return iseq ? rb_iseq_base_label(iseq) : Qnil;
}

VALUE
rb_profile_frame_first_lineno(VALUE frame)
{
    const rb_iseq_t *iseq = frame2iseq(frame);
    return iseq ? rb_iseq_first_lineno(iseq) : Qnil;
}

static VALUE
frame2klass(VALUE frame)
{
    if (NIL_P(frame)) return Qnil;

    if (RB_TYPE_P(frame, T_IMEMO)) {
        const rb_callable_method_entry_t *cme = (rb_callable_method_entry_t *)frame;

        if (imemo_type(frame) == imemo_ment) {
            return cme->defined_class;
        }
    }
    return Qnil;
}

VALUE
rb_profile_frame_classpath(VALUE frame)
{
    VALUE klass = frame2klass(frame);

    if (klass && !NIL_P(klass)) {
        if (RB_TYPE_P(klass, T_ICLASS)) {
            klass = RBASIC(klass)->klass;
        }
        else if (RCLASS_SINGLETON_P(klass)) {
            klass = RCLASS_ATTACHED_OBJECT(klass);
            if (!RB_TYPE_P(klass, T_CLASS) && !RB_TYPE_P(klass, T_MODULE))
                return rb_sprintf("#<%s:%p>", rb_class2name(rb_obj_class(klass)), (void*)klass);
        }
        return rb_class_path(klass);
    }
    else {
        return Qnil;
    }
}

VALUE
rb_profile_frame_singleton_method_p(VALUE frame)
{
    VALUE klass = frame2klass(frame);

    return RBOOL(klass && !NIL_P(klass) && RCLASS_SINGLETON_P(klass));
}

VALUE
rb_profile_frame_method_name(VALUE frame)
{
    const rb_callable_method_entry_t *cme = cframe(frame);
    if (cme) {
        ID mid = cme->def->original_id;
        return id2str(mid);
    }
    const rb_iseq_t *iseq = frame2iseq(frame);
    return iseq ? rb_iseq_method_name(iseq) : Qnil;
}

static VALUE
qualified_method_name(VALUE frame, VALUE method_name)
{
    if (method_name != Qnil) {
        VALUE classpath = rb_profile_frame_classpath(frame);
        VALUE singleton_p = rb_profile_frame_singleton_method_p(frame);

        if (classpath != Qnil) {
            return rb_sprintf("%"PRIsVALUE"%s%"PRIsVALUE,
                              classpath, singleton_p == Qtrue ? "." : "#", method_name);
        }
        else {
            return method_name;
        }
    }
    else {
        return Qnil;
    }
}

VALUE
rb_profile_frame_qualified_method_name(VALUE frame)
{
    VALUE method_name = rb_profile_frame_method_name(frame);

    return qualified_method_name(frame, method_name);
}

VALUE
rb_profile_frame_full_label(VALUE frame)
{
    const rb_callable_method_entry_t *cme = cframe(frame);
    if (cme) {
        ID mid = cme->def->original_id;
        VALUE method_name = id2str(mid);
        return qualified_method_name(frame, method_name);
    }

    VALUE label = rb_profile_frame_label(frame);
    VALUE base_label = rb_profile_frame_base_label(frame);
    VALUE qualified_method_name = rb_profile_frame_qualified_method_name(frame);

    if (NIL_P(qualified_method_name) || base_label == qualified_method_name) {
        return label;
    }
    else {
        long label_length = RSTRING_LEN(label);
        long base_label_length = RSTRING_LEN(base_label);
        int prefix_len = rb_long2int(label_length - base_label_length);

        return rb_sprintf("%.*s%"PRIsVALUE, prefix_len, RSTRING_PTR(label), qualified_method_name);
    }
}
