/**********************************************************************

  struct.c -

  $Author$
  created at: Tue Mar 22 18:44:30 JST 1995

  Copyright (C) 1993-2007 Yukihiro Matsumoto

**********************************************************************/

#include "id.h"
#include "internal.h"
#include "internal/class.h"
#include "internal/error.h"
#include "internal/hash.h"
#include "internal/object.h"
#include "internal/proc.h"
#include "internal/struct.h"
#include "internal/symbol.h"
#include "vm_core.h"
#include "builtin.h"

/* only for struct[:field] access */
enum {
    AREF_HASH_UNIT = 5,
    AREF_HASH_THRESHOLD = 10
};

/* Note: Data is a stricter version of the Struct: no attr writers & no
   hash-alike/array-alike behavior. It shares most of the implementation
   on the C level, but is unrelated on the Ruby level. */
VALUE rb_cStruct;
static VALUE rb_cData;
static ID id_members, id_back_members, id_keyword_init;

static VALUE struct_alloc(VALUE);

static inline VALUE
struct_ivar_get(VALUE c, ID id)
{
    VALUE orig = c;
    VALUE ivar = rb_attr_get(c, id);

    if (!NIL_P(ivar))
        return ivar;

    for (;;) {
        c = rb_class_superclass(c);
        if (c == rb_cStruct || c == rb_cData || !RTEST(c))
            return Qnil;
        RUBY_ASSERT(RB_TYPE_P(c, T_CLASS));
        ivar = rb_attr_get(c, id);
        if (!NIL_P(ivar)) {
            return rb_ivar_set(orig, id, ivar);
        }
    }
}

VALUE
rb_struct_s_keyword_init(VALUE klass)
{
    return struct_ivar_get(klass, id_keyword_init);
}

VALUE
rb_struct_s_members(VALUE klass)
{
    VALUE members = struct_ivar_get(klass, id_members);

    if (NIL_P(members)) {
        rb_raise(rb_eTypeError, "uninitialized struct");
    }
    if (!RB_TYPE_P(members, T_ARRAY)) {
        rb_raise(rb_eTypeError, "corrupted struct");
    }
    return members;
}

VALUE
rb_struct_members(VALUE s)
{
    VALUE members = rb_struct_s_members(rb_obj_class(s));

    if (RSTRUCT_LEN(s) != RARRAY_LEN(members)) {
        rb_raise(rb_eTypeError, "struct size differs (%ld required %ld given)",
                 RARRAY_LEN(members), RSTRUCT_LEN(s));
    }
    return members;
}

static long
struct_member_pos_ideal(VALUE name, long mask)
{
    /* (id & (mask/2)) * 2 */
    return (SYM2ID(name) >> (ID_SCOPE_SHIFT - 1)) & mask;
}

static long
struct_member_pos_probe(long prev, long mask)
{
    /* (((prev/2) * AREF_HASH_UNIT + 1) & (mask/2)) * 2 */
    return (prev * AREF_HASH_UNIT + 2) & mask;
}

static VALUE
struct_set_members(VALUE klass, VALUE /* frozen hidden array */ members)
{
    VALUE back;
    const long members_length = RARRAY_LEN(members);

    if (members_length <= AREF_HASH_THRESHOLD) {
        back = members;
    }
    else {
        long i, j, mask = 64;
        VALUE name;

        while (mask < members_length * AREF_HASH_UNIT) mask *= 2;

        back = rb_ary_hidden_new(mask + 1);
        rb_ary_store(back, mask, INT2FIX(members_length));
        mask -= 2;			  /* mask = (2**k-1)*2 */

        for (i=0; i < members_length; i++) {
            name = RARRAY_AREF(members, i);

            j = struct_member_pos_ideal(name, mask);

            for (;;) {
                if (!RTEST(RARRAY_AREF(back, j))) {
                    rb_ary_store(back, j, name);
                    rb_ary_store(back, j + 1, INT2FIX(i));
                    break;
                }
                j = struct_member_pos_probe(j, mask);
            }
        }
        OBJ_FREEZE(back);
    }
    rb_ivar_set(klass, id_members, members);
    rb_ivar_set(klass, id_back_members, back);

    return members;
}

static inline int
struct_member_pos(VALUE s, VALUE name)
{
    VALUE back = struct_ivar_get(rb_obj_class(s), id_back_members);
    long j, mask;

    if (UNLIKELY(NIL_P(back))) {
        rb_raise(rb_eTypeError, "uninitialized struct");
    }
    if (UNLIKELY(!RB_TYPE_P(back, T_ARRAY))) {
        rb_raise(rb_eTypeError, "corrupted struct");
    }

    mask = RARRAY_LEN(back);

    if (mask <= AREF_HASH_THRESHOLD) {
        if (UNLIKELY(RSTRUCT_LEN(s) != mask)) {
            rb_raise(rb_eTypeError,
                     "struct size differs (%ld required %ld given)",
                     mask, RSTRUCT_LEN(s));
        }
        for (j = 0; j < mask; j++) {
            if (RARRAY_AREF(back, j) == name)
                return (int)j;
        }
        return -1;
    }

    if (UNLIKELY(RSTRUCT_LEN(s) != FIX2INT(RARRAY_AREF(back, mask-1)))) {
        rb_raise(rb_eTypeError, "struct size differs (%d required %ld given)",
                 FIX2INT(RARRAY_AREF(back, mask-1)), RSTRUCT_LEN(s));
    }

    mask -= 3;
    j = struct_member_pos_ideal(name, mask);

    for (;;) {
        VALUE e = RARRAY_AREF(back, j);
        if (e == name)
            return FIX2INT(RARRAY_AREF(back, j + 1));
        if (!RTEST(e)) {
            return -1;
        }
        j = struct_member_pos_probe(j, mask);
    }
}

/*
 *  call-seq:
 *    StructClass::members -> array_of_symbols
 *
 *  Returns the member names of the Struct descendant as an array:
 *
 *     Customer = Struct.new(:name, :address, :zip)
 *     Customer.members # => [:name, :address, :zip]
 *
 */

static VALUE
rb_struct_s_members_m(VALUE klass)
{
    VALUE members = rb_struct_s_members(klass);

    return rb_ary_dup(members);
}

/*
 *  call-seq:
 *    members -> array_of_symbols
 *
 *  Returns the member names from +self+ as an array:
 *
 *     Customer = Struct.new(:name, :address, :zip)
 *     Customer.new.members # => [:name, :address, :zip]
 *
 *  Related: #to_a.
 */

static VALUE
rb_struct_members_m(VALUE obj)
{
    return rb_struct_s_members_m(rb_obj_class(obj));
}

VALUE
rb_struct_getmember(VALUE obj, ID id)
{
    VALUE slot = ID2SYM(id);
    int i = struct_member_pos(obj, slot);
    if (i != -1) {
        return RSTRUCT_GET(obj, i);
    }
    rb_name_err_raise("'%1$s' is not a struct member", obj, ID2SYM(id));

    UNREACHABLE_RETURN(Qnil);
}

static void
rb_struct_modify(VALUE s)
{
    rb_check_frozen(s);
}

static VALUE
anonymous_struct(VALUE klass)
{
    VALUE nstr;

    nstr = rb_class_new(klass);
    rb_make_metaclass(nstr, RBASIC(klass)->klass);
    rb_class_inherited(klass, nstr);
    return nstr;
}

static VALUE
new_struct(VALUE name, VALUE super)
{
    /* old style: should we warn? */
    ID id;
    name = rb_str_to_str(name);
    if (!rb_is_const_name(name)) {
        rb_name_err_raise("identifier %1$s needs to be constant",
                          super, name);
    }
    id = rb_to_id(name);
    if (rb_const_defined_at(super, id)) {
        rb_warn("redefining constant %"PRIsVALUE"::%"PRIsVALUE, super, name);
        rb_mod_remove_const(super, ID2SYM(id));
    }
    return rb_define_class_id_under_no_pin(super, id, super);
}

NORETURN(static void invalid_struct_pos(VALUE s, VALUE idx));

static void
define_aref_method(VALUE nstr, VALUE name, VALUE off)
{
    rb_add_method_optimized(nstr, SYM2ID(name), OPTIMIZED_METHOD_TYPE_STRUCT_AREF, FIX2UINT(off), METHOD_VISI_PUBLIC);
}

static void
define_aset_method(VALUE nstr, VALUE name, VALUE off)
{
    rb_add_method_optimized(nstr, SYM2ID(name), OPTIMIZED_METHOD_TYPE_STRUCT_ASET, FIX2UINT(off), METHOD_VISI_PUBLIC);
}

static VALUE
rb_struct_s_inspect(VALUE klass)
{
    VALUE inspect = rb_class_name(klass);
    if (RTEST(rb_struct_s_keyword_init(klass))) {
        rb_str_cat_cstr(inspect, "(keyword_init: true)");
    }
    return inspect;
}

static VALUE
rb_data_s_new(int argc, const VALUE *argv, VALUE klass)
{
    if (rb_keyword_given_p()) {
        if (argc > 1 || !RB_TYPE_P(argv[0], T_HASH)) {
            rb_error_arity(argc, 0, 0);
        }
        return rb_class_new_instance_pass_kw(argc, argv, klass);
    }
    else {
        VALUE members = struct_ivar_get(klass, id_members);
        int num_members = RARRAY_LENINT(members);

        rb_check_arity(argc, 0, num_members);
        VALUE arg_hash = rb_hash_new_with_size(argc);
        for (long i=0; i<argc; i++) {
            VALUE k = rb_ary_entry(members, i), v = argv[i];
            rb_hash_aset(arg_hash, k, v);
        }
        return rb_class_new_instance_kw(1, &arg_hash, klass, RB_PASS_KEYWORDS);
    }
}

#if 0 /* for RDoc */

/*
 * call-seq:
 *   StructClass::keyword_init? -> true or falsy value
 *
 * Returns +true+ if the class was initialized with <tt>keyword_init: true</tt>.
 * Otherwise returns +nil+ or +false+.
 *
 * Examples:
 *   Foo = Struct.new(:a)
 *   Foo.keyword_init? # => nil
 *   Bar = Struct.new(:a, keyword_init: true)
 *   Bar.keyword_init? # => true
 *   Baz = Struct.new(:a, keyword_init: false)
 *   Baz.keyword_init? # => false
 */
static VALUE
rb_struct_s_keyword_init_p(VALUE obj)
{
}
#endif

#define rb_struct_s_keyword_init_p rb_struct_s_keyword_init

static VALUE
setup_struct(VALUE nstr, VALUE members)
{
    long i, len;

    members = struct_set_members(nstr, members);

    rb_define_alloc_func(nstr, struct_alloc);
    rb_define_singleton_method(nstr, "new", rb_class_new_instance_pass_kw, -1);
    rb_define_singleton_method(nstr, "[]", rb_class_new_instance_pass_kw, -1);
    rb_define_singleton_method(nstr, "members", rb_struct_s_members_m, 0);
    rb_define_singleton_method(nstr, "inspect", rb_struct_s_inspect, 0);
    rb_define_singleton_method(nstr, "keyword_init?", rb_struct_s_keyword_init_p, 0);

    len = RARRAY_LEN(members);
    for (i=0; i< len; i++) {
        VALUE sym = RARRAY_AREF(members, i);
        ID id = SYM2ID(sym);
        VALUE off = LONG2NUM(i);

        define_aref_method(nstr, sym, off);
        define_aset_method(nstr, ID2SYM(rb_id_attrset(id)), off);
    }

    return nstr;
}

static VALUE
setup_data(VALUE subclass, VALUE members)
{
    long i, len;

    members = struct_set_members(subclass, members);

    rb_define_alloc_func(subclass, struct_alloc);
    VALUE sclass = rb_singleton_class(subclass);
    rb_undef_method(sclass, "define");
    rb_define_method(sclass, "new", rb_data_s_new, -1);
    rb_define_method(sclass, "[]", rb_data_s_new, -1);
    rb_define_method(sclass, "members", rb_struct_s_members_m, 0);
    rb_define_method(sclass, "inspect", rb_struct_s_inspect, 0); // FIXME: just a separate method?..

    len = RARRAY_LEN(members);
    for (i=0; i< len; i++) {
        VALUE sym = RARRAY_AREF(members, i);
        VALUE off = LONG2NUM(i);

        define_aref_method(subclass, sym, off);
    }

    return subclass;
}

VALUE
rb_struct_alloc_noinit(VALUE klass)
{
    return struct_alloc(klass);
}

static VALUE
struct_make_members_list(va_list ar)
{
    char *mem;
    VALUE ary, list = rb_ident_hash_new();
    RBASIC_CLEAR_CLASS(list);
    while ((mem = va_arg(ar, char*)) != 0) {
        VALUE sym = rb_sym_intern_ascii_cstr(mem);
        if (RTEST(rb_hash_has_key(list, sym))) {
            rb_raise(rb_eArgError, "duplicate member: %s", mem);
        }
        rb_hash_aset(list, sym, Qtrue);
    }
    ary = rb_hash_keys(list);
    RBASIC_CLEAR_CLASS(ary);
    OBJ_FREEZE(ary);
    return ary;
}

static VALUE
struct_define_without_accessor(VALUE outer, const char *class_name, VALUE super, rb_alloc_func_t alloc, VALUE members)
{
    VALUE klass;

    if (class_name) {
        if (outer) {
            klass = rb_define_class_under(outer, class_name, super);
        }
        else {
            klass = rb_define_class(class_name, super);
        }
    }
    else {
        klass = anonymous_struct(super);
    }

    struct_set_members(klass, members);

    if (alloc) {
        rb_define_alloc_func(klass, alloc);
    }
    else {
        rb_define_alloc_func(klass, struct_alloc);
    }

    return klass;
}

VALUE
rb_struct_define_without_accessor_under(VALUE outer, const char *class_name, VALUE super, rb_alloc_func_t alloc, ...)
{
    va_list ar;
    VALUE members;

    va_start(ar, alloc);
    members = struct_make_members_list(ar);
    va_end(ar);

    return struct_define_without_accessor(outer, class_name, super, alloc, members);
}

VALUE
rb_struct_define_without_accessor(const char *class_name, VALUE super, rb_alloc_func_t alloc, ...)
{
    va_list ar;
    VALUE members;

    va_start(ar, alloc);
    members = struct_make_members_list(ar);
    va_end(ar);

    return struct_define_without_accessor(0, class_name, super, alloc, members);
}

VALUE
rb_struct_define(const char *name, ...)
{
    va_list ar;
    VALUE st, ary;

    va_start(ar, name);
    ary = struct_make_members_list(ar);
    va_end(ar);

    if (!name) {
        st = anonymous_struct(rb_cStruct);
    }
    else {
        st = new_struct(rb_str_new2(name), rb_cStruct);
        rb_vm_register_global_object(st);
    }
    return setup_struct(st, ary);
}

VALUE
rb_struct_define_under(VALUE outer, const char *name, ...)
{
    va_list ar;
    VALUE ary;

    va_start(ar, name);
    ary = struct_make_members_list(ar);
    va_end(ar);

    return setup_struct(rb_define_class_id_under(outer, rb_intern(name), rb_cStruct), ary);
}

/*
 *  call-seq:
 *    Struct.new(*member_names, keyword_init: nil){|Struct_subclass| ... } -> Struct_subclass
 *    Struct.new(class_name, *member_names, keyword_init: nil){|Struct_subclass| ... } -> Struct_subclass
 *    Struct_subclass.new(*member_names) -> Struct_subclass_instance
 *    Struct_subclass.new(**member_names) -> Struct_subclass_instance
 *
 *  <tt>Struct.new</tt> returns a new subclass of +Struct+.  The new subclass:
 *
 *  - May be anonymous, or may have the name given by +class_name+.
 *  - May have members as given by +member_names+.
 *  - May have initialization via ordinary arguments, or via keyword arguments
 *
 *  The new subclass has its own method <tt>::new</tt>; thus:
 *
 *    Foo = Struct.new('Foo', :foo, :bar) # => Struct::Foo
 *    f = Foo.new(0, 1)                   # => #<struct Struct::Foo foo=0, bar=1>
 *
 *  <b>\Class Name</b>
 *
 *  With string argument +class_name+,
 *  returns a new subclass of +Struct+ named <tt>Struct::<em>class_name</em></tt>:
 *
 *    Foo = Struct.new('Foo', :foo, :bar) # => Struct::Foo
 *    Foo.name                            # => "Struct::Foo"
 *    Foo.superclass                      # => Struct
 *
 *  Without string argument +class_name+,
 *  returns a new anonymous subclass of +Struct+:
 *
 *    Struct.new(:foo, :bar).name # => nil
 *
 *  <b>Block</b>
 *
 *  With a block given, the created subclass is yielded to the block:
 *
 *    Customer = Struct.new('Customer', :name, :address) do |new_class|
 *      p "The new subclass is #{new_class}"
 *      def greeting
 *        "Hello #{name} at #{address}"
 *      end
 *    end           # => Struct::Customer
 *    dave = Customer.new('Dave', '123 Main')
 *    dave # =>     #<struct Struct::Customer name="Dave", address="123 Main">
 *    dave.greeting # => "Hello Dave at 123 Main"
 *
 *  Output, from <tt>Struct.new</tt>:
 *
 *    "The new subclass is Struct::Customer"
 *
 *  <b>Member Names</b>
 *
 *  Symbol arguments +member_names+
 *  determines the members of the new subclass:
 *
 *    Struct.new(:foo, :bar).members        # => [:foo, :bar]
 *    Struct.new('Foo', :foo, :bar).members # => [:foo, :bar]
 *
 *  The new subclass has instance methods corresponding to +member_names+:
 *
 *    Foo = Struct.new('Foo', :foo, :bar)
 *    Foo.instance_methods(false) # => [:foo, :bar, :foo=, :bar=]
 *    f = Foo.new                 # => #<struct Struct::Foo foo=nil, bar=nil>
 *    f.foo                       # => nil
 *    f.foo = 0                   # => 0
 *    f.bar                       # => nil
 *    f.bar = 1                   # => 1
 *    f                           # => #<struct Struct::Foo foo=0, bar=1>
 *
 *  <b>Singleton Methods</b>
 *
 *  A subclass returned by Struct.new has these singleton methods:
 *
 *  - \Method <tt>::new </tt> creates an instance of the subclass:
 *
 *      Foo.new          # => #<struct Struct::Foo foo=nil, bar=nil>
 *      Foo.new(0)       # => #<struct Struct::Foo foo=0, bar=nil>
 *      Foo.new(0, 1)    # => #<struct Struct::Foo foo=0, bar=1>
 *      Foo.new(0, 1, 2) # Raises ArgumentError: struct size differs
 *
 *      # Initialization with keyword arguments:
 *      Foo.new(foo: 0)         # => #<struct Struct::Foo foo=0, bar=nil>
 *      Foo.new(foo: 0, bar: 1) # => #<struct Struct::Foo foo=0, bar=1>
 *      Foo.new(foo: 0, bar: 1, baz: 2)
 *      # Raises ArgumentError: unknown keywords: baz
 *
 *  - \Method <tt>:inspect</tt> returns a string representation of the subclass:
 *
 *      Foo.inspect
 *      # => "Struct::Foo"
 *
 *  - \Method <tt>::members</tt> returns an array of the member names:
 *
 *      Foo.members # => [:foo, :bar]
 *
 *  <b>Keyword Argument</b>
 *
 *  By default, the arguments for initializing an instance of the new subclass
 *  can be both positional and keyword arguments.
 *
 *  Optional keyword argument <tt>keyword_init:</tt> allows to force only one
 *  type of arguments to be accepted:
 *
 *    KeywordsOnly = Struct.new(:foo, :bar, keyword_init: true)
 *    KeywordsOnly.new(bar: 1, foo: 0)
 *    # => #<struct KeywordsOnly foo=0, bar=1>
 *    KeywordsOnly.new(0, 1)
 *    # Raises ArgumentError: wrong number of arguments
 *
 *    PositionalOnly = Struct.new(:foo, :bar, keyword_init: false)
 *    PositionalOnly.new(0, 1)
 *    # => #<struct PositionalOnly foo=0, bar=1>
 *    PositionalOnly.new(bar: 1, foo: 0)
 *    # => #<struct PositionalOnly foo={:foo=>1, :bar=>2}, bar=nil>
 *    # Note that no error is raised, but arguments treated as one hash value
 *
 *    # Same as not providing keyword_init:
 *    Any = Struct.new(:foo, :bar, keyword_init: nil)
 *    Any.new(foo: 1, bar: 2)
 *    # => #<struct Any foo=1, bar=2>
 *    Any.new(1, 2)
 *    # => #<struct Any foo=1, bar=2>
 */

static VALUE
rb_struct_s_def(int argc, VALUE *argv, VALUE klass)
{
    VALUE name = Qnil, rest, keyword_init = Qnil;
    long i;
    VALUE st;
    VALUE opt;

    argc = rb_scan_args(argc, argv, "0*:", NULL, &opt);
    if (argc >= 1 && !SYMBOL_P(argv[0])) {
        name = argv[0];
        --argc;
        ++argv;
    }

    if (!NIL_P(opt)) {
        static ID keyword_ids[1];

        if (!keyword_ids[0]) {
            keyword_ids[0] = rb_intern("keyword_init");
        }
        rb_get_kwargs(opt, keyword_ids, 0, 1, &keyword_init);
        if (UNDEF_P(keyword_init)) {
            keyword_init = Qnil;
        }
        else if (RTEST(keyword_init)) {
            keyword_init = Qtrue;
        }
    }

    rest = rb_ident_hash_new();
    RBASIC_CLEAR_CLASS(rest);
    for (i=0; i<argc; i++) {
        VALUE mem = rb_to_symbol(argv[i]);
        if (rb_is_attrset_sym(mem)) {
            rb_raise(rb_eArgError, "invalid struct member: %"PRIsVALUE, mem);
        }
        if (RTEST(rb_hash_has_key(rest, mem))) {
            rb_raise(rb_eArgError, "duplicate member: %"PRIsVALUE, mem);
        }
        rb_hash_aset(rest, mem, Qtrue);
    }
    rest = rb_hash_keys(rest);
    RBASIC_CLEAR_CLASS(rest);
    OBJ_FREEZE(rest);
    if (NIL_P(name)) {
        st = anonymous_struct(klass);
    }
    else {
        st = new_struct(name, klass);
    }
    setup_struct(st, rest);
    rb_ivar_set(st, id_keyword_init, keyword_init);
    if (rb_block_given_p()) {
        rb_mod_module_eval(0, 0, st);
    }

    return st;
}

static long
num_members(VALUE klass)
{
    VALUE members;
    members = struct_ivar_get(klass, id_members);
    if (!RB_TYPE_P(members, T_ARRAY)) {
        rb_raise(rb_eTypeError, "broken members");
    }
    return RARRAY_LEN(members);
}

/*
 */

struct struct_hash_set_arg {
    VALUE self;
    VALUE unknown_keywords;
};

static int rb_struct_pos(VALUE s, VALUE *name);

static int
struct_hash_set_i(VALUE key, VALUE val, VALUE arg)
{
    struct struct_hash_set_arg *args = (struct struct_hash_set_arg *)arg;
    int i = rb_struct_pos(args->self, &key);
    if (i < 0) {
        if (NIL_P(args->unknown_keywords)) {
            args->unknown_keywords = rb_ary_new();
        }
        rb_ary_push(args->unknown_keywords, key);
    }
    else {
        rb_struct_modify(args->self);
        RSTRUCT_SET(args->self, i, val);
    }
    return ST_CONTINUE;
}

static VALUE
rb_struct_initialize_m(int argc, const VALUE *argv, VALUE self)
{
    VALUE klass = rb_obj_class(self);
    rb_struct_modify(self);
    long n = num_members(klass);
    if (argc == 0) {
        rb_mem_clear((VALUE *)RSTRUCT_CONST_PTR(self), n);
        return Qnil;
    }

    bool keyword_init = false;
    switch (rb_struct_s_keyword_init(klass)) {
      default:
        if (argc > 1 || !RB_TYPE_P(argv[0], T_HASH)) {
            rb_error_arity(argc, 0, 0);
        }
        keyword_init = true;
        break;
      case Qfalse:
        break;
      case Qnil:
        if (argc > 1 || !RB_TYPE_P(argv[0], T_HASH)) {
            break;
        }
        keyword_init = rb_keyword_given_p();
        break;
    }
    if (keyword_init) {
        struct struct_hash_set_arg arg;
        rb_mem_clear((VALUE *)RSTRUCT_CONST_PTR(self), n);
        arg.self = self;
        arg.unknown_keywords = Qnil;
        rb_hash_foreach(argv[0], struct_hash_set_i, (VALUE)&arg);
        if (arg.unknown_keywords != Qnil) {
            rb_raise(rb_eArgError, "unknown keywords: %s",
                     RSTRING_PTR(rb_ary_join(arg.unknown_keywords, rb_str_new2(", "))));
        }
    }
    else {
        if (n < argc) {
            rb_raise(rb_eArgError, "struct size differs");
        }
        for (long i=0; i<argc; i++) {
            RSTRUCT_SET(self, i, argv[i]);
        }
        if (n > argc) {
            rb_mem_clear((VALUE *)RSTRUCT_CONST_PTR(self)+argc, n-argc);
        }
    }
    return Qnil;
}

VALUE
rb_struct_initialize(VALUE self, VALUE values)
{
    rb_struct_initialize_m(RARRAY_LENINT(values), RARRAY_CONST_PTR(values), self);
    if (rb_obj_is_kind_of(self, rb_cData)) OBJ_FREEZE(self);
    RB_GC_GUARD(values);
    return Qnil;
}

static VALUE *
struct_heap_alloc(VALUE st, size_t len)
{
    return ALLOC_N(VALUE, len);
}

static VALUE
struct_alloc(VALUE klass)
{
    long n = num_members(klass);
    size_t embedded_size = offsetof(struct RStruct, as.ary) + (sizeof(VALUE) * n);
    VALUE flags = T_STRUCT | (RGENGC_WB_PROTECTED_STRUCT ? FL_WB_PROTECTED : 0);

    if (n > 0 && rb_gc_size_allocatable_p(embedded_size)) {
        flags |= n << RSTRUCT_EMBED_LEN_SHIFT;

        NEWOBJ_OF(st, struct RStruct, klass, flags, embedded_size, 0);

        rb_mem_clear((VALUE *)st->as.ary, n);

        return (VALUE)st;
    }
    else {
        NEWOBJ_OF(st, struct RStruct, klass, flags, sizeof(struct RStruct), 0);

        st->as.heap.ptr = struct_heap_alloc((VALUE)st, n);
        rb_mem_clear((VALUE *)st->as.heap.ptr, n);
        st->as.heap.len = n;

        return (VALUE)st;
    }
}

VALUE
rb_struct_alloc(VALUE klass, VALUE values)
{
    return rb_class_new_instance(RARRAY_LENINT(values), RARRAY_CONST_PTR(values), klass);
}

VALUE
rb_struct_new(VALUE klass, ...)
{
    VALUE tmpargs[16], *mem = tmpargs;
    int size, i;
    va_list args;

    size = rb_long2int(num_members(klass));
    if (size > numberof(tmpargs)) {
        tmpargs[0] = rb_ary_hidden_new(size);
        mem = RARRAY_PTR(tmpargs[0]);
    }
    va_start(args, klass);
    for (i=0; i<size; i++) {
        mem[i] = va_arg(args, VALUE);
    }
    va_end(args);

    return rb_class_new_instance(size, mem, klass);
}

static VALUE
struct_enum_size(VALUE s, VALUE args, VALUE eobj)
{
    return rb_struct_size(s);
}

/*
 *  call-seq:
 *    each {|value| ... } -> self
 *    each -> enumerator
 *
 *  Calls the given block with the value of each member; returns +self+:
 *
 *    Customer = Struct.new(:name, :address, :zip)
 *    joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *    joe.each {|value| p value }
 *
 *  Output:
 *
 *    "Joe Smith"
 *    "123 Maple, Anytown NC"
 *    12345
 *
 *  Returns an Enumerator if no block is given.
 *
 *  Related: #each_pair.
 */

static VALUE
rb_struct_each(VALUE s)
{
    long i;

    RETURN_SIZED_ENUMERATOR(s, 0, 0, struct_enum_size);
    for (i=0; i<RSTRUCT_LEN(s); i++) {
        rb_yield(RSTRUCT_GET(s, i));
    }
    return s;
}

/*
 *  call-seq:
 *    each_pair {|(name, value)| ... } -> self
 *    each_pair -> enumerator
 *
 *  Calls the given block with each member name/value pair; returns +self+:
 *
 *    Customer = Struct.new(:name, :address, :zip) # => Customer
 *    joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *    joe.each_pair {|(name, value)| p "#{name} => #{value}" }
 *
 *  Output:
 *
 *    "name => Joe Smith"
 *    "address => 123 Maple, Anytown NC"
 *    "zip => 12345"
 *
 *  Returns an Enumerator if no block is given.
 *
 *  Related: #each.
 *
 */

static VALUE
rb_struct_each_pair(VALUE s)
{
    VALUE members;
    long i;

    RETURN_SIZED_ENUMERATOR(s, 0, 0, struct_enum_size);
    members = rb_struct_members(s);
    if (rb_block_pair_yield_optimizable()) {
        for (i=0; i<RSTRUCT_LEN(s); i++) {
            VALUE key = rb_ary_entry(members, i);
            VALUE value = RSTRUCT_GET(s, i);
            rb_yield_values(2, key, value);
        }
    }
    else {
        for (i=0; i<RSTRUCT_LEN(s); i++) {
            VALUE key = rb_ary_entry(members, i);
            VALUE value = RSTRUCT_GET(s, i);
            rb_yield(rb_assoc_new(key, value));
        }
    }
    return s;
}

static VALUE
inspect_struct(VALUE s, VALUE prefix, int recur)
{
    VALUE cname = rb_class_path(rb_obj_class(s));
    VALUE members;
    VALUE str = prefix;
    long i, len;
    char first = RSTRING_PTR(cname)[0];

    if (recur || first != '#') {
        rb_str_append(str, cname);
    }
    if (recur) {
        return rb_str_cat2(str, ":...>");
    }

    members = rb_struct_members(s);
    len = RSTRUCT_LEN(s);

    for (i=0; i<len; i++) {
        VALUE slot;
        ID id;

        if (i > 0) {
            rb_str_cat2(str, ", ");
        }
        else if (first != '#') {
            rb_str_cat2(str, " ");
        }
        slot = RARRAY_AREF(members, i);
        id = SYM2ID(slot);
        if (rb_is_local_id(id) || rb_is_const_id(id)) {
            rb_str_append(str, rb_id2str(id));
        }
        else {
            rb_str_append(str, rb_inspect(slot));
        }
        rb_str_cat2(str, "=");
        rb_str_append(str, rb_inspect(RSTRUCT_GET(s, i)));
    }
    rb_str_cat2(str, ">");

    return str;
}

/*
 *  call-seq:
 *    inspect -> string
 *
 *  Returns a string representation of +self+:
 *
 *    Customer = Struct.new(:name, :address, :zip) # => Customer
 *    joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *    joe.inspect # => "#<struct Customer name=\"Joe Smith\", address=\"123 Maple, Anytown NC\", zip=12345>"
 *
 */

static VALUE
rb_struct_inspect(VALUE s)
{
    return rb_exec_recursive(inspect_struct, s, rb_str_new2("#<struct "));
}

/*
 *  call-seq:
 *    to_a     -> array
 *
 *  Returns the values in +self+ as an array:
 *
 *    Customer = Struct.new(:name, :address, :zip)
 *    joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *    joe.to_a # => ["Joe Smith", "123 Maple, Anytown NC", 12345]
 *
 *  Related: #members.
 */

static VALUE
rb_struct_to_a(VALUE s)
{
    return rb_ary_new4(RSTRUCT_LEN(s), RSTRUCT_CONST_PTR(s));
}

/*
 *  call-seq:
 *    to_h -> hash
 *    to_h {|name, value| ... } -> hash
 *
 *  Returns a hash containing the name and value for each member:
 *
 *    Customer = Struct.new(:name, :address, :zip)
 *    joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *    h = joe.to_h
 *    h # => {:name=>"Joe Smith", :address=>"123 Maple, Anytown NC", :zip=>12345}
 *
 *  If a block is given, it is called with each name/value pair;
 *  the block should return a 2-element array whose elements will become
 *  a key/value pair in the returned hash:
 *
 *    h = joe.to_h{|name, value| [name.upcase, value.to_s.upcase]}
 *    h # => {:NAME=>"JOE SMITH", :ADDRESS=>"123 MAPLE, ANYTOWN NC", :ZIP=>"12345"}
 *
 *  Raises ArgumentError if the block returns an inappropriate value.
 *
 */

static VALUE
rb_struct_to_h(VALUE s)
{
    VALUE h = rb_hash_new_with_size(RSTRUCT_LEN(s));
    VALUE members = rb_struct_members(s);
    long i;
    int block_given = rb_block_given_p();

    for (i=0; i<RSTRUCT_LEN(s); i++) {
        VALUE k = rb_ary_entry(members, i), v = RSTRUCT_GET(s, i);
        if (block_given)
            rb_hash_set_pair(h, rb_yield_values(2, k, v));
        else
            rb_hash_aset(h, k, v);
    }
    return h;
}

/*
 *  call-seq:
 *    deconstruct_keys(array_of_names) -> hash
 *
 *  Returns a hash of the name/value pairs for the given member names.
 *
 *    Customer = Struct.new(:name, :address, :zip)
 *    joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *    h = joe.deconstruct_keys([:zip, :address])
 *    h # => {:zip=>12345, :address=>"123 Maple, Anytown NC"}
 *
 *  Returns all names and values if +array_of_names+ is +nil+:
 *
 *    h = joe.deconstruct_keys(nil)
 *    h # => {:name=>"Joseph Smith, Jr.", :address=>"123 Maple, Anytown NC", :zip=>12345}
 *
 */
static VALUE
rb_struct_deconstruct_keys(VALUE s, VALUE keys)
{
    VALUE h;
    long i;

    if (NIL_P(keys)) {
        return rb_struct_to_h(s);
    }
    if (UNLIKELY(!RB_TYPE_P(keys, T_ARRAY))) {
        rb_raise(rb_eTypeError,
                 "wrong argument type %"PRIsVALUE" (expected Array or nil)",
                 rb_obj_class(keys));

    }
    if (RSTRUCT_LEN(s) < RARRAY_LEN(keys)) {
        return rb_hash_new_with_size(0);
    }
    h = rb_hash_new_with_size(RARRAY_LEN(keys));
    for (i=0; i<RARRAY_LEN(keys); i++) {
        VALUE key = RARRAY_AREF(keys, i);
        int i = rb_struct_pos(s, &key);
        if (i < 0) {
            return h;
        }
        rb_hash_aset(h, key, RSTRUCT_GET(s, i));
    }
    return h;
}

/* :nodoc: */
VALUE
rb_struct_init_copy(VALUE copy, VALUE s)
{
    long i, len;

    if (!OBJ_INIT_COPY(copy, s)) return copy;
    if (RSTRUCT_LEN(copy) != RSTRUCT_LEN(s)) {
        rb_raise(rb_eTypeError, "struct size mismatch");
    }

    for (i=0, len=RSTRUCT_LEN(copy); i<len; i++) {
        RSTRUCT_SET(copy, i, RSTRUCT_GET(s, i));
    }

    return copy;
}

static int
rb_struct_pos(VALUE s, VALUE *name)
{
    long i;
    VALUE idx = *name;

    if (SYMBOL_P(idx)) {
        return struct_member_pos(s, idx);
    }
    else if (RB_TYPE_P(idx, T_STRING)) {
        idx = rb_check_symbol(name);
        if (NIL_P(idx)) return -1;
        return struct_member_pos(s, idx);
    }
    else {
        long len;
        i = NUM2LONG(idx);
        len = RSTRUCT_LEN(s);
        if (i < 0) {
            if (i + len < 0) {
                *name = LONG2FIX(i);
                return -1;
            }
            i += len;
        }
        else if (len <= i) {
            *name = LONG2FIX(i);
            return -1;
        }
        return (int)i;
    }
}

static void
invalid_struct_pos(VALUE s, VALUE idx)
{
    if (FIXNUM_P(idx)) {
        long i = FIX2INT(idx), len = RSTRUCT_LEN(s);
        if (i < 0) {
            rb_raise(rb_eIndexError, "offset %ld too small for struct(size:%ld)",
                     i, len);
        }
        else {
            rb_raise(rb_eIndexError, "offset %ld too large for struct(size:%ld)",
                     i, len);
        }
    }
    else {
        rb_name_err_raise("no member '%1$s' in struct", s, idx);
    }
}

/*
 *  call-seq:
 *    struct[name] -> object
 *    struct[n] -> object
 *
 *  Returns a value from +self+.
 *
 *  With symbol or string argument +name+ given, returns the value for the named member:
 *
 *    Customer = Struct.new(:name, :address, :zip)
 *    joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *    joe[:zip] # => 12345
 *
 *  Raises NameError if +name+ is not the name of a member.
 *
 *  With integer argument +n+ given, returns <tt>self.values[n]</tt>
 *  if +n+ is in range;
 *  see Array@Array+Indexes:
 *
 *    joe[2]  # => 12345
 *    joe[-2] # => "123 Maple, Anytown NC"
 *
 *  Raises IndexError if +n+ is out of range.
 *
 */

VALUE
rb_struct_aref(VALUE s, VALUE idx)
{
    int i = rb_struct_pos(s, &idx);
    if (i < 0) invalid_struct_pos(s, idx);
    return RSTRUCT_GET(s, i);
}

/*
 *  call-seq:
 *    struct[name] = value -> value
 *    struct[n] = value -> value
 *
 *  Assigns a value to a member.
 *
 *  With symbol or string argument +name+ given, assigns the given +value+
 *  to the named member; returns +value+:
 *
 *    Customer = Struct.new(:name, :address, :zip)
 *    joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *    joe[:zip] = 54321 # => 54321
 *    joe # => #<struct Customer name="Joe Smith", address="123 Maple, Anytown NC", zip=54321>
 *
 *  Raises NameError if +name+ is not the name of a member.
 *
 *  With integer argument +n+ given, assigns the given +value+
 *  to the +n+-th member if +n+ is in range;
 *  see Array@Array+Indexes:
 *
 *    joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *    joe[2] = 54321           # => 54321
 *    joe[-3] = 'Joseph Smith' # => "Joseph Smith"
 *    joe # => #<struct Customer name="Joseph Smith", address="123 Maple, Anytown NC", zip=54321>
 *
 *  Raises IndexError if +n+ is out of range.
 *
 */

VALUE
rb_struct_aset(VALUE s, VALUE idx, VALUE val)
{
    int i = rb_struct_pos(s, &idx);
    if (i < 0) invalid_struct_pos(s, idx);
    rb_struct_modify(s);
    RSTRUCT_SET(s, i, val);
    return val;
}

FUNC_MINIMIZED(VALUE rb_struct_lookup(VALUE s, VALUE idx));
NOINLINE(static VALUE rb_struct_lookup_default(VALUE s, VALUE idx, VALUE notfound));

VALUE
rb_struct_lookup(VALUE s, VALUE idx)
{
    return rb_struct_lookup_default(s, idx, Qnil);
}

static VALUE
rb_struct_lookup_default(VALUE s, VALUE idx, VALUE notfound)
{
    int i = rb_struct_pos(s, &idx);
    if (i < 0) return notfound;
    return RSTRUCT_GET(s, i);
}

static VALUE
struct_entry(VALUE s, long n)
{
    return rb_struct_aref(s, LONG2NUM(n));
}

/*
 *  call-seq:
 *    values_at(*integers) -> array
 *    values_at(integer_range) -> array
 *
 *  Returns an array of values from +self+.
 *
 *  With integer arguments +integers+ given,
 *  returns an array containing each value given by one of +integers+:
 *
 *    Customer = Struct.new(:name, :address, :zip)
 *    joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *    joe.values_at(0, 2)    # => ["Joe Smith", 12345]
 *    joe.values_at(2, 0)    # => [12345, "Joe Smith"]
 *    joe.values_at(2, 1, 0) # => [12345, "123 Maple, Anytown NC", "Joe Smith"]
 *    joe.values_at(0, -3)   # => ["Joe Smith", "Joe Smith"]
 *
 *  Raises IndexError if any of +integers+ is out of range;
 *  see Array@Array+Indexes.
 *
 *  With integer range argument +integer_range+ given,
 *  returns an array containing each value given by the elements of the range;
 *  fills with +nil+ values for range elements larger than the structure:
 *
 *    joe.values_at(0..2)
 *    # => ["Joe Smith", "123 Maple, Anytown NC", 12345]
 *    joe.values_at(-3..-1)
 *    # => ["Joe Smith", "123 Maple, Anytown NC", 12345]
 *    joe.values_at(1..4) # => ["123 Maple, Anytown NC", 12345, nil, nil]
 *
 *  Raises RangeError if any element of the range is negative and out of range;
 *  see Array@Array+Indexes.
 *
 */

static VALUE
rb_struct_values_at(int argc, VALUE *argv, VALUE s)
{
    return rb_get_values_at(s, RSTRUCT_LEN(s), argc, argv, struct_entry);
}

/*
 *  call-seq:
 *    select {|value| ... } -> array
 *    select -> enumerator
 *
 *  With a block given, returns an array of values from +self+
 *  for which the block returns a truthy value:
 *
 *    Customer = Struct.new(:name, :address, :zip)
 *    joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *    a = joe.select {|value| value.is_a?(String) }
 *    a # => ["Joe Smith", "123 Maple, Anytown NC"]
 *    a = joe.select {|value| value.is_a?(Integer) }
 *    a # => [12345]
 *
 *  With no block given, returns an Enumerator.
 */

static VALUE
rb_struct_select(int argc, VALUE *argv, VALUE s)
{
    VALUE result;
    long i;

    rb_check_arity(argc, 0, 0);
    RETURN_SIZED_ENUMERATOR(s, 0, 0, struct_enum_size);
    result = rb_ary_new();
    for (i = 0; i < RSTRUCT_LEN(s); i++) {
        if (RTEST(rb_yield(RSTRUCT_GET(s, i)))) {
            rb_ary_push(result, RSTRUCT_GET(s, i));
        }
    }

    return result;
}

static VALUE
recursive_equal(VALUE s, VALUE s2, int recur)
{
    long i, len;

    if (recur) return Qtrue; /* Subtle! */
    len = RSTRUCT_LEN(s);
    for (i=0; i<len; i++) {
        if (!rb_equal(RSTRUCT_GET(s, i), RSTRUCT_GET(s2, i))) return Qfalse;
    }
    return Qtrue;
}


/*
 *  call-seq:
 *    self == other -> true or false
 *
 *  Returns  +true+ if and only if the following are true; otherwise returns +false+:
 *
 *  - <tt>other.class == self.class</tt>.
 *  - For each member name +name+, <tt>other.name == self.name</tt>.
 *
 *  Examples:
 *
 *    Customer = Struct.new(:name, :address, :zip)
 *    joe    = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *    joe_jr = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *    joe_jr == joe # => true
 *    joe_jr[:name] = 'Joe Smith, Jr.'
 *    # => "Joe Smith, Jr."
 *    joe_jr == joe # => false
 */

static VALUE
rb_struct_equal(VALUE s, VALUE s2)
{
    if (s == s2) return Qtrue;
    if (!RB_TYPE_P(s2, T_STRUCT)) return Qfalse;
    if (rb_obj_class(s) != rb_obj_class(s2)) return Qfalse;
    if (RSTRUCT_LEN(s) != RSTRUCT_LEN(s2)) {
        rb_bug("inconsistent struct"); /* should never happen */
    }

    return rb_exec_recursive_paired(recursive_equal, s, s2, s2);
}

/*
 *  call-seq:
 *    hash -> integer
 *
 *  Returns the integer hash value for +self+.
 *
 *  Two structs of the same class and with the same content
 *  will have the same hash code (and will compare using Struct#eql?):
 *
 *    Customer = Struct.new(:name, :address, :zip)
 *    joe    = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *    joe_jr = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *    joe.hash == joe_jr.hash # => true
 *    joe_jr[:name] = 'Joe Smith, Jr.'
 *    joe.hash == joe_jr.hash # => false
 *
 *  Related: Object#hash.
 */

static VALUE
rb_struct_hash(VALUE s)
{
    long i, len;
    st_index_t h;
    VALUE n;

    h = rb_hash_start(rb_hash(rb_obj_class(s)));
    len = RSTRUCT_LEN(s);
    for (i = 0; i < len; i++) {
        n = rb_hash(RSTRUCT_GET(s, i));
        h = rb_hash_uint(h, NUM2LONG(n));
    }
    h = rb_hash_end(h);
    return ST2FIX(h);
}

static VALUE
recursive_eql(VALUE s, VALUE s2, int recur)
{
    long i, len;

    if (recur) return Qtrue; /* Subtle! */
    len = RSTRUCT_LEN(s);
    for (i=0; i<len; i++) {
        if (!rb_eql(RSTRUCT_GET(s, i), RSTRUCT_GET(s2, i))) return Qfalse;
    }
    return Qtrue;
}

/*
 * call-seq:
 *   eql?(other) -> true or false
 *
 *  Returns +true+ if and only if the following are true; otherwise returns +false+:
 *
 *  - <tt>other.class == self.class</tt>.
 *  - For each member name +name+, <tt>other.name.eql?(self.name)</tt>.
 *
 *     Customer = Struct.new(:name, :address, :zip)
 *     joe    = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *     joe_jr = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *     joe_jr.eql?(joe) # => true
 *     joe_jr[:name] = 'Joe Smith, Jr.'
 *     joe_jr.eql?(joe) # => false
 *
 *  Related: Object#==.
 */

static VALUE
rb_struct_eql(VALUE s, VALUE s2)
{
    if (s == s2) return Qtrue;
    if (!RB_TYPE_P(s2, T_STRUCT)) return Qfalse;
    if (rb_obj_class(s) != rb_obj_class(s2)) return Qfalse;
    if (RSTRUCT_LEN(s) != RSTRUCT_LEN(s2)) {
        rb_bug("inconsistent struct"); /* should never happen */
    }

    return rb_exec_recursive_paired(recursive_eql, s, s2, s2);
}

/*
 *  call-seq:
 *    size -> integer
 *
 *  Returns the number of members.
 *
 *    Customer = Struct.new(:name, :address, :zip)
 *    joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *    joe.size #=> 3
 *
 */

VALUE
rb_struct_size(VALUE s)
{
    return LONG2FIX(RSTRUCT_LEN(s));
}

/*
 * call-seq:
 *   dig(name, *identifiers) -> object
 *   dig(n, *identifiers) -> object
 *
 *  Finds and returns an object among nested objects.
 *  The nested objects may be instances of various classes.
 *  See {Dig Methods}[rdoc-ref:dig_methods.rdoc].
 *
 *
 *  Given symbol or string argument +name+,
 *  returns the object that is specified by +name+ and +identifiers+:
 *
 *   Foo = Struct.new(:a)
 *   f = Foo.new(Foo.new({b: [1, 2, 3]}))
 *   f.dig(:a) # => #<struct Foo a={:b=>[1, 2, 3]}>
 *   f.dig(:a, :a) # => {:b=>[1, 2, 3]}
 *   f.dig(:a, :a, :b) # => [1, 2, 3]
 *   f.dig(:a, :a, :b, 0) # => 1
 *   f.dig(:b, 0) # => nil
 *
 *  Given integer argument +n+,
 *  returns the object that is specified by +n+ and +identifiers+:
 *
 *   f.dig(0) # => #<struct Foo a={:b=>[1, 2, 3]}>
 *   f.dig(0, 0) # => {:b=>[1, 2, 3]}
 *   f.dig(0, 0, :b) # => [1, 2, 3]
 *   f.dig(0, 0, :b, 0) # => 1
 *   f.dig(:b, 0) # => nil
 *
 */

static VALUE
rb_struct_dig(int argc, VALUE *argv, VALUE self)
{
    rb_check_arity(argc, 1, UNLIMITED_ARGUMENTS);
    self = rb_struct_lookup(self, *argv);
    if (!--argc) return self;
    ++argv;
    return rb_obj_dig(argc, argv, self, Qnil);
}

/*
 *  Document-class: Data
 *
 *  \Class \Data provides a convenient way to define simple classes
 *  for value-alike objects.
 *
 *  The simplest example of usage:
 *
 *     Measure = Data.define(:amount, :unit)
 *
 *     # Positional arguments constructor is provided
 *     distance = Measure.new(100, 'km')
 *     #=> #<data Measure amount=100, unit="km">
 *
 *     # Keyword arguments constructor is provided
 *     weight = Measure.new(amount: 50, unit: 'kg')
 *     #=> #<data Measure amount=50, unit="kg">
 *
 *     # Alternative form to construct an object:
 *     speed = Measure[10, 'mPh']
 *     #=> #<data Measure amount=10, unit="mPh">
 *
 *     # Works with keyword arguments, too:
 *     area = Measure[amount: 1.5, unit: 'm^2']
 *     #=> #<data Measure amount=1.5, unit="m^2">
 *
 *     # Argument accessors are provided:
 *     distance.amount #=> 100
 *     distance.unit #=> "km"
 *
 *  Constructed object also has a reasonable definitions of #==
 *  operator, #to_h hash conversion, and #deconstruct / #deconstruct_keys
 *  to be used in pattern matching.
 *
 *  ::define method accepts an optional block and evaluates it in
 *  the context of the newly defined class. That allows to define
 *  additional methods:
 *
 *     Measure = Data.define(:amount, :unit) do
 *       def <=>(other)
 *         return unless other.is_a?(self.class) && other.unit == unit
 *         amount <=> other.amount
 *       end
 *
 *       include Comparable
 *     end
 *
 *     Measure[3, 'm'] < Measure[5, 'm'] #=> true
 *     Measure[3, 'm'] < Measure[5, 'kg']
 *     # comparison of Measure with Measure failed (ArgumentError)
 *
 *  Data provides no member writers, or enumerators: it is meant
 *  to be a storage for immutable atomic values. But note that
 *  if some of data members is of a mutable class, Data does no additional
 *  immutability enforcement:
 *
 *     Event = Data.define(:time, :weekdays)
 *     event = Event.new('18:00', %w[Tue Wed Fri])
 *     #=> #<data Event time="18:00", weekdays=["Tue", "Wed", "Fri"]>
 *
 *     # There is no #time= or #weekdays= accessors, but changes are
 *     # still possible:
 *     event.weekdays << 'Sat'
 *     event
 *     #=> #<data Event time="18:00", weekdays=["Tue", "Wed", "Fri", "Sat"]>
 *
 *  See also Struct, which is a similar concept, but has more
 *  container-alike API, allowing to change contents of the object
 *  and enumerate it.
 */

/*
 * call-seq:
 *   define(*symbols) -> class
 *
 *  Defines a new \Data class.
 *
 *     measure = Data.define(:amount, :unit)
 *     #=> #<Class:0x00007f70c6868498>
 *     measure.new(1, 'km')
 *     #=> #<data amount=1, unit="km">
 *
 *     # It you store the new class in the constant, it will
 *     # affect #inspect and will be more natural to use:
 *     Measure = Data.define(:amount, :unit)
 *     #=> Measure
 *     Measure.new(1, 'km')
 *     #=> #<data Measure amount=1, unit="km">
 *
 *
 *  Note that member-less \Data is acceptable and might be a useful technique
 *  for defining several homogeneous data classes, like
 *
 *     class HTTPFetcher
 *       Response = Data.define(:body)
 *       NotFound = Data.define
 *       # ... implementation
 *     end
 *
 *  Now, different kinds of responses from +HTTPFetcher+ would have consistent
 *  representation:
 *
 *      #<data HTTPFetcher::Response body="<html...">
 *      #<data HTTPFetcher::NotFound>
 *
 *  And are convenient to use in pattern matching:
 *
 *     case fetcher.get(url)
 *     in HTTPFetcher::Response(body)
 *       # process body variable
 *     in HTTPFetcher::NotFound
 *       # handle not found case
 *     end
 */

static VALUE
rb_data_s_def(int argc, VALUE *argv, VALUE klass)
{
    VALUE rest;
    long i;
    VALUE data_class;

    rest = rb_ident_hash_new();
    RBASIC_CLEAR_CLASS(rest);
    for (i=0; i<argc; i++) {
        VALUE mem = rb_to_symbol(argv[i]);
        if (rb_is_attrset_sym(mem)) {
            rb_raise(rb_eArgError, "invalid data member: %"PRIsVALUE, mem);
        }
        if (RTEST(rb_hash_has_key(rest, mem))) {
            rb_raise(rb_eArgError, "duplicate member: %"PRIsVALUE, mem);
        }
        rb_hash_aset(rest, mem, Qtrue);
    }
    rest = rb_hash_keys(rest);
    RBASIC_CLEAR_CLASS(rest);
    OBJ_FREEZE(rest);
    data_class = anonymous_struct(klass);
    setup_data(data_class, rest);
    if (rb_block_given_p()) {
        rb_mod_module_eval(0, 0, data_class);
    }

    return data_class;
}

VALUE
rb_data_define(VALUE super, ...)
{
    va_list ar;
    VALUE ary;
    va_start(ar, super);
    ary = struct_make_members_list(ar);
    va_end(ar);
    if (!super) super = rb_cData;
    VALUE klass = setup_data(anonymous_struct(super), ary);
    rb_vm_register_global_object(klass);
    return klass;
}

/*
 *  call-seq:
 *    DataClass::members -> array_of_symbols
 *
 *  Returns an array of member names of the data class:
 *
 *     Measure = Data.define(:amount, :unit)
 *     Measure.members # => [:amount, :unit]
 *
 */

#define rb_data_s_members_m rb_struct_s_members_m


/*
 * call-seq:
 *   new(*args) -> instance
 *   new(**kwargs) -> instance
 *   ::[](*args) -> instance
 *   ::[](**kwargs) -> instance
 *
 *  Constructors for classes defined with ::define accept both positional and
 *  keyword arguments.
 *
 *     Measure = Data.define(:amount, :unit)
 *
 *     Measure.new(1, 'km')
 *     #=> #<data Measure amount=1, unit="km">
 *     Measure.new(amount: 1, unit: 'km')
 *     #=> #<data Measure amount=1, unit="km">
 *
 *     # Alternative shorter initialization with []
 *     Measure[1, 'km']
 *     #=> #<data Measure amount=1, unit="km">
 *     Measure[amount: 1, unit: 'km']
 *     #=> #<data Measure amount=1, unit="km">
 *
 *  All arguments are mandatory (unlike Struct), and converted to keyword arguments:
 *
 *     Measure.new(amount: 1)
 *     # in `initialize': missing keyword: :unit (ArgumentError)
 *
 *     Measure.new(1)
 *     # in `initialize': missing keyword: :unit (ArgumentError)
 *
 *  Note that <tt>Measure#initialize</tt> always receives keyword arguments, and that
 *  mandatory arguments are checked in +initialize+, not in +new+. This can be
 *  important for redefining initialize in order to convert arguments or provide
 *  defaults:
 *
 *     Measure = Data.define(:amount, :unit) do
 *       NONE = Data.define
 *
 *       def initialize(amount:, unit: NONE.new)
 *         super(amount: Float(amount), unit:)
 *       end
 *     end
 *
 *     Measure.new('10', 'km') # => #<data Measure amount=10.0, unit="km">
 *     Measure.new(10_000)     # => #<data Measure amount=10000.0, unit=#<data NONE>>
 *
 */

static VALUE
rb_data_initialize_m(int argc, const VALUE *argv, VALUE self)
{
    VALUE klass = rb_obj_class(self);
    rb_struct_modify(self);
    VALUE members = struct_ivar_get(klass, id_members);
    size_t num_members = RARRAY_LEN(members);

    if (argc == 0) {
        if (num_members > 0) {
            rb_exc_raise(rb_keyword_error_new("missing", members));
        }
        return Qnil;
    }
    if (argc > 1 || !RB_TYPE_P(argv[0], T_HASH)) {
        rb_error_arity(argc, 0, 0);
    }

    if (RHASH_SIZE(argv[0]) < num_members) {
        VALUE missing = rb_ary_diff(members, rb_hash_keys(argv[0]));
        rb_exc_raise(rb_keyword_error_new("missing", missing));
    }

    struct struct_hash_set_arg arg;
    rb_mem_clear((VALUE *)RSTRUCT_CONST_PTR(self), num_members);
    arg.self = self;
    arg.unknown_keywords = Qnil;
    rb_hash_foreach(argv[0], struct_hash_set_i, (VALUE)&arg);
    // Freeze early before potentially raising, so that we don't leave an
    // unfrozen copy on the heap, which could get exposed via ObjectSpace.
    OBJ_FREEZE(self);
    if (arg.unknown_keywords != Qnil) {
        rb_exc_raise(rb_keyword_error_new("unknown", arg.unknown_keywords));
    }
    return Qnil;
}

/* :nodoc: */
static VALUE
rb_data_init_copy(VALUE copy, VALUE s)
{
    copy = rb_struct_init_copy(copy, s);
    RB_OBJ_FREEZE(copy);
    return copy;
}

/*
 *  call-seq:
 *   with(**kwargs) -> instance
 *
 *  Returns a shallow copy of +self+ --- the instance variables of
 *  +self+ are copied, but not the objects they reference.
 *
 *  If the method is supplied any keyword arguments, the copy will
 *  be created with the respective field values updated to use the
 *  supplied keyword argument values. Note that it is an error to
 *  supply a keyword that the Data class does not have as a member.
 *
 *    Point = Data.define(:x, :y)
 *
 *    origin = Point.new(x: 0, y: 0)
 *
 *    up = origin.with(x: 1)
 *    right = origin.with(y: 1)
 *    up_and_right = up.with(y: 1)
 *
 *    p origin       # #<data Point x=0, y=0>
 *    p up           # #<data Point x=1, y=0>
 *    p right        # #<data Point x=0, y=1>
 *    p up_and_right # #<data Point x=1, y=1>
 *
 *    out = origin.with(z: 1) # ArgumentError: unknown keyword: :z
 *    some_point = origin.with(1, 2) # ArgumentError: expected keyword arguments, got positional arguments
 *
 */

static VALUE
rb_data_with(int argc, const VALUE *argv, VALUE self)
{
    VALUE kwargs;
    rb_scan_args(argc, argv, "0:", &kwargs);
    if (NIL_P(kwargs)) {
        return self;
    }

    VALUE h = rb_struct_to_h(self);
    rb_hash_update_by(h, kwargs, 0);
    return rb_class_new_instance_kw(1, &h, rb_obj_class(self), TRUE);
}

/*
 *  call-seq:
 *    inspect -> string
 *    to_s -> string
 *
 *  Returns a string representation of +self+:
 *
 *    Measure = Data.define(:amount, :unit)
 *
 *    distance = Measure[10, 'km']
 *
 *    p distance  # uses #inspect underneath
 *    #<data Measure amount=10, unit="km">
 *
 *    puts distance  # uses #to_s underneath, same representation
 *    #<data Measure amount=10, unit="km">
 *
 */

static VALUE
rb_data_inspect(VALUE s)
{
    return rb_exec_recursive(inspect_struct, s, rb_str_new2("#<data "));
}

/*
 *  call-seq:
 *    self == other -> true or false
 *
 *  Returns  +true+ if +other+ is the same class as +self+, and all members are
 *  equal.
 *
 *  Examples:
 *
 *    Measure = Data.define(:amount, :unit)
 *
 *    Measure[1, 'km'] == Measure[1, 'km'] #=> true
 *    Measure[1, 'km'] == Measure[2, 'km'] #=> false
 *    Measure[1, 'km'] == Measure[1, 'm']  #=> false
 *
 *    Measurement = Data.define(:amount, :unit)
 *    # Even though Measurement and Measure have the same "shape"
 *    # their instances are never equal
 *    Measure[1, 'km'] == Measurement[1, 'km'] #=> false
 */

#define rb_data_equal rb_struct_equal

/*
 *  call-seq:
 *    self.eql?(other) -> true or false
 *
 *  Equality check that is used when two items of data are keys of a Hash.
 *
 *  The subtle difference with #== is that members are also compared with their
 *  #eql? method, which might be important in some cases:
 *
 *    Measure = Data.define(:amount, :unit)
 *
 *    Measure[1, 'km'] == Measure[1.0, 'km'] #=> true, they are equal as values
 *    # ...but...
 *    Measure[1, 'km'].eql? Measure[1.0, 'km'] #=> false, they represent different hash keys
 *
 *  See also Object#eql? for further explanations of the method usage.
 */

#define rb_data_eql rb_struct_eql

/*
 *  call-seq:
 *    hash -> integer
 *
 *  Redefines Object#hash (used to distinguish objects as Hash keys) so that
 *  data objects of the same class with same content would have the same +hash+
 *  value, and represented the same Hash key.
 *
 *    Measure = Data.define(:amount, :unit)
 *
 *    Measure[1, 'km'].hash == Measure[1, 'km'].hash #=> true
 *    Measure[1, 'km'].hash == Measure[10, 'km'].hash #=> false
 *    Measure[1, 'km'].hash == Measure[1, 'm'].hash #=> false
 *    Measure[1, 'km'].hash == Measure[1.0, 'km'].hash #=> false
 *
 *    # Structurally similar data class, but shouldn't be considered
 *    # the same hash key
 *    Measurement = Data.define(:amount, :unit)
 *
 *    Measure[1, 'km'].hash == Measurement[1, 'km'].hash #=> false
 */

#define rb_data_hash rb_struct_hash

/*
 *  call-seq:
 *    to_h -> hash
 *    to_h {|name, value| ... } -> hash
 *
 *  Returns Hash representation of the data object.
 *
 *    Measure = Data.define(:amount, :unit)
 *    distance = Measure[10, 'km']
 *
 *    distance.to_h
 *    #=> {:amount=>10, :unit=>"km"}
 *
 *  Like Enumerable#to_h, if the block is provided, it is expected to
 *  produce key-value pairs to construct a hash:
 *
 *
 *    distance.to_h { |name, val| [name.to_s, val.to_s] }
 *    #=> {"amount"=>"10", "unit"=>"km"}
 *
 *  Note that there is a useful symmetry between #to_h and #initialize:
 *
 *   distance2 = Measure.new(**distance.to_h)
 *   #=> #<data Measure amount=10, unit="km">
 *   distance2 == distance
 *   #=> true
 */

#define rb_data_to_h rb_struct_to_h

/*
 *  call-seq:
 *    members -> array_of_symbols
 *
 *  Returns the member names from +self+ as an array:
 *
 *     Measure = Data.define(:amount, :unit)
 *     distance = Measure[10, 'km']
 *
 *     distance.members #=> [:amount, :unit]
 *
 */

#define rb_data_members_m rb_struct_members_m

/*
 *  call-seq:
 *    deconstruct     -> array
 *
 *  Returns the values in +self+ as an array, to use in pattern matching:
 *
 *    Measure = Data.define(:amount, :unit)
 *
 *    distance = Measure[10, 'km']
 *    distance.deconstruct #=> [10, "km"]
 *
 *    # usage
 *    case distance
 *    in n, 'km' # calls #deconstruct underneath
 *      puts "It is #{n} kilometers away"
 *    else
 *      puts "Don't know how to handle it"
 *    end
 *    # prints "It is 10 kilometers away"
 *
 *  Or, with checking the class, too:
 *
 *    case distance
 *    in Measure(n, 'km')
 *      puts "It is #{n} kilometers away"
 *    # ...
 *    end
 */

#define rb_data_deconstruct rb_struct_to_a

/*
 *  call-seq:
 *    deconstruct_keys(array_of_names_or_nil) -> hash
 *
 *  Returns a hash of the name/value pairs, to use in pattern matching.
 *
 *    Measure = Data.define(:amount, :unit)
 *
 *    distance = Measure[10, 'km']
 *    distance.deconstruct_keys(nil) #=> {:amount=>10, :unit=>"km"}
 *    distance.deconstruct_keys([:amount]) #=> {:amount=>10}
 *
 *    # usage
 *    case distance
 *    in amount:, unit: 'km' # calls #deconstruct_keys underneath
 *      puts "It is #{amount} kilometers away"
 *    else
 *      puts "Don't know how to handle it"
 *    end
 *    # prints "It is 10 kilometers away"
 *
 *  Or, with checking the class, too:
 *
 *    case distance
 *    in Measure(amount:, unit: 'km')
 *      puts "It is #{amount} kilometers away"
 *    # ...
 *    end
 */

#define rb_data_deconstruct_keys rb_struct_deconstruct_keys

/*
 *  Document-class: Struct
 *
 *  \Class \Struct provides a convenient way to create a simple class
 *  that can store and fetch values.
 *
 *  This example creates a subclass of +Struct+, <tt>Struct::Customer</tt>;
 *  the first argument, a string, is the name of the subclass;
 *  the other arguments, symbols, determine the _members_ of the new subclass.
 *
 *    Customer = Struct.new('Customer', :name, :address, :zip)
 *    Customer.name       # => "Struct::Customer"
 *    Customer.class      # => Class
 *    Customer.superclass # => Struct
 *
 *  Corresponding to each member are two methods, a writer and a reader,
 *  that store and fetch values:
 *
 *    methods = Customer.instance_methods false
 *    methods # => [:zip, :address=, :zip=, :address, :name, :name=]
 *
 *  An instance of the subclass may be created,
 *  and its members assigned values, via method <tt>::new</tt>:
 *
 *    joe = Customer.new("Joe Smith", "123 Maple, Anytown NC", 12345)
 *    joe # => #<struct Struct::Customer name="Joe Smith", address="123 Maple, Anytown NC", zip=12345>
 *
 *  The member values may be managed thus:
 *
 *    joe.name    # => "Joe Smith"
 *    joe.name = 'Joseph Smith'
 *    joe.name    # => "Joseph Smith"
 *
 *  And thus; note that member name may be expressed as either a string or a symbol:
 *
 *    joe[:name]  # => "Joseph Smith"
 *    joe[:name] = 'Joseph Smith, Jr.'
 *    joe['name'] # => "Joseph Smith, Jr."
 *
 *  See Struct::new.
 *
 *  == What's Here
 *
 *  First, what's elsewhere. \Class \Struct:
 *
 *  - Inherits from {class Object}[rdoc-ref:Object@What-27s+Here].
 *  - Includes {module Enumerable}[rdoc-ref:Enumerable@What-27s+Here],
 *    which provides dozens of additional methods.
 *
 *  See also Data, which is a somewhat similar, but stricter concept for defining immutable
 *  value objects.
 *
 *  Here, class \Struct provides methods that are useful for:
 *
 *  - {Creating a Struct Subclass}[rdoc-ref:Struct@Methods+for+Creating+a+Struct+Subclass]
 *  - {Querying}[rdoc-ref:Struct@Methods+for+Querying]
 *  - {Comparing}[rdoc-ref:Struct@Methods+for+Comparing]
 *  - {Fetching}[rdoc-ref:Struct@Methods+for+Fetching]
 *  - {Assigning}[rdoc-ref:Struct@Methods+for+Assigning]
 *  - {Iterating}[rdoc-ref:Struct@Methods+for+Iterating]
 *  - {Converting}[rdoc-ref:Struct@Methods+for+Converting]
 *
 *  === Methods for Creating a Struct Subclass
 *
 *  - ::new: Returns a new subclass of \Struct.
 *
 *  === Methods for Querying
 *
 *  - #hash: Returns the integer hash code.
 *  - #size (aliased as #length): Returns the number of members.
 *
 *  === Methods for Comparing
 *
 *  - #==: Returns whether a given object is equal to +self+, using <tt>==</tt>
 *    to compare member values.
 *  - #eql?: Returns whether a given object is equal to +self+,
 *    using <tt>eql?</tt> to compare member values.
 *
 *  === Methods for Fetching
 *
 *  - #[]: Returns the value associated with a given member name.
 *  - #to_a (aliased as #values, #deconstruct): Returns the member values in +self+ as an array.
 *  - #deconstruct_keys: Returns a hash of the name/value pairs
 *    for given member names.
 *  - #dig: Returns the object in nested objects that is specified
 *    by a given member name and additional arguments.
 *  - #members: Returns an array of the member names.
 *  - #select (aliased as #filter): Returns an array of member values from +self+,
 *    as selected by the given block.
 *  - #values_at: Returns an array containing values for given member names.
 *
 *  === Methods for Assigning
 *
 *  - #[]=: Assigns a given value to a given member name.
 *
 *  === Methods for Iterating
 *
 *  - #each: Calls a given block with each member name.
 *  - #each_pair: Calls a given block with each member name/value pair.
 *
 *  === Methods for Converting
 *
 *  - #inspect (aliased as #to_s): Returns a string representation of +self+.
 *  - #to_h: Returns a hash of the member name/value pairs in +self+.
 *
 */
void
InitVM_Struct(void)
{
    rb_cStruct = rb_define_class("Struct", rb_cObject);
    rb_include_module(rb_cStruct, rb_mEnumerable);

    rb_undef_alloc_func(rb_cStruct);
    rb_define_singleton_method(rb_cStruct, "new", rb_struct_s_def, -1);
#if 0 /* for RDoc */
    rb_define_singleton_method(rb_cStruct, "keyword_init?", rb_struct_s_keyword_init_p, 0);
    rb_define_singleton_method(rb_cStruct, "members", rb_struct_s_members_m, 0);
#endif

    rb_define_method(rb_cStruct, "initialize", rb_struct_initialize_m, -1);
    rb_define_method(rb_cStruct, "initialize_copy", rb_struct_init_copy, 1);

    rb_define_method(rb_cStruct, "==", rb_struct_equal, 1);
    rb_define_method(rb_cStruct, "eql?", rb_struct_eql, 1);
    rb_define_method(rb_cStruct, "hash", rb_struct_hash, 0);

    rb_define_method(rb_cStruct, "inspect", rb_struct_inspect, 0);
    rb_define_alias(rb_cStruct,  "to_s", "inspect");
    rb_define_method(rb_cStruct, "to_a", rb_struct_to_a, 0);
    rb_define_method(rb_cStruct, "to_h", rb_struct_to_h, 0);
    rb_define_method(rb_cStruct, "values", rb_struct_to_a, 0);
    rb_define_method(rb_cStruct, "size", rb_struct_size, 0);
    rb_define_method(rb_cStruct, "length", rb_struct_size, 0);

    rb_define_method(rb_cStruct, "each", rb_struct_each, 0);
    rb_define_method(rb_cStruct, "each_pair", rb_struct_each_pair, 0);
    rb_define_method(rb_cStruct, "[]", rb_struct_aref, 1);
    rb_define_method(rb_cStruct, "[]=", rb_struct_aset, 2);
    rb_define_method(rb_cStruct, "select", rb_struct_select, -1);
    rb_define_method(rb_cStruct, "filter", rb_struct_select, -1);
    rb_define_method(rb_cStruct, "values_at", rb_struct_values_at, -1);

    rb_define_method(rb_cStruct, "members", rb_struct_members_m, 0);
    rb_define_method(rb_cStruct, "dig", rb_struct_dig, -1);

    rb_define_method(rb_cStruct, "deconstruct", rb_struct_to_a, 0);
    rb_define_method(rb_cStruct, "deconstruct_keys", rb_struct_deconstruct_keys, 1);

    rb_cData = rb_define_class("Data", rb_cObject);

    rb_undef_method(CLASS_OF(rb_cData), "new");
    rb_undef_alloc_func(rb_cData);
    rb_define_singleton_method(rb_cData, "define", rb_data_s_def, -1);

#if 0 /* for RDoc */
    rb_define_singleton_method(rb_cData, "members", rb_data_s_members_m, 0);
#endif

    rb_define_method(rb_cData, "initialize", rb_data_initialize_m, -1);
    rb_define_method(rb_cData, "initialize_copy", rb_data_init_copy, 1);

    rb_define_method(rb_cData, "==", rb_data_equal, 1);
    rb_define_method(rb_cData, "eql?", rb_data_eql, 1);
    rb_define_method(rb_cData, "hash", rb_data_hash, 0);

    rb_define_method(rb_cData, "inspect", rb_data_inspect, 0);
    rb_define_alias(rb_cData,  "to_s", "inspect");
    rb_define_method(rb_cData, "to_h", rb_data_to_h, 0);

    rb_define_method(rb_cData, "members", rb_data_members_m, 0);

    rb_define_method(rb_cData, "deconstruct", rb_data_deconstruct, 0);
    rb_define_method(rb_cData, "deconstruct_keys", rb_data_deconstruct_keys, 1);

    rb_define_method(rb_cData, "with", rb_data_with, -1);
}

#undef rb_intern
void
Init_Struct(void)
{
    id_members = rb_intern("__members__");
    id_back_members = rb_intern("__members_back__");
    id_keyword_init = rb_intern("__keyword_init__");

    InitVM(Struct);
}
