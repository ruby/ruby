#ifndef MJIT_UNIT_H
#define MJIT_UNIT_H

#include "ccan/list/list.h"

// The unit structure that holds metadata of ISeq for MJIT.
struct rb_mjit_unit {
    struct ccan_list_node unode;
    // Unique order number of unit.
    int id;
    // Dlopen handle of the loaded object file.
    void *handle;
    rb_iseq_t *iseq;
#if defined(_WIN32)
    // DLL cannot be removed while loaded on Windows. If this is set, it'll be lazily deleted.
    char *so_file;
#endif
    // Only used by unload_units. Flag to check this unit is currently on stack or not.
    bool used_code_p;
    // True if it's a unit for JIT compaction
    bool compact_p;
    // mjit_compile's optimization switches
    struct rb_mjit_compile_info compile_info;
    // captured CC values, they should be marked with iseq.
    const struct rb_callcache **cc_entries;
    unsigned int cc_entries_size; // ISEQ_BODY(iseq)->ci_size + ones of inlined iseqs
};

#endif /* MJIT_UNIT_H */
