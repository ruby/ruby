#ifndef OBJSPACE_H
#define OBJSPACE_H 1

/* object_tracing.c */
struct allocation_info {
    /* all of information don't need marking. */
    int living;
    VALUE flags;
    VALUE klass;

    /* allocation info */
    unsigned int locindex;
    const char *class_path;
    VALUE mid;
    size_t generation;
};
struct allocation_info *objspace_lookup_allocation_info(VALUE obj);
unsigned int objspace_lookup_locindex(VALUE obj);

#endif
