#include "internal.h"
#include "internal/array.h"
#include "iseq.h"
#include "vm_core.h"
#include "builtin.h"

#include "miniprelude.c"

static VALUE
prelude_ast_value(VALUE name, VALUE code, int line)
{
    rb_ast_t *ast;
    VALUE ast_value = rb_parser_compile_string_path(rb_parser_new(), name, code, line);
    ast = rb_ruby_ast_data_get(ast_value);
    if (!ast || !ast->body.root) {
        if (ast) rb_ast_dispose(ast);
        rb_exc_raise(rb_errinfo());
    }
    return ast_value;
}

static void
pm_prelude_load(pm_parse_result_t *result, VALUE name, VALUE code, int line)
{
    pm_options_line_set(&result->options, line);
    VALUE error = pm_parse_string(result, code, name, NULL);

    if (!NIL_P(error)) {
        pm_parse_result_free(result);
        rb_exc_raise(error);
    }
}

static const rb_iseq_t *
builtin_iseq_load(const char *feature_name, const struct rb_builtin_function *table)
{
    VALUE name_str = 0;
    int start_line;
    const rb_iseq_t *iseq;
    VALUE code = rb_builtin_find(feature_name, &name_str, &start_line);
    if (NIL_P(code)) {
        rb_fatal("builtin_iseq_load: can not find %s; "
                 "probably miniprelude.c is out of date",
                 feature_name);
    }

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

    if (rb_ruby_prism_p()) {
        pm_parse_result_t result = { 0 };
        pm_prelude_load(&result, name_str, code, start_line);

        vm->builtin_function_table = table;
        int error_state;
        iseq = pm_iseq_new_with_opt(&result.node, name_str, name_str, Qnil, 0, NULL, 0, ISEQ_TYPE_TOP, &optimization, &error_state);

        vm->builtin_function_table = NULL;
        pm_parse_result_free(&result);

        if (error_state) {
            RUBY_ASSERT(iseq == NULL);
            rb_jump_tag(error_state);
        }
    }
    else {
        VALUE ast_value = prelude_ast_value(name_str, code, start_line);
        rb_ast_t *ast = rb_ruby_ast_data_get(ast_value);

        vm->builtin_function_table = table;
        iseq = rb_iseq_new_with_opt(ast_value, name_str, name_str, Qnil, 0, NULL, 0, ISEQ_TYPE_TOP, &optimization, Qnil);

        vm->builtin_function_table = NULL;
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
