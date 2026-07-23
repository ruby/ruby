#include "internal.h"
#include "internal/box.h"
#include "internal/string.h"
#include "internal/variable.h"
#include "vm_core.h"
#include "iseq.h"
#include "builtin.h"

#include "builtin_binary.rbbin"

#ifndef BUILTIN_BINARY_SIZE

#define BUILTIN_LOADED(feature_name, iseq) ((void)0)
#include "mini_builtin.c"

#else

static const unsigned char *
bin4feature(const struct builtin_binary *bb, const char *feature, size_t *psize)
{
    *psize = bb->bin_size;
    return strcmp(bb->feature, feature) ? NULL : bb->bin;
}

static const unsigned char*
builtin_lookup(const char *feature, size_t *psize)
{
    static size_t index = 0;
    const unsigned char *bin = NULL;

    /*
     * Fast path:
     * builtin_binary is usually arranged in the same order
     * as features are looked up in miniruby, so try the next entry first.
     */
    if (builtin_binary[index].feature) {
        bin = bin4feature(&builtin_binary[index], feature, psize);
        index++;
    }
    if (bin) {
        return bin;
    }

    /*
     * Fallback:
     * In case the lookup order does not match the array order,
     * scan the entire table to find the feature.
     */
    for (const struct builtin_binary *bb = &builtin_binary[0];
         bb->feature;
         bb++) {
        bin = bin4feature(bb, feature, psize);
        if (bin) {
            break;
        }
    }

    return bin;
}

static void
load_with_builtin_functions(const char *feature_name, const struct rb_builtin_function *table, const rb_box_t *target_box)
{
    // search binary
    size_t size;
    const unsigned char *bin = builtin_lookup(feature_name, &size);
    if (! bin) {
        rb_bug("builtin_lookup: can not find %s", feature_name);
    }

    // load binary
    rb_vm_t *vm = GET_VM();
    if (vm->builtin_function_table != NULL) rb_bug("vm->builtin_function_table should be NULL.");
    vm->builtin_function_table = table;
    const rb_iseq_t *iseq = rb_iseq_ibf_load_bytes((const char *)bin, size);
    ASSUME(iseq); // otherwise an exception should have raised
    vm->builtin_function_table = NULL;

    // exec
    rb_iseq_eval(rb_iseq_check(iseq), target_box);
}

void
rb_load_with_builtin_functions(const char *feature_name, const struct rb_builtin_function *table)
{
    load_with_builtin_functions(feature_name, table, rb_root_box());
}

VALUE
rb_define_gem_modules(VALUE flags_value, VALUE _)
{
    rb_box_gem_flags_t *flags = (rb_box_gem_flags_t *)flags_value;

    if (flags->gem) {
        rb_define_module("Gem");
        // Make the error decoration gems autoload on first constant access.
        // error.c loads them for error display on the first error
        // (or eagerly via Process.warmup).
        if (flags->error_highlight) {
            rb_autoload_str(rb_cObject, rb_intern("ErrorHighlight"), rb_fstring_cstr("error_highlight"));
        }
        if (flags->did_you_mean) {
            rb_autoload_str(rb_cObject, rb_intern("DidYouMean"), rb_fstring_cstr("did_you_mean"));
        }
        if (flags->syntax_suggest) {
            rb_autoload_str(rb_cObject, rb_intern("SyntaxSuggest"), rb_fstring_cstr("syntax_suggest"));
        }
    }

    return Qnil;
}

void
rb_load_gem_prelude(VALUE box)
{
    load_with_builtin_functions("gem_prelude", NULL, (const rb_box_t *)box);
}

struct gem_prelude_without_bundler_setup_args {
    VALUE box;
    VALUE key;
    VALUE value;
};

static VALUE
load_gem_prelude_without_bundler_setup(VALUE data)
{
    struct gem_prelude_without_bundler_setup_args *args =
        (struct gem_prelude_without_bundler_setup_args *)data;

    rb_load_gem_prelude(args->box);

    return Qnil;
}

static VALUE
restore_bundler_setup(VALUE data)
{
    struct gem_prelude_without_bundler_setup_args *args =
        (struct gem_prelude_without_bundler_setup_args *)data;
    VALUE env = rb_const_get(rb_cObject, rb_intern("ENV"));

    if (NIL_P(args->value)) {
        rb_funcall(env, rb_intern("delete"), 1, args->key);
    }
    else {
        rb_funcall(env, rb_intern("[]="), 2, args->key, args->value);
    }

    return Qnil;
}

static void
rb_load_gem_prelude_without_bundler_setup(VALUE box)
{
    VALUE env = rb_const_get(rb_cObject, rb_intern("ENV"));
    struct gem_prelude_without_bundler_setup_args args = {
        .box = box,
        .key = rb_str_new_lit("BUNDLER_SETUP"),
    };

    args.value = rb_funcall(env, rb_intern("[]"), 1, args.key);
    rb_funcall(env, rb_intern("delete"), 1, args.key);

    rb_ensure(load_gem_prelude_without_bundler_setup, (VALUE)&args,
              restore_bundler_setup, (VALUE)&args);
}

#endif

void
rb_free_loaded_builtin_table(void)
{
    // do nothing
}

void
Init_builtin(void)
{
    // nothing
}

void
Init_builtin_features(void)
{

#ifdef BUILTIN_BINARY_SIZE

    if (rb_box_available()) {
        /*
         * Do not let the root box consume Bundler setup. Bundler can evaluate
         * gemspecs through TOPLEVEL_BINDING in the main box before the main
         * box has loaded RubyGems.
         */
        rb_load_gem_prelude_without_bundler_setup((VALUE)rb_root_box());
    }
    else {
        rb_load_gem_prelude((VALUE)rb_root_box());
    }

    rb_load_gem_prelude((VALUE)rb_main_box());

#endif

}
