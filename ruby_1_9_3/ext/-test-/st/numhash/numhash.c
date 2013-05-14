#include <ruby.h>
#include <ruby/st.h>

static void
numhash_free(void *ptr)
{
    if (ptr) st_free_table(ptr);
}

static VALUE
numhash_alloc(VALUE klass)
{
    return Data_Wrap_Struct(klass, 0, numhash_free, 0);
}

static VALUE
numhash_init(VALUE self)
{
    st_table *tbl = (st_table *)DATA_PTR(self);
    if (tbl) st_free_table(tbl);
    DATA_PTR(self) = st_init_numtable();
    return self;
}

static VALUE
numhash_aref(VALUE self, VALUE key)
{
    st_data_t data;
    if (!SPECIAL_CONST_P(key)) rb_raise(rb_eArgError, "not a special const");
    if (st_lookup((st_table *)DATA_PTR(self), (st_data_t)key, &data))
	return (VALUE)data;
    return Qnil;
}

static VALUE
numhash_aset(VALUE self, VALUE key, VALUE data)
{
    if (!SPECIAL_CONST_P(key)) rb_raise(rb_eArgError, "not a special const");
    if (!SPECIAL_CONST_P(data)) rb_raise(rb_eArgError, "not a special const");
    st_insert((st_table *)DATA_PTR(self), (st_data_t)key, (st_data_t)data);
    return self;
}

static int
numhash_i(st_data_t key, st_data_t value, st_data_t arg, int error)
{
    VALUE ret;
    if (key == 0 && value == 0 && error == 1) rb_raise(rb_eRuntimeError, "numhash modified");
    ret = rb_yield_values(3, (VALUE)key, (VALUE)value, (VALUE)arg);
    if (ret == Qtrue) return ST_CHECK;
    return ST_CONTINUE;
}

static VALUE
numhash_each(VALUE self)
{
    return st_foreach((st_table *)DATA_PTR(self), numhash_i, self) ? Qtrue : Qfalse;
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
}
