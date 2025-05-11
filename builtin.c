#include "internal.h"
#include "vm_core.h"
#include "iseq.h"
#include "builtin.h"

#include "builtin_binary.inc"

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
    static int index = 0;
    const unsigned char *bin = bin4feature(&builtin_binary[index++], feature, psize);

    // usually, `builtin_binary` order is loading order at miniruby.
    for (const struct builtin_binary *bb = &builtin_binary[0]; bb->feature &&! bin; bb++) {
        bin = bin4feature(bb++, feature, psize);
    }
    return bin;
}

static void
load_with_builtin_functions(const char *feature_name, const struct rb_builtin_function *table)
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

    rb_namespace_enable_builtin();

    // exec
    if (rb_namespace_available() && rb_mNamespaceRefiner) {
        rb_iseq_eval_with_refinement(rb_iseq_check(iseq), rb_mNamespaceRefiner);
    }
    else {
        rb_iseq_eval(rb_iseq_check(iseq));
    }

    rb_namespace_disable_builtin();
}

void
rb_load_with_builtin_functions(const char *feature_name, const struct rb_builtin_function *table)
{
    load_with_builtin_functions(feature_name, table);
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
    load_with_builtin_functions("gem_prelude", NULL);
}
