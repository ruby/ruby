#include "internal.h"
#include "vm_core.h"
#include "iseq.h"
#include "builtin.h"

#if CROSS_COMPILING

#define INCLUDED_BY_BUILTIN_C 1
#include "mini_builtin.c"

#else

#include "builtin_binary.inc"

static const unsigned char*
builtin_lookup(const char *feature, size_t *psize)
{
    static int index = 0;
    int i = index++;

    // usually, `builtin_binary` order is loading order at miniruby.
    if (LIKELY(strcmp(builtin_binary[i].feature, feature) == 0)) {
      found:
        *psize = builtin_binary[i].bin_size;
        return builtin_binary[i].bin;
    }
    else {
        if (0) fprintf(stderr, "builtin_lookup: cached index miss (index:%d)\n", i);
        for (i=0; i<BUILTIN_BINARY_SIZE; i++) {
            if (strcmp(builtin_binary[i].feature, feature) == 0) {
                goto found;
            }
        }
    }
    rb_bug("builtin_lookup: can not find %s\n", feature);
}

void
rb_load_with_builtin_functions(const char *feature_name, const struct rb_builtin_function *table)
{
    // search binary
    size_t size;
    const unsigned char *bin = builtin_lookup(feature_name, &size);

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
