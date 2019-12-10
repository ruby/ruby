#include "internal.h"
#include "vm_core.h"
#include "iseq.h"
#include "builtin.h"
#include "miniprelude.c"

// included from miniinit.c

static struct st_table *loaded_builtin_table;
rb_ast_t *rb_builtin_ast(const char *feature_name, VALUE *name_str);

static const rb_iseq_t *
builtin_iseq_load(const char *feature_name, const struct rb_builtin_function *table)
{
    VALUE name_str = 0;
    rb_ast_t *ast = rb_builtin_ast(feature_name, &name_str);

    GET_VM()->builtin_function_table = table;
    const rb_iseq_t *iseq = rb_iseq_new(&ast->body, name_str, name_str, Qnil, NULL, ISEQ_TYPE_TOP);
    GET_VM()->builtin_function_table = NULL;

    rb_ast_dispose(ast);

    // for debug
    if (0 && strcmp("prelude", feature_name) == 0) {
        rb_io_write(rb_stdout, rb_iseq_disasm((const rb_iseq_t *)iseq));
    }

    st_insert(loaded_builtin_table, (st_data_t)feature_name, (st_data_t)iseq);
    rb_gc_register_mark_object((VALUE)iseq);

    return iseq;
}

void
rb_load_with_builtin_functions(const char *feature_name, const struct rb_builtin_function *table)
{
    const rb_iseq_t *iseq = builtin_iseq_load(feature_name, table);
    rb_iseq_eval(iseq);
}

static int
each_builtin_i(st_data_t key, st_data_t val, st_data_t dmy)
{
    const char *feature = (const char *)key;
    const rb_iseq_t *iseq = (const rb_iseq_t *)val;

    rb_yield_values(2, rb_str_new2(feature), rb_iseqw_new(iseq));

    return ST_CONTINUE;
}

static VALUE
each_builtin(VALUE self)
{
    st_foreach(loaded_builtin_table, each_builtin_i, 0);
    return Qnil;
}

void
Init_builtin(void)
{
    rb_define_singleton_method(rb_cRubyVM, "each_builtin", each_builtin, 0);
    loaded_builtin_table = st_init_strtable();
}

void
Init_builtin_features(void)
{
    // register for ruby
    builtin_iseq_load("gem_prelude", NULL);
}
