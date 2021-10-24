#include "internal.h"
#include "internal/array.h"
#include "iseq.h"
#include "vm_core.h"
#include "builtin.h"

#include "miniprelude.c"

// included from miniinit.c

#ifndef INCLUDED_BY_BUILTIN_C
static struct st_table *loaded_builtin_table;
#endif

rb_ast_t *rb_builtin_ast(const char *feature_name, VALUE *name_str);

static const rb_iseq_t *
builtin_iseq_load(const char *feature_name, const struct rb_builtin_function *table)
{
    VALUE name_str = 0;
    rb_ast_t *ast = rb_builtin_ast(feature_name, &name_str);
    rb_vm_t *vm = GET_VM();

    vm->builtin_function_table = table;
    vm->builtin_inline_index = 0;
    static const rb_compile_option_t optimization = {
        TRUE, /* int inline_const_cache; */
        TRUE, /* int peephole_optimization; */
        FALSE,/* int tailcall_optimization; */
        TRUE, /* int specialized_instruction; */
        TRUE, /* int operands_unification; */
        TRUE, /* int instructions_unification; */
        TRUE, /* int stack_caching; */
        TRUE, /* int frozen_string_literal; */
        FALSE, /* int debug_frozen_string_literal; */
        FALSE, /* unsigned int coverage_enabled; */
        0, /* int debug_level; */
    };
    const rb_iseq_t *iseq = rb_iseq_new_with_opt(&ast->body, name_str, name_str, Qnil, INT2FIX(0), NULL, 0, ISEQ_TYPE_TOP, &optimization);
    GET_VM()->builtin_function_table = NULL;

    rb_ast_dispose(ast);

    // for debug
    if (0 && strcmp("prelude", feature_name) == 0) {
        rb_io_write(rb_stdout, rb_iseq_disasm((const rb_iseq_t *)iseq));
    }

#ifndef INCLUDED_BY_BUILTIN_C
    st_insert(loaded_builtin_table, (st_data_t)feature_name, (st_data_t)iseq);
    rb_gc_register_mark_object((VALUE)iseq);
#endif

    return iseq;
}

void
rb_load_with_builtin_functions(const char *feature_name, const struct rb_builtin_function *table)
{
    const rb_iseq_t *iseq = builtin_iseq_load(feature_name, table);
    rb_iseq_eval(iseq);
}

#ifndef INCLUDED_BY_BUILTIN_C

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
#endif
