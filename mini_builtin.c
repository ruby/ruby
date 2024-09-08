#include "internal.h"
#include "internal/array.h"
#include "iseq.h"
#include "vm_core.h"
#include "builtin.h"

#include "miniprelude.c"


bool pm_builtin_ast_value(pm_parse_result_t *result, const char *feature_name, VALUE *name_str);
VALUE rb_builtin_ast_value(const char *feature_name, VALUE *name_str);

static const rb_iseq_t *
builtin_iseq_load(const char *feature_name, const struct rb_builtin_function *table)
{
    VALUE name_str = 0;
    const rb_iseq_t *iseq;

    rb_vm_t *vm = GET_VM();
    static const rb_compile_option_t optimization = {
        .inline_const_cache = TRUE,
        .peephole_optimization = TRUE,
        .tailcall_optimization = FALSE,
        .specialized_instruction = TRUE,
        .operands_unification = TRUE,
        .instructions_unification = TRUE,
        .frozen_string_literal = TRUE,
        .debug_frozen_string_literal = FALSE,
        .coverage_enabled = FALSE,
        .debug_level = 0,
    };

    if (*rb_ruby_prism_ptr()) {
        pm_parse_result_t result = { 0 };
        if (!pm_builtin_ast_value(&result, feature_name, &name_str)) {
            rb_fatal("builtin_iseq_load: can not find %s; "
                     "probably miniprelude.c is out of date",
                     feature_name);
        }

        vm->builtin_function_table = table;
        iseq = pm_iseq_new_with_opt(&result.node, name_str, name_str, Qnil, 0, NULL, 0, ISEQ_TYPE_TOP, &optimization);

        GET_VM()->builtin_function_table = NULL;
        pm_parse_result_free(&result);
    }
    else {
        VALUE ast_value = rb_builtin_ast_value(feature_name, &name_str);

        if (NIL_P(ast_value)) {
            rb_fatal("builtin_iseq_load: can not find %s; "
                     "probably miniprelude.c is out of date",
                     feature_name);
        }

        rb_ast_t *ast = rb_ruby_ast_data_get(ast_value);

        vm->builtin_function_table = table;
        iseq = rb_iseq_new_with_opt(ast_value, name_str, name_str, Qnil, 0, NULL, 0, ISEQ_TYPE_TOP, &optimization, Qnil);

        GET_VM()->builtin_function_table = NULL;
        rb_ast_dispose(ast);
    }

    // for debug
    if (0 && strcmp("prelude", feature_name) == 0) {
        rb_io_write(rb_stdout, rb_iseq_disasm((const rb_iseq_t *)iseq));
    }

    BUILTIN_LOADED(feature_name, iseq);

    return iseq;
}

void
rb_load_with_builtin_functions(const char *feature_name, const struct rb_builtin_function *table)
{
    const rb_iseq_t *iseq = builtin_iseq_load(feature_name, table);
    rb_iseq_eval(iseq);
}
