#include "internal.h"
#include "internal/box.h"
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
        if (flags->error_highlight) {
            rb_define_module("ErrorHighlight");
        }
        if (flags->did_you_mean) {
            rb_define_module("DidYouMean");
        }
        if (flags->syntax_suggest) {
            rb_define_module("SyntaxSuggest");
        }
    }

    return Qnil;
}

void
rb_load_gem_prelude(VALUE box)
{
    load_with_builtin_functions("gem_prelude", NULL, (const rb_box_t *)box);
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

    rb_load_gem_prelude((VALUE)rb_root_box());

    rb_load_gem_prelude((VALUE)rb_main_box());

#endif

}
