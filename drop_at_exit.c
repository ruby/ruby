int rb_cleanup_at_exit_i(void *vstart, void *vend, size_t stride, void *data)
{
        rb_objspace_t *objspace = &rb_objspace;
        VALUE v = (VALUE)vstart;
        for (; v != (VALUE)vend; v += stride) {
                asan_unpoison_object(v, false);
                switch (BUILTIN_TYPE(v)) {
                        case T_NONE:
                                break;
                        default:
                                obj_free(objspace, v);
                }
        }
        return 0;
}

void rb_cleanup_at_exit(void)
{
        rb_objspace_t *objspace = &rb_objspace;

        // Fix FrozenCore flags.
        // It's explicitly marked as ICLASS, but in fact it's a class
        RBASIC(rb_mRubyVMFrozenCore)->flags = T_CLASS;

        // Iterate over all pages and manually free all objects
        struct each_obj_data each_obj_data = {
                .objspace = objspace,
                .reenable_incremental = false,

                .callback = rb_cleanup_at_exit_i,
                .data = NULL,

                .pages = {NULL},
                .pages_counts = {0},
        };
        objspace_each_objects_try((VALUE)&each_obj_data);
        objspace_each_objects_ensure((VALUE)&each_obj_data);
}
