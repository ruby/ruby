#include "internal.h"
#include "vm_core.h"
#include "iseq.h"
#include "builtin.h"

#include "builtin_binary.inc"

static const unsigned char*
builtin_lookup(const char *feature, size_t *psize)
{
    for (int i=0; i<BUILTIN_BINARY_SIZE; i++) {
        if (strcmp(builtin_binary[i].feature, feature) == 0) {
            *psize = builtin_binary[i].bin_size;
            return builtin_binary[i].bin;
        }
    }
    rb_bug("builtin_lookup: can not find %s\n", feature);
}

void
rb_load_with_builtin_functions(const char *feature_name, const char *fname, const struct rb_builtin_function *table)
{
    // search binary
    size_t size;
    const unsigned char *bin = builtin_lookup(feature_name, &size);

    // load binary
    GET_VM()->builtin_function_table = table;
    const rb_iseq_t *iseq = rb_iseq_ibf_load_bytes((const char *)bin, size);
    GET_VM()->builtin_function_table = NULL;

    // exec
    rb_iseq_eval(iseq);
}

void
Init_builtin(void)
{
    //
}
