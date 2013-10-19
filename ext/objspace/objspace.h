#ifndef OBJSPACE_H
#define OBJSPACE_H 1

/* objspace.c */
size_t objspace_memsize_of(VALUE obj);

/* object_tracing.c */
struct allocation_info {
    /* all of information don't need marking. */
    int living;
    VALUE flags;
    VALUE klass;

    /* allocation info */
    const char *path;
    unsigned long line;
    const char *class_path;
    VALUE mid;
    size_t generation;
};
struct allocation_info *objspace_lookup_allocation_info(VALUE obj);

#endif
