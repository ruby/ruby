#include "internal.h"
#include "vm_core.h"
#include "iseq.h"
#include "builtin.h"

#ifdef CROSS_COMPILING

#define INCLUDED_BY_BUILTIN_C 1
#include "mini_builtin.c"

#else

#include "builtin_binary.inc"

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

void
rb_load_with_builtin_functions(const char *feature_name, const struct rb_builtin_function *table)
{
    // search binary
    size_t size;
    const unsigned char *bin = builtin_lookup(feature_name, &size);
    if (! bin) {
        rb_bug("builtin_lookup: can not find %s\n", feature_name);
    }

    // load binary
    rb_vm_t *vm = GET_VM();
    if (vm->builtin_function_table != NULL) rb_bug("vm->builtin_function_table should be NULL.");
    vm->builtin_function_table = table;
    vm->builtin_inline_index = 0;
    const rb_iseq_t *iseq = rb_iseq_ibf_load_bytes((const char *)bin, size);
    vm->builtin_function_table = NULL;

    // exec
    rb_iseq_eval(rb_iseq_check(iseq));
}

#endif

void
Init_builtin(void)
{
    // nothing
}

void
Init_builtin_features(void)
{
    rb_load_with_builtin_functions("gem_prelude", NULL);
}
