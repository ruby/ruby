#include "internal.h"
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

    // exec
    rb_iseq_eval(rb_iseq_check(iseq), rb_root_box()); // builtin functions are loaded in the root box
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

#ifdef BUILTIN_BINARY_SIZE

    load_with_builtin_functions("gem_prelude", NULL);

#endif

}
