#include <ruby.h>
#include <ruby/st.h>

static void
numhash_free(void *ptr)
{
    if (ptr) st_free_table(ptr);
}

static size_t
numhash_memsize(const void *ptr)
{
    return st_memsize(ptr);
}

static const rb_data_type_t numhash_type = {
    "numhash",
    {0, numhash_free, numhash_memsize,},
    0, 0,
    RUBY_TYPED_FREE_IMMEDIATELY|RUBY_TYPED_WB_PROTECTED,
};

static VALUE
numhash_alloc(VALUE klass)
{
    return TypedData_Wrap_Struct(klass, &numhash_type, 0);
}

static VALUE
numhash_init(VALUE self)
{
    st_table *tbl = (st_table *)Check_TypedStruct(self, &numhash_type);
    if (tbl) st_free_table(tbl);
    DATA_PTR(self) = st_init_numtable();
    return self;
}

static VALUE
numhash_aref(VALUE self, VALUE key)
{
    st_data_t data;
    st_table *tbl = (st_table *)Check_TypedStruct(self, &numhash_type);
    if (!SPECIAL_CONST_P(key)) rb_raise(rb_eArgError, "not a special const");
    if (st_lookup(tbl, (st_data_t)key, &data))
	return (VALUE)data;
    return Qnil;
}

static VALUE
numhash_aset(VALUE self, VALUE key, VALUE data)
{
    st_table *tbl = (st_table *)Check_TypedStruct(self, &numhash_type);
    if (!SPECIAL_CONST_P(key)) rb_raise(rb_eArgError, "not a special const");
    if (!SPECIAL_CONST_P(data)) rb_raise(rb_eArgError, "not a special const");
    st_insert(tbl, (st_data_t)key, (st_data_t)data);
    return self;
}

static int
numhash_i(st_data_t key, st_data_t value, st_data_t arg)
{
    VALUE ret;
    ret = rb_yield_values(3, (VALUE)key, (VALUE)value, (VALUE)arg);
    if (ret == Qtrue) return ST_CHECK;
    return ST_CONTINUE;
}

static VALUE
numhash_each(VALUE self)
{
    st_table *table = (st_table *)Check_TypedStruct(self, &numhash_type);
    st_data_t data = (st_data_t)self;
    return st_foreach_check(table, numhash_i, data, data) ? Qtrue : Qfalse;
}

static int
update_func(st_data_t *key, st_data_t *value, st_data_t arg, int existing)
{
    VALUE ret = rb_yield_values(existing ? 2 : 1, (VALUE)*key, (VALUE)*value);
    switch (ret) {
      case Qfalse:
	return ST_STOP;
      case Qnil:
	return ST_DELETE;
      default:
	*value = ret;
	return ST_CONTINUE;
    }
}

static VALUE
numhash_update(VALUE self, VALUE key)
{
    st_table *table = (st_table *)Check_TypedStruct(self, &numhash_type);
    if (st_update(table, (st_data_t)key, update_func, 0))
	return Qtrue;
    else
	return Qfalse;
}

#if SIZEOF_LONG == SIZEOF_VOIDP
# define ST2NUM(x) ULONG2NUM(x)
#elif SIZEOF_LONG_LONG == SIZEOF_VOIDP
# define ST2NUM(x) ULL2NUM(x)
#endif

static VALUE
numhash_size(VALUE self)
{
    st_table *table = (st_table *)Check_TypedStruct(self, &numhash_type);
    return ST2NUM(table->num_entries);
}

static VALUE
numhash_delete_safe(VALUE self, VALUE key)
{
    st_table *table = (st_table *)Check_TypedStruct(self, &numhash_type);
    st_data_t val, k = (st_data_t)key;
    if (st_delete_safe(table, &k, &val, (st_data_t)self)) {
	return val;
    }
    return Qnil;
}

void
Init_numhash(void)
{
    VALUE st = rb_define_class_under(rb_define_module("Bug"), "StNumHash", rb_cData);
    rb_define_alloc_func(st, numhash_alloc);
    rb_define_method(st, "initialize", numhash_init, 0);
    rb_define_method(st, "[]", numhash_aref, 1);
    rb_define_method(st, "[]=", numhash_aset, 2);
    rb_define_method(st, "each", numhash_each, 0);
    rb_define_method(st, "update", numhash_update, 1);
    rb_define_method(st, "size", numhash_size, 0);
    rb_define_method(st, "delete_safe", numhash_delete_safe, 1);
}

